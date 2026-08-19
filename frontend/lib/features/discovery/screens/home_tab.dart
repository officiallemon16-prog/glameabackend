import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../models/category.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_entrance.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../discovery_controller.dart';
import '../feed_controller.dart';
import '../../profile/profile_controller.dart';
import '../widgets/category_tile.dart';
import '../widgets/feed_post_card.dart';

/// Tab 0 - the Instagram-style beauty feed: a services carousel on top that
/// filters the feed, followed by post cards showing profile, location,
/// rating, verification and an image carousel per post.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key, this.onSeeAll});

  /// Switches the shell to the Discover tab.
  final VoidCallback? onSeeAll;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedControllerProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];

    return SafeArea(
      child: Column(
        children: [
          GlameaPageHeader(
            title: 'GLAMEA',
            centerTitle: true,
            titleStyle: const TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.5,
              color: AppColors.primary,
            ),
            leading: IconButton(
              onPressed: () => context.go(AppRoutes.pro),
              icon: const Icon(Icons.storefront_outlined, color: AppColors.textPrimary),
              tooltip: 'My studio',
              visualDensity: VisualDensity.compact,
            ),
            trailing: _NotificationBadge(
              onTap: () => context.push(AppRoutes.notifications),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (categories.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ServiceCarousel(
                        categories: categories,
                        selectedId: feed.selectedCategoryId,
                        onSelect: (id) => ref.read(feedControllerProvider.notifier).selectCategory(id),
                        onSeeAll: widget.onSeeAll,
                      ),
                    ),
                  ..._buildFeed(context, feed),
                  const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFeed(BuildContext context, FeedState feed) {
    switch (feed.status) {
      case FeedStatus.loading:
        return [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
              child: _FeedSkeleton(),
            ),
          ),
        ];
      case FeedStatus.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorState(
              message: feed.error ?? 'Could not load your feed.',
              onRetry: () => ref.read(feedControllerProvider.notifier).retry(),
            ),
          ),
        ];
      case FeedStatus.ready:
      case FeedStatus.loadingMore:
      case FeedStatus.refreshing:
        if (feed.posts.isEmpty) {
          final isFiltered = feed.selectedCategoryId != null;
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: isFiltered ? 'No looks here yet' : 'No looks yet',
                message: isFiltered
                    ? 'Nothing in this service yet. Try another one above.'
                    : 'New looks are being added. Check back soon.',
              ),
            ),
          ];
        }
        final selectedName = _selectedCategoryName(feed.selectedCategoryId);
        final Widget? trailing;
        if (feed.selectedCategoryId != null) {
          trailing = TextButton(
            onPressed: () => ref.read(feedControllerProvider.notifier).selectCategory(null),
            child: const Text('Clear'),
          );
        } else if (feed.total > 0) {
          trailing = Text(
            '${feed.total} look${feed.total == 1 ? '' : 's'}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          );
        } else {
          trailing = null;
        }
        return [
          SliverToBoxAdapter(
            child: SectionHeader(
              title: selectedName ?? 'Latest looks',
              trailing: trailing,
            ),
          ),
          SliverList.builder(
            itemCount: feed.posts.length + (feed.status == FeedStatus.loadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= feed.posts.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  AppEntrance(
                    delay: Duration(milliseconds: (i % 10) * 40),
                    child: FeedPostCard(
                      post: feed.posts[i],
                      onToggleLike: () => ref
                          .read(feedControllerProvider.notifier)
                          .toggleLike(feed.posts[i]),
                      onToggleSave: () => ref
                          .read(feedControllerProvider.notifier)
                          .toggleSave(feed.posts[i]),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderSubtle,
                  ),
                ],
              );
            },
          ),
        ];
    }
  }

  String? _selectedCategoryName(String? id) {
    if (id == null) return null;
    final categories = ref.read(categoriesProvider).valueOrNull ?? const <Category>[];
    for (final c in categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }
}

class _NotificationBadge extends ConsumerWidget {
  const _NotificationBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);
    final count = state.unreadCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
          tooltip: 'Notifications',
          visualDensity: VisualDensity.compact,
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// Horizontal strip of category cards with real images and a subtitle.
/// Tapping one filters the feed; the active card is highlighted.
class _ServiceCarousel extends StatelessWidget {
  const _ServiceCarousel({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    this.onSeeAll,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
          child: Row(
            children: [
              const Expanded(
                child: Text('Shop by service', style: AppTextStyles.title),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, AppDimens.minTouchTarget),
                  ),
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final category = categories[i];
              final selected = selectedId == category.id;
              return _ServiceCarouselCard(
                category: category,
                selected: selected,
                onTap: () => onSelect(selected ? null : category.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServiceCarouselCard extends StatelessWidget {
  const _ServiceCarouselCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x296B1A2B),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile - 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (category.hasImage)
                AppImage(url: category.imageUrl, fit: BoxFit.cover)
              else
                Container(
                  color: AppColors.roseGold.withValues(alpha: 0.2),
                  alignment: Alignment.center,
                  child: Icon(
                    categoryIcon(category.name),
                    color: AppColors.primary,
                    size: 34,
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      categorySubtitle(category.slug),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton matching the post-card shape: author row, 1:1 image, text lines.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 2; i++) ...[
          const Row(
            children: [
              AppSkeleton(width: 40, height: 40, radius: 20),
              SizedBox(width: AppSpacing.sm),
              AppSkeleton(width: 160, height: 16),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const AspectRatio(
            aspectRatio: 1,
            child: AppSkeleton(radius: 0),
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSkeleton(height: 14),
          const SizedBox(height: AppSpacing.xs),
          const AppSkeleton(width: 120, height: 14),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

