import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';
import 'pro_deals_tab.dart';
import 'pro_payouts_tab.dart';
import 'pro_portfolio_tab.dart';
import 'pro_profile_setup_screen.dart';
import 'pro_reviews_tab.dart';
import 'pro_verification_tab.dart';

/// Professional account: profile snapshot, sub-section links and logout.
class ProAccountTab extends ConsumerWidget {
  const ProAccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(proProfileControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final pro = profileState.profile;
    final verificationStatus = pro?.verificationStatus ?? 'UNVERIFIED';

    if (profileState.status == ProListStatus.error && pro == null) {
      return SafeArea(
        child: Column(
          children: [
            const GlameaPageHeader(title: 'Account'),
            Expanded(
              child: ErrorState(
                message: profileState.error ?? 'Could not load your professional profile.',
                onRetry: () => ref.read(proProfileControllerProvider.notifier).refresh(),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          const GlameaPageHeader(title: 'Account'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(proProfileControllerProvider.notifier).refresh();
                await ref.read(proBookingsControllerProvider.notifier).refresh();
              },
              color: AppColors.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(color: AppColors.softGrey, shape: BoxShape.circle),
                          child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 28),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pro?.name ?? auth.user?.fullName ?? 'Studio', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headline2),
                              Text(
                                pro?.location.isNotEmpty == true ? pro!.location : 'Professional account',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        _VerificationBadge(status: verificationStatus),
                      ],
                    ),
                  ),
            const SizedBox(height: AppSpacing.lg),
            Text('Studio', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  if (pro == null)
                    _MenuRow(
                      icon: Icons.add_business_outlined,
                      label: 'Set up your studio',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ProProfileSetupScreen()),
                      ),
                    ),
                  if (pro == null) const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(icon: Icons.photo_library_outlined, label: 'Portfolio', onTap: () => _open(context, 'Portfolio', const ProPortfolioTab())),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(icon: Icons.local_offer_outlined, label: 'Deals & promos', onTap: () => _open(context, 'Deals & promos', const ProDealsTab())),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(icon: Icons.star_outline_rounded, label: 'Reviews', onTap: () => _open(context, 'Reviews', const ProReviewsTab())),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(icon: Icons.verified_outlined, label: 'Verification', onTap: () => _open(context, 'Verification', const ProVerificationTab())),
                  const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                  _MenuRow(icon: Icons.account_balance_wallet_outlined, label: 'Payouts', onTap: () => _open(context, 'Payouts', const ProPayoutsTab())),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Account', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.storefront_outlined,
                    label: 'Browse as customer',
                    onTap: () => context.go(AppRoutes.home),
                  ),
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
  void _open(BuildContext context, String title, Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.surface,
          appBar: GlameaAppBar(title: title),
          body: child,
        ),
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
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final verified = status == 'VERIFIED';
    final color = verified ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verified ? Icons.verified_rounded : Icons.verified_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Text(verified ? 'Verified' : 'Unverified', style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? AppColors.error : AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: color))),
            Icon(Icons.chevron_right_rounded, size: 20, color: danger ? AppColors.error : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
