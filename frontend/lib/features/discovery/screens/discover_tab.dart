import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../models/category.dart';
import '../../../models/feed_post.dart';
import '../../../models/professional.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_entrance.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../discovery_controller.dart';
import '../feed_controller.dart';
import '../widgets/category_tile.dart';
import '../widgets/deal_card.dart';
import '../widgets/professional_card.dart';
import '../widgets/service_tile.dart';

const _sortOptions = <String, String>{
  '': 'Recommended',
  'rating': 'Top rated',
  'newest': 'Newest',
};

/// Tab 1 - search + filters + browse. When nothing is searched it doubles as a
/// curated page: category grid, top-rated professionals, offers, adverts
/// (sponsored posts) and popular services.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(discoverControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _pickSort() async {
    final current = ref.read(discoverControllerProvider).sort;
    final selected = await showGlameaSheet<String>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Sort by'),
          for (final entry in _sortOptions.entries)
            ListTile(
              leading: Icon(
                entry.key == current ? Icons.radio_button_checked : Icons.radio_button_off,
                color: AppColors.primary,
              ),
              title: Text(entry.value),
              onTap: () => Navigator.of(context).pop(entry.key),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
    if (selected != null) {
      ref.read(discoverControllerProvider.notifier).setSort(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverControllerProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final home = ref.watch(homeControllerProvider);
    final adverts = ref.watch(advertFeedProvider).valueOrNull ?? const <FeedPost>[];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GlameaPageHeader(title: 'Discover'),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSearchBar(
                  controller: _searchController,
                  onChanged: (q) => ref.read(discoverControllerProvider.notifier).setQuery(q),
                  trailing: state.query.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            ref.read(discoverControllerProvider.notifier).clearQuery();
                          },
                          icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _FilterRow(
                  categories: categories,
                  selectedCategoryId: state.categoryId,
                  verifiedOnly: state.verifiedOnly,
                  homeServiceOnly: state.homeServiceOnly,
                  sort: state.sort,
                  hasActiveFilters: state.hasActiveFilters,
                  onCategory: (id) => ref.read(discoverControllerProvider.notifier).setCategory(id),
                  onVerified: (v) => ref.read(discoverControllerProvider.notifier).setVerifiedOnly(v),
                  onHomeService: (v) => ref.read(discoverControllerProvider.notifier).setHomeServiceOnly(v),
                  onSort: _pickSort,
                  onClear: () => ref.read(discoverControllerProvider.notifier).clearFilters(),
                ),
              ],
            ),
          ),
          Expanded(child: _buildResults(context, ref, state, categories, home, adverts)),
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    WidgetRef ref,
    DiscoverState state,
    List<Category> categories,
    HomeFeedState home,
    List<FeedPost> adverts,
  ) {
    if (state.status == DiscoverStatus.searching && state.results.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonGrid(count: 6)],
      );
    }
    if (state.status == DiscoverStatus.error) {
      return ErrorState(
        message: state.error ?? 'Search failed. Please try again.',
        onRetry: () => ref.read(discoverControllerProvider.notifier).retry(),
      );
    }

    final showBrowse = state.query.isEmpty && !state.hasActiveFilters;
    final hasResults = state.results.isNotEmpty;

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (showBrowse && categories.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Text(
                'Browse by category',
                style: AppTextStyles.title,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => CategoryTile(
                  category: categories[i],
                  onTap: () => context.push(AppRoutes.categoryFor(categories[i].slug)),
                ),
                childCount: categories.length,
              ),
            ),
          ),
        ],
        if (showBrowse) ..._browseSections(context, ref, home, adverts),
        if (!showBrowse) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasResults
                          ? '${state.results.length} professional${state.results.length == 1 ? '' : 's'}'
                          : 'Professionals',
                      style: AppTextStyles.title,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasResults)
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
                  (context, i) => AppEntrance(
                    delay: Duration(milliseconds: (i % 8) * 40),
                    child: ProfessionalGridCard(
                      professional: state.results[i],
                      onTap: () => _openProfessional(context, state.results[i]),
                    ),
                  ),
                  childCount: state.results.length,
                ),
              ),
            )
          else if (state.status != DiscoverStatus.searching)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No professionals found',
                message: 'Try a different search or remove some filters.',
              ),
            ),
        ],
        if (state.status == DiscoverStatus.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  /// Curated sections shown when there's no active search/filter: top-rated
  /// professionals, offers, adverts (sponsored posts) and popular services.
  List<Widget> _browseSections(BuildContext context, WidgetRef ref, HomeFeedState home, List<FeedPost> adverts) {
    final feed = home.feed;
    if (feed == null) {
      if (home.status == HomeFeedStatus.error) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: _InlineError(
                message: home.error ?? 'Could not load suggestions.',
                onRetry: () => ref.read(homeControllerProvider.notifier).refresh(),
              ),
            ),
          ),
        ];
      }
      return const [];
    }
    return [
      if (adverts.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Sponsored')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: adverts.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => _AdvertCard(
                post: adverts[i],
                onTap: () => _openProfessionalById(context, adverts[i].professionalId),
              ),
            ),
          ),
        ),
      ],
      if (feed.professionals.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'Top rated professionals',
            actionLabel: 'See all',
            onAction: () {
              HapticFeedback.selectionClick();
              context.push(AppRoutes.topRated);
            },
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 104,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: feed.professionals.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => SizedBox(
                width: 288,
                child: ProfessionalTile(
                  professional: feed.professionals[i],
                  onTap: () => _openProfessional(context, feed.professionals[i]),
                  trailing: _HomeServiceDot(enabled: feed.professionals[i].homeServiceEnabled),
                ),
              ),
            ),
          ),
        ),
      ],
      if (feed.deals.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Offers for you')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 156,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: feed.deals.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => DealCard(deal: feed.deals[i]),
            ),
          ),
        ),
      ],
      if (feed.services.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader(title: 'Popular services')),
        SliverList.builder(
          itemCount: feed.services.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: ServiceTile(
              service: feed.services[i],
              onTap: () => _openProfessionalById(context, feed.services[i].professionalId),
            ),
          ),
        ),
      ],
    ];
  }

  void _openProfessional(BuildContext context, Professional professional) {
    context.push(AppRoutes.professionalFor(professional.id));
  }

  void _openProfessionalById(BuildContext context, String id) {
    if (id.isEmpty) return;
    context.push(AppRoutes.professionalFor(id));
  }
}

/// Compact inline error card with retry, used inside slivers.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: AppColors.coral),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Advert card: sponsored post cover with an "Advert" pill.
class _AdvertCard extends StatelessWidget {  const _AdvertCard({required this.post, this.onTap});

  final FeedPost post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppImage(url: post.coverUrl, fit: BoxFit.cover, placeholderIcon: Icons.photo_outlined),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.scrim,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Sponsored',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              post.professional.name.isEmpty ? 'Glamea professional' : post.professional.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              post.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeServiceDot extends StatelessWidget {
  const _HomeServiceDot({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return Tooltip(
      message: 'Provides home service',
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.home_rounded, size: 17, color: AppColors.success),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.categories,
    required this.selectedCategoryId,
    required this.verifiedOnly,
    required this.homeServiceOnly,
    required this.sort,
    required this.hasActiveFilters,
    required this.onCategory,
    required this.onVerified,
    required this.onHomeService,
    required this.onSort,
    required this.onClear,
  });

  final List<Category> categories;
  final String? selectedCategoryId;
  final bool verifiedOnly;
  final bool homeServiceOnly;
  final String sort;
  final bool hasActiveFilters;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onVerified;
  final ValueChanged<bool> onHomeService;
  final VoidCallback onSort;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(
                context,
                label: 'Verified',
                icon: Icons.verified_rounded,
                selected: verifiedOnly,
                onTap: () => onVerified(!verifiedOnly),
              ),
              const SizedBox(width: AppSpacing.xs),
              _chip(
                context,
                label: 'Home service',
                icon: Icons.home_rounded,
                selected: homeServiceOnly,
                onTap: () => onHomeService(!homeServiceOnly),
              ),
              const SizedBox(width: AppSpacing.xs),
              _chip(
                context,
                label: _sortOptions[sort] ?? 'Sort',
                icon: Icons.swap_vert_rounded,
                selected: sort.isNotEmpty,
                onTap: onSort,
              ),
              if (hasActiveFilters) ...[
                const SizedBox(width: AppSpacing.xs),
                TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ],
          ),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _chip(
                    context,
                    label: 'All',
                    selected: selectedCategoryId == null,
                    onTap: () => onCategory(null),
                  );
                }
                final category = categories[i - 1];
                return _chip(
                  context,
                  label: category.name,
                  selected: selectedCategoryId == category.id,
                  onTap: () => onCategory(category.id),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    IconData? icon,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: selected ? AppColors.white : AppColors.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.white,
      checkmarkColor: AppColors.white,
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: selected ? AppColors.white : AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.borderSubtle),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      visualDensity: VisualDensity.compact,
    );
  }
}
