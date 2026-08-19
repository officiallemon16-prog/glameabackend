import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/professional.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_states.dart';
import '../data/discovery_api.dart';
import '../widgets/professional_card.dart';

/// Route: /top-rated. Full list of top-rated professionals (sort=rating),
/// the destination of the "See all" action on the Discover section.
final topRatedProvider = FutureProvider<List<Professional>>((ref) {
  return ref.watch(discoveryApiProvider).fetchProfessionals(
        sort: 'rating',
        perPage: 50,
      );
});

class TopRatedScreen extends ConsumerWidget {
  const TopRatedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(topRatedProvider);

    return Scaffold(
      appBar: const GlameaAppBar(title: 'Top rated'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(topRatedProvider.future),
        color: AppColors.primary,
        child: switch (async) {
          AsyncData(:final value) => _TopRatedBody(professionals: value),
          AsyncError(:final error) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: ErrorState(
                    message: error is AppException
                        ? error.message
                        : 'Could not load top-rated professionals.',
                    onRetry: () => ref.invalidate(topRatedProvider),
                  ),
                ),
              ],
            ),
          _ => const _TopRatedSkeleton(),
        },
      ),
    );
  }
}

class _TopRatedBody extends StatelessWidget {
  const _TopRatedBody({required this.professionals});

  final List<Professional> professionals;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
            child: Text(
              '${professionals.length} professional${professionals.length == 1 ? '' : 's'}',
              style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ),
        if (professionals.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.star_border_rounded,
              title: 'No professionals yet',
              message: 'Top-rated artists will appear here as bookings grow.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProfessionalGridCard(
                  professional: professionals[i],
                  onTap: () =>
                      context.push(AppRoutes.professionalFor(professionals[i].id)),
                ),
                childCount: professionals.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }
}

/// Grid of skeleton tiles matching the results layout.
class _TopRatedSkeleton extends StatelessWidget {
  const _TopRatedSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        AppSkeleton(width: 180, height: 20),
        SizedBox(height: AppSpacing.md),
        SkeletonGrid(count: 6),
      ],
    );
  }
}
