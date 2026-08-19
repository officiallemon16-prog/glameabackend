import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Shimmer placeholder during loads.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({super.key, this.width = double.infinity, this.height = 16, this.radius = 8});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Full-page loading state (centered spinner).
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Friendly empty state with optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.12),
                    AppColors.primaryDeep.withValues(alpha: 0.18),
                  ],
                ),
              ),
              child: Icon(icon, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppOutlinedAction(label: actionLabel!, onTap: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}

class AppOutlinedAction extends StatelessWidget {
  const AppOutlinedAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimens.minTouchTarget,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Error state with retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 40,
                color: AppColors.coral,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppOutlinedAction(label: 'Try again', onTap: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grid of skeleton tiles matching the 4:5 portfolio ratio.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 6, this.ratio = 4 / 5});

  final int count;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: ratio,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const AppSkeleton(radius: AppDimens.cardRadiusMobile),
    );
  }
}

/// Skeleton rows for lists.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 56, height: 56, radius: AppSpacing.md),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 140, height: 16),
                    SizedBox(height: AppSpacing.xs),
                    AppSkeleton(width: 100, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

/// Skeleton for a chat message thread with alternating bubble positions.
class SkeletonChatBubbles extends StatelessWidget {
  const SkeletonChatBubbles({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          Padding(
            padding: EdgeInsets.only(
              left: i.isEven ? 48 : 0,
              right: i.isEven ? 0 : 48,
            ),
            child: Row(
              mainAxisAlignment: i.isEven ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!i.isEven) ...[
                  const AppSkeleton(width: 32, height: 32, radius: 16),
                  const SizedBox(width: AppSpacing.sm),
                ],
                AppSkeleton(
                  width: 140.0 + ((i * 17) % 60),
                  height: 40,
                  radius: 12,
                ),
                if (i.isEven) ...[
                  const SizedBox(width: AppSpacing.sm),
                  const AppSkeleton(width: 32, height: 32, radius: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

/// Skeleton for a wallet screen: balance card + transaction rows.
class SkeletonWallet extends StatelessWidget {
  const SkeletonWallet({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        AppSkeleton(width: double.infinity, height: 120, radius: AppSpacing.md),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(width: 100, height: 16),
        SizedBox(height: AppSpacing.sm),
        SkeletonList(count: 4),
      ],
    );
  }
}

/// Skeleton for a booking detail screen.
class SkeletonBookingDetail extends StatelessWidget {
  const SkeletonBookingDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        AppSkeleton(width: double.infinity, height: 140, radius: AppSpacing.md),
        SizedBox(height: AppSpacing.md),
        AppSkeleton(width: double.infinity, height: 20, radius: 4),
        SizedBox(height: AppSpacing.xs),
        AppSkeleton(width: 200, height: 16, radius: 4),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(width: double.infinity, height: 60, radius: AppSpacing.md),
        SizedBox(height: AppSpacing.sm),
        AppSkeleton(width: double.infinity, height: 60, radius: AppSpacing.md),
      ],
    );
  }
}
