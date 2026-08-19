import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../features/booking/booking_controller.dart';
import '../../../features/profile/profile_controller.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';

/// Profile tab (customer): identity, activity summary and account actions.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final notifications = ref.watch(notificationsControllerProvider);
    final bookings = ref.watch(myBookingsControllerProvider);

    final user = profile.status == ProfileStatus.ready
        ? (profile.user ?? auth.user)
        : auth.user;
    final unread = notifications.status == NotificationsStatus.ready
        ? notifications.unreadCount
        : 0;
    final bookingsCount =
        bookings.status == MyBookingsStatus.ready ? bookings.bookings.length : 0;

    if (profile.status == ProfileStatus.error && user == null) {
      return SafeArea(
        child: Column(
          children: [
            const GlameaPageHeader(title: 'Profile'),
            Expanded(
              child: ErrorState(
                message: profile.error ?? 'Could not load your profile.',
                onRetry: () => ref.read(profileControllerProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          const GlameaPageHeader(title: 'Profile'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(profileControllerProvider.notifier).refresh();
                await ref.read(notificationsControllerProvider.notifier).refresh();
                await ref.read(myBookingsControllerProvider.notifier).refresh();
              },
              color: AppColors.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _HeaderCard(user: user, onEdit: () => context.push(AppRoutes.editProfile)),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.calendar_month_outlined,
                          value: bookingsCount,
                          label: 'Bookings',
                          onTap: () => context.push(AppRoutes.bookingList),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.notifications_none_rounded,
                          value: unread,
                          label: 'Unread',
                          onTap: () => context.push(AppRoutes.notifications),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Account', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        _MenuRow(
                          icon: Icons.notifications_outlined,
                          label: 'Notifications',
                    onTap: () => context.push(AppRoutes.notifications),
                    badge: unread > 0 ? unread : null,
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  if (user?.email?.isNotEmpty == true && user?.emailVerified == false) ...[
                    _MenuRow(
                      icon: Icons.verified_outlined,
                      label: 'Verify email',
                      onTap: () => context.push(AppRoutes.verifyEmail),
                    ),
                    const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  ],
                  _MenuRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'My bookings',
                    onTap: () => context.push(AppRoutes.bookingList),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    onTap: () => context.push(AppRoutes.wallet),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(
                    icon: Icons.favorite_outline_rounded,
                    label: 'Favorites',
                    onTap: () => context.push(AppRoutes.favorites),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(
                    icon: Icons.star_outline_rounded,
                    label: 'My reviews',
                    onTap: () => context.push(AppRoutes.myReviews),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(
                    icon: Icons.gavel_outlined,
                    label: 'Disputes',
                    onTap: () => context.push(AppRoutes.disputes),
                  ),
                  if (user?.role == 'PROFESSIONAL') ...[
                    const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                    _MenuRow(
                      icon: Icons.storefront_outlined,
                      label: 'Professional studio',
                      onTap: () => context.go(AppRoutes.pro),
                    ),
                  ],
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(
                    icon: Icons.logout_rounded,
                    label: 'Log out',
                    danger: true,
                    onTap: () => _confirmLogout(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
        ),
      ),
      ],
    ),
  );
}

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        title: const Text('Log out?'),
        content: const Text('You can log back in anytime with your email or phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.user, required this.onEdit});

  final User? user;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final name = user?.fullName.isNotEmpty == true ? user!.fullName : 'Glamea customer';
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          AppAvatar(name: name, radius: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headline2),
                if (user?.phone?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    user!.phone!,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                if (user?.email?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    user!.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Icon(icon, color: AppColors.roseGold),
              const SizedBox(height: AppSpacing.xs),
              Text('$value', style: AppTextStyles.headline2.copyWith(color: AppColors.primary)),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    final iconColor = danger ? AppColors.error : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: AppTextStyles.caption.copyWith(color: AppColors.white, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              color: danger ? AppColors.error : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
