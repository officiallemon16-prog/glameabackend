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
import '../../../models/professional.dart';
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

/// Pro dashboard: profile, balance, KPIs, quick actions and upcoming bookings.
class ProDashboardTab extends ConsumerWidget {
  const ProDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(proProfileControllerProvider);
    final bookingsState = ref.watch(proBookingsControllerProvider);
    final earningsState = ref.watch(proEarningsControllerProvider);
    final hasProfile =
        profileState.status == ProListStatus.ready && profileState.profile != null;

    return SafeArea(
      child: Column(
        children: [
          const GlameaPageHeader(title: 'Studio dashboard'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(proProfileControllerProvider.notifier).refresh();
                await ref.read(proBookingsControllerProvider.notifier).refresh();
                await ref.read(proEarningsControllerProvider.notifier).refresh();
              },
              color: AppColors.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _buildProfile(context, ref, profileState),
                  if (hasProfile) ...[
                    const SizedBox(height: AppSpacing.md),
                    _buildBalance(context, ref, earningsState),
                    const SizedBox(height: AppSpacing.md),
                    _buildBrowseAsCustomer(context),
                    const SizedBox(height: AppSpacing.md),
                    _buildStats(context, bookingsState, profileState.profile?.rating ?? 0),
                    const SizedBox(height: AppSpacing.md),
                    _buildEarnings(context, ref, earningsState),
                    const SizedBox(height: AppSpacing.lg),
                    const _SectionHeader(title: 'Manage your studio'),
                    const SizedBox(height: AppSpacing.sm),
                    _buildQuickActions(context),
                    const SizedBox(height: AppSpacing.lg),
                    const _SectionHeader(title: 'Upcoming bookings'),
                    const SizedBox(height: AppSpacing.sm),
                    _buildUpcoming(context, ref, bookingsState),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile(BuildContext context, WidgetRef ref, ProProfileState state) {
    switch (state.status) {
      case ProListStatus.loading:
        return const AppCard(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                AppSkeleton(width: 56, height: 56, radius: 28),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeleton(width: 150, height: 16),
                      SizedBox(height: AppSpacing.xs),
                      AppSkeleton(width: 90, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case ProListStatus.error:
        return ErrorState(
          message: state.error ?? 'Could not load your profile.',
          onRetry: () => ref.read(proProfileControllerProvider.notifier).refresh(),
        );
      case ProListStatus.ready:
        final pro = state.profile;
        if (pro == null) {
          return EmptyState(
            icon: Icons.storefront_outlined,
            title: 'No profile yet',
            message: 'Set up your studio to get started.',
            actionLabel: 'Set up your studio',
            onAction: () => _openSetup(context),
          );
        }
        return AppCard(
          child: Row(
            children: [
              _AvatarBadge(pro: pro),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pro.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headline2),
                    if (pro.location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(pro.location, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: _VerificationChip(status: pro.verificationStatus)),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textSecondary),
            ],
          ),
        );
    }
  }

  void _openSetup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProProfileSetupScreen()),
    );
  }

  /// Prominent link back to the customer side of the app.
  Widget _buildBrowseAsCustomer(BuildContext context) {
    return AppCard(
      color: AppColors.softGrey,
      shadow: false,
      onTap: () => _browseAsCustomer(context),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Browse as customer',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Scroll other pros & their services',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildStats(BuildContext context, ProListState<Booking> bookingsState, double rating) {
    final upcoming = bookingsState.items
        .where((b) => b.isPending || b.isConfirmed || b.status == 'IN_PROGRESS')
        .length;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.schedule_rounded,
              value: '$upcoming',
              label: 'Upcoming',
            ),
          ),
          _statDivider(),
          Expanded(
            child: _Stat(
              icon: Icons.calendar_month_rounded,
              value: '${bookingsState.items.length}',
              label: 'Total bookings',
            ),
          ),
          _statDivider(),
          Expanded(
            child: _Stat(
              icon: Icons.star_rounded,
              value: rating.toStringAsFixed(1),
              label: 'Rating',
              onTap: () => _openSub(context, 'Reviews', const ProReviewsTab()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 1, height: 32, color: AppColors.borderSubtle);
  }

  Widget _buildBalance(BuildContext context, WidgetRef ref, ProEarningsState state) {
    if (state.status != ProListStatus.ready) {
      return _buildEarnings(context, ref, state);
    }
    final e = state.earnings;
    return AppCard(
      color: AppColors.primary,
      shadow: true,
      onTap: () => _openPayouts(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 4),
          Text(
            Formatters.money(e.available, e.currency),
            style: AppTextStyles.headline1.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _BalanceChip(label: 'Pending', value: Formatters.money(e.pending, e.currency)),
              const SizedBox(width: AppSpacing.sm),
              _BalanceChip(label: 'Wallet', value: Formatters.money(e.walletBalance, e.currency)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => _openPayouts(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.white, foregroundColor: AppColors.primary),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnings(BuildContext context, WidgetRef ref, ProEarningsState state) {
    switch (state.status) {
      case ProListStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: AppSkeleton(
                  height: 76,
                  radius: AppDimens.cardRadiusMobile,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppSkeleton(
                  height: 76,
                  radius: AppDimens.cardRadiusMobile,
                ),
              ),
            ],
          ),
        );
      case ProListStatus.error:
        return ErrorState(
          message: state.error ?? 'Could not load earnings.',
          onRetry: () => ref.read(proEarningsControllerProvider.notifier).refresh(),
        );
      case ProListStatus.ready:
        final e = state.earnings;
        return Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Total earned',
                value: Formatters.money(e.totalEarned, e.currency),
                onTap: () => _openPayouts(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _KpiCard(
                label: 'This week',
                value: Formatters.money(e.thisWeek, e.currency),
                onTap: () => _openPayouts(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _KpiCard(
                label: 'This month',
                value: Formatters.money(e.thisMonth, e.currency),
                onTap: () => _openPayouts(context),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickActionTile(
                icon: Icons.photo_library_outlined,
                label: 'Portfolio',
                onTap: () => _openSub(context, 'Portfolio', const ProPortfolioTab()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _QuickActionTile(
                icon: Icons.local_offer_outlined,
                label: 'Deals & promos',
                onTap: () => _openSub(context, 'Deals & promos', const ProDealsTab()),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _QuickActionTile(
                icon: Icons.star_outline_rounded,
                label: 'Reviews',
                onTap: () => _openSub(context, 'Reviews', const ProReviewsTab()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _QuickActionTile(
                icon: Icons.verified_outlined,
                label: 'Verification',
                onTap: () => _openSub(context, 'Verification', const ProVerificationTab()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpcoming(BuildContext context, WidgetRef ref, ProListState<Booking> bookingsState) {
    if (bookingsState.status == ProListStatus.error) {
      return ErrorState(
        message: bookingsState.error ?? 'Could not load your bookings.',
        onRetry: () => ref.read(proBookingsControllerProvider.notifier).refresh(),
      );
    }
    final upcoming = bookingsState.items
        .where((b) => b.isPending || b.isConfirmed || b.status == 'IN_PROGRESS')
        .toList()
      ..sort((a, b) {
        final at = a.startAt;
        final bt = b.startAt;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    if (upcoming.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.event_available_outlined, color: AppColors.roseGold, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'No upcoming bookings yet. Share your services to get booked.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final booking in upcoming.take(3)) ...[
          _UpcomingBookingTile(booking: booking),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  void _openPayouts(BuildContext context) {
    _openSub(context, 'Payouts', const ProPayoutsTab());
  }

  /// Returns to the customer side of the app to browse other pros.
  void _browseAsCustomer(BuildContext context) {
    try {
      GoRouter.of(context).go(AppRoutes.home);
    } catch (_) {
      // Fallback for the standalone preview where no router is mounted.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer home is not available in this preview.'),
        ),
      );
    }
  }

  void _openSub(BuildContext context, String title, Widget child) {
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
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            Text(value, style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Small KPI card with a label and value.
class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.title.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.softGrey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _UpcomingBookingTile extends StatelessWidget {
  const _UpcomingBookingTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final (color, label) = _status(booking);
    final time = booking.startAt == null
        ? 'Time not set'
        : '${Formatters.date(booking.startAt)} · ${Formatters.time(booking.startAt!)}';
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.person_outline_rounded, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.customerName.isEmpty ? 'New booking' : booking.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (booking.serviceName.isNotEmpty) booking.serviceName,
                    time,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  (Color, String) _status(Booking booking) {
    return switch (booking.status) {
      'CONFIRMED' => (AppColors.success, 'Confirmed'),
      'IN_PROGRESS' => (AppColors.primary, 'In progress'),
      _ => (AppColors.warning, 'Pending'),
    };
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.pro});
  final Professional pro;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.softGrey,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.storefront_rounded,
        color: AppColors.primary,
        size: 26,
      ),
    );
  }
}

class _VerificationChip extends StatelessWidget {
  const _VerificationChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'VERIFIED'
        ? AppColors.success
        : status == 'REJECTED'
            ? AppColors.error
            : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, this.onTap});

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Icon(icon, size: 20, color: AppColors.roseGold),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTextStyles.headline2.copyWith(color: AppColors.primary)),
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
        child: content,
      ),
    );
  }
}
