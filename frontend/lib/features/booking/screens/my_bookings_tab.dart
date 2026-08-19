import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/booking.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_states.dart';
import '../booking_controller.dart';
import '../widgets/booking_widgets.dart';

enum _BookingsFilter { all, upcoming, past }

/// Bookings tab (customer): upcoming and past bookings with filtering.
class MyBookingsTab extends ConsumerStatefulWidget {
  const MyBookingsTab({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  ConsumerState<MyBookingsTab> createState() => _MyBookingsTabState();
}

class _MyBookingsTabState extends ConsumerState<MyBookingsTab> {
  _BookingsFilter _filter = _BookingsFilter.all;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myBookingsControllerProvider);
    final upcomingCount = switch (state.status) {
      MyBookingsStatus.ready =>
        state.bookings.where(_isUpcoming).length,
      _ => 0,
    };

    return SafeArea(
      child: Column(
        children: [
          if (widget.showTitle)
            GlameaPageHeader(
              title: 'My bookings',
              subtitle: upcomingCount > 0
                  ? '$upcomingCount upcoming ${upcomingCount == 1 ? 'appointment' : 'appointments'}'
                  : 'No upcoming appointments',
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(myBookingsControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: switch (state.status) {
                MyBookingsStatus.loading => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: SkeletonList(count: 5),
                      ),
                    ],
                  ),
                MyBookingsStatus.error => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 400,
                        child: ErrorState(
                          message: state.error ?? 'Could not load your bookings.',
                          onRetry: () => ref
                              .read(myBookingsControllerProvider.notifier)
                              .refresh(),
                        ),
                      ),
                    ],
                  ),
                MyBookingsStatus.ready => _BookingsList(
                    bookings: state.bookings,
                    filter: _filter,
                    onFilterChanged: (filter) => setState(() => _filter = filter),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

bool _isUpcoming(Booking b) =>
    b.status == 'PENDING' ||
    b.status == 'CONFIRMED' ||
    b.status == 'IN_PROGRESS';

class _BookingsList extends StatelessWidget {
  const _BookingsList({
    required this.bookings,
    required this.filter,
    required this.onFilterChanged,
  });

  final List<Booking> bookings;
  final _BookingsFilter filter;
  final ValueChanged<_BookingsFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final upcoming = bookings.where(_isUpcoming).toList();
    final past = bookings.where((b) => !_isUpcoming(b)).toList();
    final visible = switch (filter) {
      _BookingsFilter.all => bookings,
      _BookingsFilter.upcoming => upcoming,
      _BookingsFilter.past => past,
    };

    if (bookings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.calendar_month_outlined,
            title: 'No bookings yet',
            message: 'Browse artists and book your first appointment.',
          ),
        ],
      );
    }

    final totalSpent = past
        .where((b) => b.status == 'COMPLETED')
        .fold<double>(0, (sum, b) => sum + b.totalAmount);
    final currency = bookings.first.currency;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            for (final option in _BookingsFilter.values) ...[
              if (option != _BookingsFilter.values.first)
                const SizedBox(width: AppSpacing.xs),
              _FilterPill(
                label: switch (option) {
                  _BookingsFilter.all => 'All',
                  _BookingsFilter.upcoming => 'Upcoming',
                  _BookingsFilter.past => 'Past',
                },
                count: switch (option) {
                  _BookingsFilter.all => bookings.length,
                  _BookingsFilter.upcoming => upcoming.length,
                  _BookingsFilter.past => past.length,
                },
                selected: filter == option,
                onTap: () => onFilterChanged(option),
              ),
            ],
            if (totalSpent > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Completed · ${Formatters.money(totalSpent, currency)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: EmptyState(
              icon: filter == _BookingsFilter.upcoming
                  ? Icons.event_available_outlined
                  : Icons.history_rounded,
              title: filter == _BookingsFilter.upcoming
                  ? 'No upcoming bookings'
                  : 'No past bookings',
              message: filter == _BookingsFilter.upcoming
                  ? 'When you book an appointment it will appear here.'
                  : 'Completed and cancelled bookings will appear here.',
            ),
          )
        else
          for (final booking in visible) ...[
            BookingCard(
              booking: booking,
              onTap: () => context.push(AppRoutes.bookingFor(booking.id)),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.white,
      borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: selected ? AppColors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: AppTextStyles.caption.copyWith(
                  color: selected
                      ? AppColors.white.withValues(alpha: 0.9)
                      : AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
