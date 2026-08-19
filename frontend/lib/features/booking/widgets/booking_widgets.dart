import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/booking.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';

/// Brand color for a booking status.
Color bookingStatusColor(String status) {
  switch (status) {
    case 'CONFIRMED':
    case 'COMPLETED':
      return AppColors.success;
    case 'IN_PROGRESS':
      return AppColors.primary;
    case 'CANCELLED':
    case 'NO_SHOW':
      return AppColors.error;
    default:
      return AppColors.warning;
  }
}

/// Icon shown alongside a booking status.
IconData bookingStatusIcon(String status) {
  switch (status) {
    case 'CONFIRMED':
      return Icons.check_circle_rounded;
    case 'COMPLETED':
      return Icons.task_alt_rounded;
    case 'IN_PROGRESS':
      return Icons.bolt_rounded;
    case 'CANCELLED':
      return Icons.cancel_rounded;
    case 'NO_SHOW':
      return Icons.person_off_rounded;
    default:
      return Icons.schedule_rounded;
  }
}

/// Status chip for a booking.
class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = bookingStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(bookingStatusIcon(status), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            statusLabel(status),
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'PENDING':
      return 'Pending';
    case 'CONFIRMED':
      return 'Confirmed';
    case 'IN_PROGRESS':
      return 'In progress';
    case 'COMPLETED':
      return 'Completed';
    case 'CANCELLED':
      return 'Cancelled';
    case 'NO_SHOW':
      return 'No show';
    default:
      return status.isEmpty ? 'Unknown' : status;
  }
}

/// List card for a booking in the customer's bookings tab.
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, this.onTap});

  final Booking booking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final start = booking.startAt;
    final statusColor = bookingStatusColor(booking.status);
    final professionalName = booking.professionalName.isEmpty
        ? 'Glamea professional'
        : booking.professionalName;
    final serviceName =
        booking.serviceName.isEmpty ? 'Service booking' : booking.serviceName;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppAvatar(name: professionalName, radius: 22),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  serviceName,
                                  style: AppTextStyles.title
                                      .copyWith(color: AppColors.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  professionalName,
                                  style: AppTextStyles.bodyMedium
                                      .copyWith(color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          BookingStatusChip(status: booking.status),
                        ],
                      ),
                      if (start != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(
                              '${Formatters.date(start)} at ${Formatters.time(start)}',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                      if (booking.homeService) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: [
                            const Icon(Icons.home_work_outlined,
                                size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                booking.locationAddress.isEmpty
                                    ? 'Home service'
                                    : booking.locationAddress,
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(height: 1, color: AppColors.borderSubtle),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Text(
                            Formatters.money(
                                booking.totalAmount, booking.currency),
                            style: AppTextStyles.price
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          if (booking.depositAmount > 0) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                '· ${Formatters.money(booking.depositAmount, booking.currency)} deposit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textMuted),
                              ),
                            ),
                          ],
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded,
                              size: 20, color: AppColors.textMuted),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
