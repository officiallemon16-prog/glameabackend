import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/category_result.dart';
import '../../../models/professional.dart';
import '../../../shared/widgets/widgets.dart';
import '../data/discovery_api.dart';
import '../widgets/professional_card.dart';

/// Category page: its professionals (spec section 11 CATEGORY).
class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoryProvider(slug));
    final categoryName = async.valueOrNull?.category.name;

    return Scaffold(
      appBar: GlameaAppBar(title: categoryName ?? 'Category'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(categoryProvider(slug).future),
        color: AppColors.primary,
        child: switch (async) {
          AsyncData(:final value) => _CategoryBody(
              result: value,
              onProfessionalTap: (professional) =>
                  context.push(AppRoutes.professionalFor(professional.id)),
            ),
          AsyncError(:final error) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: ErrorState(
                    message: error is AppException ? error.message : 'Could not load this category.',
                    onRetry: () => ref.invalidate(categoryProvider(slug)),
                  ),
                ),
              ],
            ),
          _ => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: SkeletonGrid(count: 6),
          ),
        },
      ),
    );
  }
}

/// Category detail + professionals (backend `/discovery/categories/{slug}`).
final categoryProvider = FutureProvider.family<CategoryResult, String>(
  (ref, slug) => ref.watch(discoveryApiProvider).fetchCategory(slug),
);

class _CategoryBody extends StatelessWidget {
  const _CategoryBody({required this.result, required this.onProfessionalTap});

  final CategoryResult result;
  final ValueChanged<Professional> onProfessionalTap;

  @override
  Widget build(BuildContext context) {
    final professionals = result.professionals;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (result.category.hasImage)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AppImage(
                    url: result.category.imageUrl,
                    fit: BoxFit.cover,
                    placeholderIcon: Icons.auto_awesome_outlined,
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.category.description.isNotEmpty)
                  Text(
                    result.category.description,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${professionals.length} professional${professionals.length == 1 ? '' : 's'}',
                  style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
        if (professionals.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.person_off_outlined,
              title: 'No professionals yet',
              message: 'Artists in this category are joining soon.',
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
                  onTap: () => onProfessionalTap(professionals[i]),
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
