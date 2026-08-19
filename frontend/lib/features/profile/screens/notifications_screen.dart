import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/notification_item.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_states.dart';
import '../profile_controller.dart';

/// Notification inbox with unread emphasis and read actions.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);

    return Scaffold(
      appBar: GlameaAppBar(
        title: 'Notifications',
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref.read(notificationsControllerProvider.notifier).markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: switch (state.status) {
        NotificationsStatus.loading => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: SkeletonList(count: 6),
          ),
        NotificationsStatus.error => ErrorState(
            message: state.error ?? 'Could not load notifications.',
            onRetry: () => ref.read(notificationsControllerProvider.notifier).refresh(),
          ),
        NotificationsStatus.ready => RefreshIndicator(
            onRefresh: () => ref.read(notificationsControllerProvider.notifier).refresh(),
            color: AppColors.primary,
            child: state.items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'You are all caught up',
                        message: 'Booking updates and messages from your artists will appear here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final notification = state.items[index];
                      return _NotificationTile(
                        notification: notification,
                        onTap: () {
                          if (!notification.isRead) {
                            ref.read(notificationsControllerProvider.notifier).markRead(notification.id);
                          }
                          _openNotification(context, notification);
                        },
                      );
                    },
                  ),
          ),
      },
    );
  }
}

/// Booking/message/payment notifications deep-link to the booking they relate to.
void _openNotification(BuildContext context, GlameaNotification notification) {
  const bookingTypes = {
    'booking',
    'booking_created',
    'booking_confirmed',
    'booking_cancelled',
    'payment',
    'earning',
  };
  if (!bookingTypes.contains(notification.type)) return;
  final bookingId = notification.data?['booking_id'] as String?;
  if (bookingId == null || bookingId.isEmpty) return;
  context.push(AppRoutes.bookingFor(bookingId));
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final GlameaNotification notification;
  final VoidCallback onTap;

  IconData get _icon {
    switch (notification.type) {
      case 'booking' || 'booking_created' || 'booking_confirmed' || 'booking_cancelled':
        return Icons.calendar_month_outlined;
      case 'message' || 'message_received':
        return Icons.chat_bubble_outline_rounded;
      case 'payment':
        return Icons.payments_outlined;
      case 'review':
        return Icons.star_outline_rounded;
      case 'deal':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: notification.isRead ? AppColors.white : AppColors.roseGold.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.roseGold.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (notification.createdAt != null)
                          Text(
                            Formatters.relativeTime(notification.createdAt!),
                            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                          ),
                      ],
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (!notification.isRead) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
