import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/booking.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';

/// Professional bookings: filterable list with confirm/start/complete actions.
class ProBookingsTab extends ConsumerStatefulWidget {
  const ProBookingsTab({super.key});

  @override
  ConsumerState<ProBookingsTab> createState() => _ProBookingsTabState();
}

class _ProBookingsTabState extends ConsumerState<ProBookingsTab> {
  String _filter = 'ALL';
  final Set<String> _busy = {};

  static const _filters = [
    ('ALL', 'All'),
    ('PENDING', 'Pending'),
    ('CONFIRMED', 'Confirmed'),
    ('IN_PROGRESS', 'In progress'),
    ('COMPLETED', 'Completed'),
    ('CANCELLED', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proBookingsControllerProvider);
    final items = _filter == 'ALL'
        ? state.items
        : state.items.where((b) => b.status == _filter).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GlameaPageHeader(title: 'My bookings'),
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (_, i) {
                final (value, label) = _filters[i];
                final selected = _filter == value;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = value),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.softGrey,
                  labelStyle: AppTextStyles.bodyMedium.copyWith(
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                  side: BorderSide.none,
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proBookingsControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(state, items),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ProListState<Booking> state, List<Booking> items) {
    if (state.status == ProListStatus.loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonList(count: 5)],
      );
    }
    if (state.status == ProListStatus.error) {
      return ListView(
        children: [
          ErrorState(
            message: state.error ?? 'Could not load bookings.',
            onRetry: () => ref.read(proBookingsControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    if (items.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'No bookings here',
            message: 'New requests will show up here for you to confirm.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _BookingCard(
        booking: items[i],
        busy: _busy.contains(items[i].id),
        onAction: _runAction,
      ),
    );
  }

  Future<void> _runAction(Booking booking, String action) async {
    setState(() => _busy.add(booking.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final notifier = ref.read(proBookingsControllerProvider.notifier);
      await notifier.runAction(booking, action);
      final message = switch (action) {
        'confirm' => 'Booking confirmed',
        'start' => 'Booking started',
        'complete' => 'Booking completed',
        _ => 'Booking updated',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy.remove(booking.id));
    }
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.busy, required this.onAction});
  final Booking booking;
  final bool busy;
  final void Function(Booking, String) onAction;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (booking.status) {
      'PENDING' => AppColors.warning,
      'CONFIRMED' => AppColors.info,
      'IN_PROGRESS' => AppColors.primary,
      'COMPLETED' => AppColors.success,
      'CANCELLED' || 'NO_SHOW' => AppColors.error,
      _ => AppColors.textSecondary,
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.serviceName.isEmpty ? 'Service booking' : booking.serviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(booking.statusLabel, style: AppTextStyles.caption.copyWith(color: statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(icon: Icons.person_outline_rounded, text: booking.customerName.isEmpty ? 'Customer' : booking.customerName),
          _InfoRow(icon: Icons.calendar_today_rounded, text: '${Formatters.date(booking.startAt)} · ${Formatters.time(booking.startAt ?? DateTime.now())}'),
          if (booking.homeService && booking.locationAddress.isNotEmpty)
            _InfoRow(icon: Icons.home_work_outlined, text: booking.locationAddress),
          if (booking.customerNotes.isNotEmpty)
            _InfoRow(icon: Icons.notes_rounded, text: booking.customerNotes, multiline: true),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child:                 Text(
                  Formatters.money(booking.totalAmount, booking.currency),
                  style: AppTextStyles.price.copyWith(color: AppColors.primary),
                ),
              ),
              _ActionButtons(booking: booking, busy: busy, onAction: onAction),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.booking, required this.busy, required this.onAction});
  final Booking booking;
  final bool busy;
  final void Function(Booking, String) onAction;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
      );
    }
    final buttons = <Widget>[];
    if (booking.isPending) {
      buttons.addAll([
        FilledButton(
          onPressed: () => onAction(booking, 'confirm'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md)),
          child: const Text('Confirm'),
        ),
      ]);
    } else if (booking.isConfirmed) {
      buttons.add(FilledButton.icon(
        onPressed: () => onAction(booking, 'start'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md)),
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Start'),
      ));
    } else if (booking.status == 'IN_PROGRESS') {
      buttons.add(FilledButton.icon(
        onPressed: () => onAction(booking, 'complete'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md)),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Complete'),
      ));
    }
    return Wrap(spacing: AppSpacing.xs, children: buttons);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.multiline = false});
  final IconData icon;
  final String text;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              maxLines: multiline ? 3 : 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
