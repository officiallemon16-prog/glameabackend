import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/review.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../reviews_controller.dart';

/// Reviews written by the current customer.
class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myReviewsControllerProvider);

    return Scaffold(
      appBar: const GlameaAppBar(title: 'My reviews'),
      body: switch (state.status) {
        MyReviewsStatus.loading => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: SkeletonList(count: 4),
          ),
        MyReviewsStatus.error => ErrorState(
            message: state.error ?? 'Could not load your reviews.',
            onRetry: () => ref.read(myReviewsControllerProvider.notifier).refresh(),
          ),
        MyReviewsStatus.ready => RefreshIndicator(
            onRefresh: () => ref.read(myReviewsControllerProvider.notifier).refresh(),
            color: AppColors.primary,
            child: state.items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.star_outline_rounded,
                        title: 'No reviews yet',
                        message: 'Reviews you write after a completed booking appear here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) => _ReviewCard(review: state.items[index]),
                  ),
          ),
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.professionalName.isEmpty ? 'Glamea professional' : review.professionalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (review.createdAt != null)
                Text(
                  Formatters.date(review.createdAt!),
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          RatingStars(rating: review.rating.toDouble(), size: 16),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(review.comment, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ],
          if (review.response != null && review.response!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.softGrey,
                borderRadius: BorderRadius.circular(AppSpacing.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Response from ${review.professionalName.isNotEmpty ? review.professionalName : 'the artist'}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(review.response!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
