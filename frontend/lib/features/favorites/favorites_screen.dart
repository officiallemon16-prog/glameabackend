import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../models/feed_post.dart';
import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/app_states.dart';
import '../discovery/widgets/feed_post_card.dart';
import 'favorites_controller.dart';

/// The signed-in user's saved looks in two tabs: "Liked" (hearts) and
/// "Saved" (bookmarks). Tapping the heart/bookmark on a card removes it from
/// the active tab.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _likedScroll = ScrollController();
  final _savedScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(favoritesControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _likedScroll.dispose();
    _savedScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlameaAppBar(
        title: 'Favorites',
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Liked'),
            Tab(text: 'Saved'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FavoritesList(
            scrollController: _likedScroll,
            builder: (state) => state.liked,
            emptyIcon: Icons.favorite_outline_rounded,
            emptyTitle: 'No likes yet',
            emptyMessage: 'Tap the heart on looks you love and they will show up here.',
            onToggleLike: (post) => ref
                .read(favoritesControllerProvider.notifier)
                .unlike(post),
            onToggleSave: (post) => ref
                .read(favoritesControllerProvider.notifier)
                .toggleSave(post),
            onLoadMore: () => ref
                .read(favoritesControllerProvider.notifier)
                .loadMore(FavoritesTab.liked),
            onRetry: () => ref
                .read(favoritesControllerProvider.notifier)
                .retry(FavoritesTab.liked),
          ),
          _FavoritesList(
            scrollController: _savedScroll,
            builder: (state) => state.saved,
            emptyIcon: Icons.bookmark_outline_rounded,
            emptyTitle: 'No saved looks yet',
            emptyMessage: 'Tap the bookmark on looks you like and they will show up here.',
            onToggleLike: (post) => ref
                .read(favoritesControllerProvider.notifier)
                .toggleLike(post),
            onToggleSave: (post) => ref
                .read(favoritesControllerProvider.notifier)
                .unsave(post),
            onLoadMore: () => ref
                .read(favoritesControllerProvider.notifier)
                .loadMore(FavoritesTab.saved),
            onRetry: () => ref
                .read(favoritesControllerProvider.notifier)
                .retry(FavoritesTab.saved),
          ),
        ],
      ),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  const _FavoritesList({
    required this.scrollController,
    required this.builder,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onLoadMore,
    required this.onRetry,
  });

  final ScrollController scrollController;
  final FavoritesListState Function(FavoritesState state) builder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<FeedPost> onToggleLike;
  final ValueChanged<FeedPost> onToggleSave;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = builder(ref.watch(favoritesControllerProvider));
    switch (state.status) {
      case FavoritesStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: SkeletonList(count: 4),
        );
      case FavoritesStatus.error:
        return ErrorState(
          message: state.error ?? 'Could not load these looks.',
          onRetry: onRetry,
        );
      case FavoritesStatus.ready:
      case FavoritesStatus.loadingMore:
        if (state.posts.isEmpty) {
          return EmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        final itemCount = state.posts.length +
            (state.status == FavoritesStatus.loadingMore ? 1 : 0);
        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(favoritesControllerProvider.notifier).refresh();
          },
          color: AppColors.primary,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 400) {
                onLoadMore();
              }
              return false;
            },
            child: ListView.separated(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, thickness: 1, color: AppColors.borderSubtle),
              itemBuilder: (context, i) {
                if (i >= state.posts.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  );
                }
                final post = state.posts[i];
                return FeedPostCard(
                  post: post,
                  onToggleLike: () => onToggleLike(post),
                  onToggleSave: () => onToggleSave(post),
                );
              },
            ),
          ),
        );
    }
  }
}
