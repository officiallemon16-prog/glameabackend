import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/booking.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../../payments/payments_controller.dart';
import '../../../models/payment.dart';
import '../booking_controller.dart';

/// Multi-step booking wizard: date -> time slot -> details -> confirm.
class BookingFlowScreen extends ConsumerWidget {
  const BookingFlowScreen({super.key, required this.args});

  final BookingFlowArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookingFlowProvider(args));
    final controller = ref.read(bookingFlowProvider(args).notifier);
    final created = state.createdBooking;

    if (created != null && created.depositAmount > 0 && !state.paymentHandled) {
      return _PendingPaymentScreen(
        booking: created,
        args: args,
        onPayNow: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _PaymentSheet(
              bookingId: created.id,
              booking: created,
              onSuccess: () => controller.markPaymentHandled(),
            ),
          );
        },
        onViewBooking: () => context.push(AppRoutes.bookingFor(created.id)),
        onDone: () => context.pop(),
      );
    }

    if (created != null) {
      return _SuccessScreen(
        booking: created,
        onViewBooking: () => context.push(AppRoutes.bookingFor(created.id)),
      );
    }

    return Scaffold(
      appBar: const GlameaAppBar(title: 'Book appointment'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _ServiceHeader(state: state),
          const SizedBox(height: AppSpacing.lg),
          Text('Pick a date', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          _DateStrip(
            selected: state.selectedDate,
            onSelected: controller.selectDate,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Available times', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          _SlotsSection(
            state: state,
            onSelectSlot: controller.selectSlot,
            onRetry: controller.retrySlots,
          ),
          if (state.homeServiceAvailable) ...[
            const SizedBox(height: AppSpacing.lg),
            _HomeServiceSection(
              state: state,
              onToggle: controller.setHomeService,
              onAddressChanged: controller.setAddress,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Notes for your artist', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          _NotesField(
            initialValue: state.notes,
            onChanged: controller.setNotes,
          ),
          const SizedBox(height: AppSpacing.lg),
          _PriceSummary(state: state),
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: state.selectedStart == null
                ? 'Select a time to continue'
                : state.addressRequired
                    ? 'Add your address to continue'
                    : 'Book',
            icon: Icons.check_circle_outline_rounded,
            loading: state.submitting,
            onPressed: state.readyToSubmit
                ? () {
                    HapticFeedback.mediumImpact();
                    controller.submit();
                  }
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({required this.state});

  final BookingFlowState state;

  @override
  Widget build(BuildContext context) {
    final service = state.service;
    final professional = state.professional;
    return AppCard(
      child: Row(
        children: [
          AppAvatar(name: professional.name, radius: 26),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  professional.name,
                  style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${service.name} · ${Formatters.duration(service.durationMinutes)}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            Formatters.money(service.basePrice, service.currency),
            style: AppTextStyles.price.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelected});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dates = [
      for (var i = 0; i < 30; i++)
        DateTime(today.year, today.month, today.day).add(Duration(days: i)),
    ];

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = selected != null &&
              selected!.year == date.year &&
              selected!.month == date.month &&
              selected!.day == date.day;
          return _DayChip(
            date: date,
            selected: isSelected,
            onTap: () => onSelected(date),
          );
        },
      ),
    );
  }

  static String weekday(DateTime date) => _days[date.weekday - 1];
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date, required this.selected, required this.onTap});

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.textSecondary;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.entrance,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 64,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.md),
            border: Border.all(color: selected ? AppColors.primary : AppColors.borderSubtle),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _DateStrip.weekday(date),
                style: AppTextStyles.caption.copyWith(color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.day}',
                style: AppTextStyles.title.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotsSection extends StatelessWidget {
  const _SlotsSection({
    required this.state,
    required this.onSelectSlot,
    required this.onRetry,
  });

  final BookingFlowState state;
  final ValueChanged<DateTime> onSelectSlot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (state.slotStatus) {
      case SlotLoadStatus.idle:
        return Text(
          'Select a date above to see available times.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
        );
      case SlotLoadStatus.loading:
        return const Wrap(spacing: 8, runSpacing: 8, children: [
          _SlotSkeleton(),
          _SlotSkeleton(),
          _SlotSkeleton(),
        ]);
      case SlotLoadStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.slotError ?? 'Could not load available times.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Try again',
              variant: AppButtonVariant.outline,
              expanded: false,
              onPressed: onRetry,
            ),
          ],
        );
      case SlotLoadStatus.ready:
        if (state.slots.isEmpty) {
          return const EmptyState(
            icon: Icons.schedule_outlined,
            title: 'No times available',
            message: 'Try picking another day.',
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final slot in state.slots)
              _SlotChip(
                label: Formatters.time(slot.start),
                selected: state.selectedStart != null &&
                    slot.start.toUtc().isAtSameMomentAs(state.selectedStart!.toUtc()),
                onTap: () => onSelectSlot(slot.start),
              ),
          ],
        );
    }
  }
}

class _SlotSkeleton extends StatelessWidget {
  const _SlotSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppSkeleton(width: 88, height: 40, radius: AppSpacing.sm);
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.entrance,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            border: Border.all(color: selected ? AppColors.primary : AppColors.borderSubtle),
          ),
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: selected ? AppColors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeServiceSection extends StatefulWidget {
  const _HomeServiceSection({
    required this.state,
    required this.onToggle,
    required this.onAddressChanged,
  });

  final BookingFlowState state;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onAddressChanged;

  @override
  State<_HomeServiceSection> createState() => _HomeServiceSectionState();
}

class _HomeServiceSectionState extends State<_HomeServiceSection> {
  bool _addressTouched = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final addressEmpty = state.address.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Home service', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          subtitle: Text(
            'Have them come to you',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
          activeTrackColor: AppColors.primary,
          value: state.homeService,
          onChanged: (value) {
            HapticFeedback.selectionClick();
            widget.onToggle(value);
          },
        ),
        if (state.homeService) ...[
          const SizedBox(height: AppSpacing.xs),
          TextField(
            onChanged: (value) {
              _addressTouched = true;
              widget.onAddressChanged(value);
            },
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Home or office address',
              prefixIcon: const Icon(Icons.location_on_outlined),
              errorText:
                  addressEmpty && _addressTouched ? 'Enter your address to continue' : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      maxLines: 3,
      maxLength: 300,
      decoration: const InputDecoration(
        hintText: 'Anything they should know?',
        alignLabelWithHint: true,
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({required this.state});

  final BookingFlowState state;

  @override
  Widget build(BuildContext context) {
    final service = state.service;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          _row('Service price', Formatters.money(service.basePrice, service.currency)),
          const SizedBox(height: AppSpacing.xs),
          _row('Deposit (due now)', Formatters.money(state.depositAmount, service.currency)),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: AppSpacing.sm),
          _row(
            'Balance at service',
            Formatters.money(state.balanceAmount, service.currency),
            bold: true,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final labelStyle = bold
        ? AppTextStyles.bodyMedium
        : AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary);
    final valueStyle = bold
        ? AppTextStyles.price.copyWith(color: AppColors.textPrimary)
        : AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: labelStyle),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({required this.booking, required this.onViewBooking});

  final Booking booking;
  final VoidCallback onViewBooking;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Booking confirmed', showBack: false),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: AppMotion.slow,
              curve: Curves.elasticOut,
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 56),
              ),
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'You\u2019re booked!',
              style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your request is pending. The artist will confirm your appointment shortly.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const Spacer(),
            AppButton(
              label: 'View booking',
              icon: Icons.event_rounded,
              onPressed: onViewBooking,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Done',
              variant: AppButtonVariant.outline,
              onPressed: () => context.pop(),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending Payment — shown after booking is created and deposit is due.
// ---------------------------------------------------------------------------

class _PendingPaymentScreen extends StatelessWidget {
  const _PendingPaymentScreen({
    required this.booking,
    required this.args,
    required this.onPayNow,
    required this.onViewBooking,
    required this.onDone,
  });

  final Booking booking;
  final BookingFlowArgs args;
  final VoidCallback onPayNow;
  final VoidCallback onViewBooking;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Booking created', showBack: false),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: AppMotion.slow,
              curve: Curves.elasticOut,
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_rounded, color: Colors.white, size: 56),
              ),
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'You\u2019re booked!',
              style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A deposit is required to confirm your appointment.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  _infoRow('Service', booking.serviceName),
                  const SizedBox(height: AppSpacing.xs),
                  _infoRow('Deposit due', Formatters.money(booking.depositAmount, booking.currency)),
                  const SizedBox(height: AppSpacing.xs),
                  _infoRow('Balance at service', Formatters.money(booking.balanceAmount, booking.currency)),
                ],
              ),
            ),
            const Spacer(),
            AppButton(
              label: 'Pay deposit · ${Formatters.money(booking.depositAmount, booking.currency)}',
              icon: Icons.payment_rounded,
              onPressed: onPayNow,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'View booking',
              variant: AppButtonVariant.outline,
              icon: Icons.event_rounded,
              onPressed: onViewBooking,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Done',
              variant: AppButtonVariant.outline,
              onPressed: onDone,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        Text(value, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Payment Sheet — modal bottom sheet that creates an intent, opens checkout,
// polls for status, and shows confetti on success.
// ---------------------------------------------------------------------------

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.bookingId, required this.booking, this.onSuccess});

  final String bookingId;
  final Booking booking;
  final VoidCallback? onSuccess;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet>
    with SingleTickerProviderStateMixin {
  late final PaymentFlowArgs _flowArgs;
  bool _launched = false;
  bool _celebrated = false;
  late final ConfettiController _confettiController;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _flowArgs = PaymentFlowArgs(bookingId: widget.bookingId, amountType: 'DEPOSIT');
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startPayment();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _startPayment() async {
    await ref.read(paymentFlowProvider(_flowArgs).notifier).start();
  }

  void _openCheckout(String url) {
    if (_launched) return;
    _launched = true;
    // Open the gateway page in an in-app WebView (full screen) instead of
    // spawning a separate browser app, which many OEMs/ROMs block or silently
    // drop - that was leaving the sheet stuck on a spinner.
    ref.read(paymentFlowProvider(_flowArgs).notifier).startPolling(
          intervalSeconds: 3,
          maxTries: 40,
        );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _EmbeddedCheckoutScreen(
          flowArgs: _flowArgs,
          url: url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider(_flowArgs));
    final intent = flow.intent;

    if (flow.status == PaymentFlowStatus.succeeded && !_celebrated) {
      _celebrated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _confettiController.play();
          _scaleController.forward();
          widget.onSuccess?.call();
        }
      });
    }

    final hasAuthUrl = intent?.authorizationUrl != null && intent!.authorizationUrl!.isNotEmpty;
    if (hasAuthUrl && !_launched) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openCheckout(intent!.authorizationUrl!);
      });
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (flow.status == PaymentFlowStatus.succeeded)
              _buildSuccess()
            else if (flow.status == PaymentFlowStatus.failed)
              _buildError(flow)
            else
              _buildProcessing(intent),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                AppColors.primary,
                AppColors.success,
                Colors.amber,
                Colors.pink,
                Colors.blue,
              ],
              emissionFrequency: 0.08,
              numberOfParticles: 20,
              gravity: 0.15,
            ),
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Payment Successful!',
          style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your deposit has been confirmed.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'View booking',
          icon: Icons.event_rounded,
          onPressed: () {
            Navigator.of(context).pop();
            context.push(AppRoutes.bookingFor(widget.bookingId));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Done',
          variant: AppButtonVariant.outline,
          onPressed: () {
            Navigator.of(context).pop();
            widget.onSuccess?.call();
          },
        ),
      ],
    );
  }

  Widget _buildError(PaymentFlowState flow) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
        const SizedBox(height: AppSpacing.md),
        Text(
          flow.error ?? 'Payment failed. Please try again.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: () {
            _launched = false;
            ref.read(paymentFlowProvider(_flowArgs).notifier).start();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildProcessing(PaymentIntent? intent) {
    final hasUrl = intent?.authorizationUrl != null && intent!.authorizationUrl!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hasUrl) ...[
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Processing your payment...',
            style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Please wait while we set up your payment.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ] else ...[
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'A payment page is open.',
            style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Complete your payment in the page that opened.\nThis page updates automatically once it succeeds.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          if (intent?.gatewayReference != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ref: ${intent!.gatewayReference}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'I completed payment',
            icon: Icons.check_circle_outline_rounded,
            onPressed: () {
              ref.read(paymentFlowProvider(_flowArgs).notifier).checkStatus();
            },
          ),
        ],
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
    );
  }
}

// ---------------------------------------------------------------------------
// Embedded checkout — full-screen in-app WebView for the gateway page. Watches
// the flow and returns to the sheet once the backend marks it terminal.
// ---------------------------------------------------------------------------

class _EmbeddedCheckoutScreen extends ConsumerStatefulWidget {
  const _EmbeddedCheckoutScreen({required this.flowArgs, required this.url});

  final PaymentFlowArgs flowArgs;
  final String url;

  @override
  ConsumerState<_EmbeddedCheckoutScreen> createState() => _EmbeddedCheckoutScreenState();
}

class _EmbeddedCheckoutScreenState extends ConsumerState<_EmbeddedCheckoutScreen> {
  late final WebViewController _controller;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_looksLikeSuccess(request.url)) _markVerifying();
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            if (_looksLikeSuccess(url)) _markVerifying();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Once the backend marks the intent terminal we return to the sheet,
    // which then celebrates (success) or shows the error.
    ref.listenManual(paymentFlowProvider(widget.flowArgs), (previous, next) {
      if (!mounted) return;
      if (next.status == PaymentFlowStatus.succeeded) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.of(context).pop();
        });
      } else if (next.status == PaymentFlowStatus.failed) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  bool _looksLikeSuccess(String url) {
    final lower = url.toLowerCase();
    return lower.contains('glamea://') ||
        lower.contains('status=success') ||
        lower.contains('status=complete') ||
        lower.contains('&paid=') ||
        lower.contains('tx_ref=') ||
        lower.contains('trxref=') ||
        lower.contains('/callback') ||
        lower.contains('/return');
  }

  void _markVerifying() {
    if (!mounted) return;
    setState(() => _verifying = true);
    ref.read(paymentFlowProvider(widget.flowArgs).notifier).checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlameaAppBar(
        title: 'Complete payment',
        showBack: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () {
              ref.read(paymentFlowProvider(widget.flowArgs).notifier).checkStatus();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_verifying)
            Container(
              color: Colors.black45,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: AppSpacing.md),
                      Text('Verifying your payment…'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
