import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/feed_post.dart';
import '../discovery/data/discovery_api.dart';

enum FavoritesTab { liked, saved }

enum FavoritesStatus { loading, ready, loadingMore, error }

class FavoritesListState {
  const FavoritesListState({
    this.status = FavoritesStatus.loading,
    this.posts = const [],
    this.hasMore = false,
    this.error,
  });

  final FavoritesStatus status;
  final List<FeedPost> posts;
  final bool hasMore;
  final String? error;

  FavoritesListState copyWith({
    FavoritesStatus? status,
    List<FeedPost>? posts,
    bool? hasMore,
    Object? error = _keep,
  }) {
    return FavoritesListState(
      status: status ?? this.status,
      posts: posts ?? this.posts,
      hasMore: hasMore ?? this.hasMore,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }

  static const Object _keep = Object();
}

class FavoritesState {
  const FavoritesState({
    this.liked = const FavoritesListState(),
    this.saved = const FavoritesListState(),
  });

  final FavoritesListState liked;
  final FavoritesListState saved;

  FavoritesState copyWith({FavoritesListState? liked, FavoritesListState? saved}) {
    return FavoritesState(
      liked: liked ?? this.liked,
      saved: saved ?? this.saved,
    );
  }
}

/// Drives the two favorites tabs: "Liked" (hearts) and "Saved" (bookmarks).
/// Each list is loaded independently and supports infinite scroll.
class FavoritesController extends Notifier<FavoritesState> {
  static const _pageSize = 30;

  @override
  FavoritesState build() {
    Future.microtask(_loadLiked);
    Future.microtask(_loadSaved);
    return const FavoritesState();
  }

  // -------------------------------------------------------------------------
  // Liked (hearts)
  // -------------------------------------------------------------------------

  Future<void> _loadLiked() async {
    if (state.liked.posts.isEmpty) {
      state = state.copyWith(
          liked: const FavoritesListState(status: FavoritesStatus.loading));
    }
    try {
      final result = await ref.read(discoveryApiProvider).fetchLikedPosts(
            limit: _pageSize,
            offset: 0,
          );
      state = state.copyWith(
        liked: FavoritesListState(
          status: FavoritesStatus.ready,
          posts: result.posts,
          hasMore: result.posts.length >= _pageSize,
        ),
      );
    } on AppException catch (e) {
      if (state.liked.posts.isNotEmpty) return;
      state = state.copyWith(
          liked: FavoritesListState(status: FavoritesStatus.error, error: e.message));
    } catch (_) {
      if (state.liked.posts.isNotEmpty) return;
      state = state.copyWith(
        liked: const FavoritesListState(
          status: FavoritesStatus.error,
          error: 'Could not load your favorites. Please try again.',
        ),
      );
    }
  }

  Future<void> _loadMoreLiked() async {
    final current = state.liked;
    if (current.status == FavoritesStatus.loading ||
        current.status == FavoritesStatus.loadingMore ||
        !current.hasMore) {
      return;
    }
    state = state.copyWith(
        liked: current.copyWith(status: FavoritesStatus.loadingMore));
    try {
      final result = await ref.read(discoveryApiProvider).fetchLikedPosts(
            limit: _pageSize,
            offset: current.posts.length,
          );
      state = state.copyWith(
        liked: FavoritesListState(
          status: FavoritesStatus.ready,
          posts: [...current.posts, ...result.posts],
          hasMore: result.posts.length >= _pageSize,
        ),
      );
    } catch (_) {
      state = state.copyWith(
          liked: state.liked.copyWith(status: FavoritesStatus.ready));
    }
  }

  /// Unlikes a post optimistically and removes it from the list.
  Future<void> unlike(FeedPost post) async {
    state = state.copyWith(
      liked: state.liked.copyWith(posts: [
        for (final p in state.liked.posts)
          if (p.id != post.id) p,
      ]),
    );
    try {
      await ref.read(discoveryApiProvider).unlikePost(post.id);
    } catch (_) {
      await _loadLiked();
    }
  }

  /// Optimistically toggles a post's like without changing list membership
  /// (used from the Saved tab, where the heart is informational).
  Future<void> toggleLike(FeedPost post) async {
    final updated = post.copyWith(
      likedByMe: !post.likedByMe,
      likeCount: post.likeCount + (post.likedByMe ? -1 : 1),
    );
    _replaceInLists(updated);
    try {
      if (updated.likedByMe) {
        await ref.read(discoveryApiProvider).likePost(post.id);
      } else {
        await ref.read(discoveryApiProvider).unlikePost(post.id);
      }
    } catch (_) {
      _replaceInLists(post);
    }
  }

  // -------------------------------------------------------------------------
  // Saved (bookmarks)
  // -------------------------------------------------------------------------

  Future<void> _loadSaved() async {
    if (state.saved.posts.isEmpty) {
      state = state.copyWith(
          saved: const FavoritesListState(status: FavoritesStatus.loading));
    }
    try {
      final result = await ref.read(discoveryApiProvider).fetchSavedPosts(
            limit: _pageSize,
            offset: 0,
          );
      state = state.copyWith(
        saved: FavoritesListState(
          status: FavoritesStatus.ready,
          posts: result.posts,
          hasMore: result.posts.length >= _pageSize,
        ),
      );
    } on AppException catch (e) {
      if (state.saved.posts.isNotEmpty) return;
      state = state.copyWith(
          saved: FavoritesListState(status: FavoritesStatus.error, error: e.message));
    } catch (_) {
      if (state.saved.posts.isNotEmpty) return;
      state = state.copyWith(
        saved: const FavoritesListState(
          status: FavoritesStatus.error,
          error: 'Could not load your saved looks. Please try again.',
        ),
      );
    }
  }

  Future<void> _loadMoreSaved() async {
    final current = state.saved;
    if (current.status == FavoritesStatus.loading ||
        current.status == FavoritesStatus.loadingMore ||
        !current.hasMore) {
      return;
    }
    state = state.copyWith(
        saved: current.copyWith(status: FavoritesStatus.loadingMore));
    try {
      final result = await ref.read(discoveryApiProvider).fetchSavedPosts(
            limit: _pageSize,
            offset: current.posts.length,
          );
      state = state.copyWith(
        saved: FavoritesListState(
          status: FavoritesStatus.ready,
          posts: [...current.posts, ...result.posts],
          hasMore: result.posts.length >= _pageSize,
        ),
      );
    } catch (_) {
      state = state.copyWith(
          saved: state.saved.copyWith(status: FavoritesStatus.ready));
    }
  }

  /// Un-saves a post optimistically and removes it from the list.
  Future<void> unsave(FeedPost post) async {
    state = state.copyWith(
      saved: state.saved.copyWith(posts: [
        for (final p in state.saved.posts)
          if (p.id != post.id) p,
      ]),
    );
    try {
      await ref.read(discoveryApiProvider).unsavePost(post.id);
    } catch (_) {
      await _loadSaved();
    }
  }

  /// Optimistically toggles a post's bookmark without changing list membership
  /// (used from the Liked tab, where the bookmark is informational).
  Future<void> toggleSave(FeedPost post) async {
    final updated = post.copyWith(savedByMe: !post.savedByMe);
    _replaceInLists(updated);
    try {
      if (updated.savedByMe) {
        await ref.read(discoveryApiProvider).savePost(post.id);
      } else {
        await ref.read(discoveryApiProvider).unsavePost(post.id);
      }
    } catch (_) {
      _replaceInLists(post);
    }
  }

  void _replaceInLists(FeedPost updated) {
    List<FeedPost> replace(List<FeedPost> list) => [
          for (final p in list) p.id == updated.id ? updated : p,
        ];
    state = state.copyWith(
      liked: state.liked.copyWith(posts: replace(state.liked.posts)),
      saved: state.saved.copyWith(posts: replace(state.saved.posts)),
    );
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  Future<void> refresh() async {
    await Future.wait([_loadLiked(), _loadSaved()]);
  }

  Future<void> retry(FavoritesTab tab) {
    return tab == FavoritesTab.liked ? _loadLiked() : _loadSaved();
  }

  Future<void> loadMore(FavoritesTab tab) {
    return tab == FavoritesTab.liked ? _loadMoreLiked() : _loadMoreSaved();
  }
}

final favoritesControllerProvider =
    NotifierProvider<FavoritesController, FavoritesState>(FavoritesController.new);
