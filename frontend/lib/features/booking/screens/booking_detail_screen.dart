import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/disputes/screens/raise_dispute_screen.dart';
import '../../../features/reviews/data/review_api.dart';
import '../../../features/reviews/reviews_controller.dart';
import '../../../features/reviews/screens/review_sheet.dart';
import '../../../models/booking.dart';
import '../../../models/slot.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../../payments/payments_controller.dart';
import '../booking_controller.dart';
import '../data/booking_api.dart';
import '../widgets/booking_widgets.dart';

/// Booking detail with price breakdown, timeline and customer actions.
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingDetailProvider(id));

    return Scaffold(
      appBar: const GlameaAppBar(title: 'Booking details'),
      body: switch (async) {
        AsyncData(:final value) => _BookingBody(booking: value),
        AsyncError(:final error) => ErrorState(
            message: error is AppException
                ? error.message
                : 'Could not load this booking.',
            onRetry: () => ref.invalidate(bookingDetailProvider(id)),
          ),
        _ => const SkeletonBookingDetail(),
      },
    );
  }
}

class _BookingBody extends ConsumerWidget {
  const _BookingBody({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _StatusBanner(booking: booking),
        const SizedBox(height: AppSpacing.md),
        _InfoCard(booking: booking),
        const SizedBox(height: AppSpacing.lg),
        _PriceCard(booking: booking),
        if (booking.isUpcoming && booking.depositAmount > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          _PaymentSection(booking: booking),
        ],
        if (booking.customerNotes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Notes',
              style:
                  AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            booking.customerNotes,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (booking.cancelReason.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Cancellation reason',
              style:
                  AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            booking.cancelReason,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _TimelineSection(bookingId: booking.id),
        if (booking.cancellable ||
            booking.reschedulable ||
            booking.canMessage) ...[
          const SizedBox(height: AppSpacing.lg),
          _Actions(booking: booking),
        ],
        if (booking.canReview || booking.canDispute) ...[
          const SizedBox(height: AppSpacing.lg),
          _FeedbackActions(booking: booking),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final start = booking.startAt;
    final color = bookingStatusColor(booking.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusLabel(booking.status),
            style: AppTextStyles.title.copyWith(color: color),
          ),
          if (start != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${Formatters.date(start)} at ${Formatters.time(start)}',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            booking.serviceName.isEmpty
                ? 'Service booking'
                : booking.serviceName,
            style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              AppAvatar(name: booking.professionalName, radius: 16),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  booking.professionalName.isEmpty
                      ? 'Glamea professional'
                      : booking.professionalName,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (booking.startAt != null && booking.endAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  '${Formatters.time(booking.startAt!)} - ${Formatters.time(booking.endAt!)}',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
          if (booking.homeService) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.home_work_outlined,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    booking.locationAddress.isEmpty
                        ? 'Home service'
                        : booking.locationAddress,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          _row('Service price',
              Formatters.money(booking.baseAmount, booking.currency)),
          const SizedBox(height: AppSpacing.xs),
          _row('Deposit paid',
              Formatters.money(booking.depositAmount, booking.currency)),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: AppSpacing.sm),
          _row('Total', Formatters.money(booking.totalAmount, booking.currency),
              bold: true),
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

class _PaymentSection extends ConsumerWidget {
  const _PaymentSection({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final depositAsync = ref.watch(bookingDepositIntentProvider(booking.id));
    final depositPaid = depositAsync.valueOrNull?.isSucceeded ?? false;
    final balanceOutstanding = booking.balanceAmount > 0;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Payment',
                style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
              ),
              const Spacer(),
              if (depositPaid && !balanceOutstanding)
                Text(
                  'Fully paid',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(
            'Deposit',
            depositPaid
                ? 'Paid'
                : 'Outstanding (${Formatters.money(booking.depositAmount, booking.currency)})',
            valueColor: depositPaid ? AppColors.success : AppColors.textPrimary,
          ),
          if (balanceOutstanding) ...[
            const SizedBox(height: AppSpacing.xs),
            _row(
              'Balance',
              Formatters.money(booking.balanceAmount, booking.currency),
            ),
          ],
          if (!depositPaid && booking.depositAmount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      booking.isPending
                          ? 'A deposit is required before the artist can confirm this booking.'
                          : 'Pay the outstanding deposit for this booking.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Pay deposit to confirm (${Formatters.money(booking.depositAmount, booking.currency)})',
              icon: Icons.lock_outline_rounded,
              onPressed: () => _openPay(context, ref, 'DEPOSIT'),
            ),
          ],
          if (depositPaid && balanceOutstanding) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Pay balance (${Formatters.money(booking.balanceAmount, booking.currency)})',
              variant: AppButtonVariant.outline,
              icon: Icons.credit_card_rounded,
              onPressed: () => _openPay(context, ref, 'BALANCE'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openPay(BuildContext context, WidgetRef ref, String amountType) async {
    await context.push(
      AppRoutes.inAppPayment,
      extra: PaymentFlowArgs(bookingId: booking.id, amountType: amountType),
    );
    if (context.mounted) {
      ref.invalidate(bookingDepositIntentProvider(booking.id));
      // The payment may have settled while the checkout screen was open; refetch
      // so the balance and paid status reflect the server's totals.
      ref.invalidate(bookingDetailProvider(booking.id));
    }
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TimelineSection extends ConsumerWidget {
  const _TimelineSection({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(bookingHistoryProvider(bookingId));

    return history.maybeWhen(
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timeline',
                style:
                    AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  for (var i = 0; i < events.length; i++) ...[
                    _TimelineRow(
                        event: events[i], isLast: i == events.length - 1),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast});

  final BookingStatusEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(width: 2, height: 28, color: AppColors.borderSubtle),
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel(event.toStatus),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (event.createdAt != null)
                  Text(
                    Formatters.date(event.createdAt),
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted),
                  ),
                if (event.note.isNotEmpty)
                  Text(
                    event.note,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (booking.canMessage)
          AppButton(
            label: 'Message artist',
            variant: AppButtonVariant.outline,
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: () => context.push(AppRoutes.chatFor(booking.id)),
          ),
        if (booking.canMessage &&
            (booking.reschedulable || booking.cancellable))
          const SizedBox(height: AppSpacing.sm),
        if (booking.reschedulable)
          AppButton(
            label: 'Reschedule',
            variant: AppButtonVariant.outline,
            icon: Icons.event_repeat_rounded,
            onPressed: () async {
              final newStart = await showRescheduleSheet(
                context,
                professionalId: booking.professionalId,
                serviceDurationMinutes:
                    booking.startAt != null && booking.endAt != null
                        ? booking.endAt!.difference(booking.startAt!).inMinutes
                        : 60,
              );
              if (newStart == null || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(bookingApiProvider)
                    .rescheduleBooking(booking.id, newStart);
                if (!context.mounted) return;
                ref.invalidate(bookingDetailProvider(booking.id));
                ref.invalidate(myBookingsControllerProvider);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Booking rescheduled.')));
              } on AppException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('Could not reschedule. Please try again.')),
                );
              }
            },
          ),
        if (booking.reschedulable && booking.cancellable)
          const SizedBox(height: AppSpacing.sm),
        if (booking.cancellable)
          AppButton(
            label: 'Cancel booking',
            icon: Icons.event_busy_rounded,
            onPressed: () async {
              final reason = await showCancelSheet(context);
              if (reason == null || !context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(bookingApiProvider)
                    .cancelBooking(booking.id, reason);
                if (!context.mounted) return;
                ref.invalidate(bookingDetailProvider(booking.id));
                ref.invalidate(myBookingsControllerProvider);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Booking cancelled.')));
              } on AppException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text('Could not cancel. Please try again.')),
                );
              }
            },
          ),
      ],
    );
  }
}

/// Actions shown after a booking is completed: review + dispute.
class _FeedbackActions extends ConsumerWidget {
  const _FeedbackActions({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myReviews = ref.watch(myReviewsControllerProvider);
    final alreadyReviewed = myReviews.status == MyReviewsStatus.ready &&
        myReviews.items.any((r) => r.bookingId == booking.id);
    final showReview = booking.canReview && !alreadyReviewed;
    final showDispute = booking.canDispute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReview)
          AppButton(
            label: 'Leave a review',
            icon: Icons.star_rounded,
            onPressed: () => _leaveReview(context, ref),
          ),
        if (showReview && showDispute) const SizedBox(height: AppSpacing.sm),
        if (showDispute)
          AppButton(
            label: 'Raise a dispute',
            variant: AppButtonVariant.outline,
            icon: Icons.gavel_outlined,
            onPressed: () => context.push(
              AppRoutes.raiseDisputeFor(booking.id),
              extra: RaiseDisputeArgs(
                bookingId: booking.id,
                professionalName: booking.professionalName,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _leaveReview(BuildContext context, WidgetRef ref) async {
    final input = await showReviewSheet(context,
        professionalName: booking.professionalName);
    if (input == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(reviewApiProvider).createReview(
            bookingId: booking.id,
            rating: input.rating,
            comment: input.comment,
          );
      if (!context.mounted) return;
      ref.invalidate(myReviewsControllerProvider);
      messenger.showSnackBar(
          const SnackBar(content: Text('Thanks! Your review was submitted.')));
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not submit your review.')));
    }
  }
}

/// Bottom sheet that collects a cancellation reason.
Future<String?> showCancelSheet(BuildContext context) {
  final reason = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Cancel booking',
                style:
                    AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tell the artist why you are cancelling.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Confirm cancellation',
              icon: Icons.event_busy_rounded,
              onPressed: () =>
                  Navigator.of(sheetContext).pop(reason.text.trim()),
            ),
          ],
        ),
      );
    },
  ).whenComplete(reason.dispose);
}

/// Bottom sheet that picks a new date + slot.
Future<DateTime?> showRescheduleSheet(
  BuildContext context, {
  required String professionalId,
  required int serviceDurationMinutes,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _RescheduleSheet(
      professionalId: professionalId,
      serviceDurationMinutes: serviceDurationMinutes,
    ),
  );
}

class _RescheduleSheet extends ConsumerStatefulWidget {
  const _RescheduleSheet({
    required this.professionalId,
    required this.serviceDurationMinutes,
  });

  final String professionalId;
  final int serviceDurationMinutes;

  @override
  ConsumerState<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends ConsumerState<_RescheduleSheet> {
  DateTime? _date;
  List<AvailabilitySlot> _slots = const [];
  bool _loading = false;
  String? _error;
  DateTime? _selected;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadFor(DateTime.now());
  }

  Future<void> _loadFor(DateTime date) async {
    final requestId = ++_requestId;
    setState(() {
      _date = date;
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final slots = await ref.read(bookingApiProvider).fetchSlots(
            widget.professionalId,
            date: date,
            durationMinutes: widget.serviceDurationMinutes,
          );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _slots = slots;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _slots = const [];
        _loading = false;
        _error =
            e is AppException ? e.message : 'Could not load available times.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Reschedule',
              style:
                  AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          _MiniDateStrip(selected: _date, onSelected: _loadFor),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: CircularProgressIndicator(color: AppColors.primary)))
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.error)),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Try again',
                  variant: AppButtonVariant.outline,
                  expanded: false,
                  onPressed: () => _loadFor(_date ?? DateTime.now()),
                ),
              ],
            )
          else if (_slots.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('No times available on this day.'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots)
                  _SlotChip(
                    label: Formatters.time(slot.start),
                    selected: _selected != null &&
                        slot.start.toUtc().isAtSameMomentAs(_selected!.toUtc()),
                    onTap: () => setState(() => _selected = slot.start),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: _selected == null ? 'Select a new time' : 'Confirm new time',
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected),
          ),
        ],
      ),
    );
  }
}

class _MiniDateStrip extends StatelessWidget {
  const _MiniDateStrip({required this.selected, required this.onSelected});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dates = [
      for (var i = 0; i < 14; i++)
        DateTime(today.year, today.month, today.day).add(Duration(days: i)),
    ];
    return SizedBox(
      height: 52,
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
          return InkWell(
            onTap: () => onSelected(date),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.white,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.borderSubtle),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    Formatters.dayShort(date).split(', ').first,
                    style: AppTextStyles.caption.copyWith(
                      color: isSelected
                          ? AppColors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${date.day}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color:
                          isSelected ? AppColors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderSubtle),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: selected ? AppColors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
