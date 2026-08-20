import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/category.dart';
import '../../models/feed_post.dart';
import 'data/discovery_api.dart';

/// Signals the home feed to scroll back to the top (latest post) when the home
/// nav icon is tapped while already on the home tab.
final homeScrollToTopProvider = StateProvider<int>((ref) => 0);

enum FeedStatus { loading, ready, loadingMore, refreshing, error }

class FeedState {
  const FeedState({
    this.status = FeedStatus.loading,
    this.posts = const [],
    this.selectedCategoryId,
    this.total = 0,
    this.hasMore = false,
    this.error,
    this.refreshing = false,
  });

  final FeedStatus status;
  final List<FeedPost> posts;
  final String? selectedCategoryId;
  final int total;
  final bool hasMore;
  final String? error;
  final bool refreshing;

  FeedState copyWith({
    FeedStatus? status,
    List<FeedPost>? posts,
    Object? selectedCategoryId = _keep,
    int? total,
    bool? hasMore,
    Object? error = _keep,
    bool? refreshing,
  }) {
    return FeedState(
      status: status ?? this.status,
      posts: posts ?? this.posts,
      selectedCategoryId: identical(selectedCategoryId, _keep)
          ? this.selectedCategoryId
          : selectedCategoryId as String?,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      error: identical(error, _keep) ? this.error : error as String?,
      refreshing: refreshing ?? this.refreshing,
    );
  }

  static const Object _keep = Object();
}

/// Drives the Instagram-style Home feed. Selecting a category refetches with
/// that filter; sponsored posts remain mixed in and float to the top.
class FeedController extends Notifier<FeedState> {
  static const _pageSize = 10;

  int _requestSeq = 0;
  bool _disposed = false;

  @override
  FeedState build() {
    Future.microtask(_load);
    ref.onDispose(() => _disposed = true);
    return const FeedState();
  }

  void selectCategory(String? id) {
    state = state.copyWith(selectedCategoryId: id);
    _load();
  }

  void selectCategoryObject(Category? category) {
    selectCategory(category?.id);
  }

  Future<void> refresh() async {
    await _load();
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    if (_disposed) return;
    final requestId = ++_requestSeq;
    try {
      final categoryId = state.selectedCategoryId;
      if (state.posts.isEmpty) {
        state = state.copyWith(status: FeedStatus.loading, error: null);
      } else {
        state = state.copyWith(refreshing: true, error: null);
      }
      final result = await ref.read(discoveryApiProvider).fetchFeed(
            categoryId: categoryId,
            limit: _pageSize,
            offset: 0,
          );
      if (_disposed || requestId != _requestSeq) return;
      state = state.copyWith(
        status: FeedStatus.ready,
        posts: result.posts,
        total: result.total,
        hasMore: result.posts.length >= _pageSize,
        refreshing: false,
      );
    } on AppException catch (e) {
      if (_disposed || requestId != _requestSeq) return;
      try {
        if (state.posts.isNotEmpty) {
          state = state.copyWith(refreshing: false, error: e.message);
        } else {
          state = state.copyWith(status: FeedStatus.error, error: e.message);
        }
      } catch (_) {}
    } catch (_) {
      if (_disposed || requestId != _requestSeq) return;
      try {
        if (state.posts.isNotEmpty) {
          state = state.copyWith(
            refreshing: false,
            error: 'Could not load your feed. Please try again.',
          );
        } else {
          state = state.copyWith(
            status: FeedStatus.error,
            error: 'Could not load your feed. Please try again.',
          );
        }
      } catch (_) {}
    }
  }

  Future<void> loadMore() async {
    if (_disposed) return;
    final requestId = _requestSeq;
    final current = state;
    if (current.status == FeedStatus.loading ||
        current.status == FeedStatus.loadingMore ||
        !current.hasMore) {
      return;
    }
    state = state.copyWith(status: FeedStatus.loadingMore);
    try {
      final result = await ref.read(discoveryApiProvider).fetchFeed(
            categoryId: current.selectedCategoryId,
            limit: _pageSize,
            offset: current.posts.length,
          );
      if (_disposed || requestId != _requestSeq) return;
      state = state.copyWith(
        status: FeedStatus.ready,
        posts: [...current.posts, ...result.posts],
        total: result.total,
        hasMore: result.posts.length >= _pageSize,
      );
    } on AppException catch (e) {
      if (_disposed || requestId != _requestSeq) return;
      state = state.copyWith(status: FeedStatus.ready, error: e.message);
    } catch (_) {
      if (_disposed || requestId != _requestSeq) return;
      state = state.copyWith(
        status: FeedStatus.ready,
        error: 'Could not load more posts.',
      );
    }
  }

  /// Optimistically toggles a post's like, reverting on failure. The same
  /// toggle drives the "save to favorites" heart on feed cards.
  Future<void> toggleLike(FeedPost post) async {
    if (_disposed) return;
    final api = ref.read(discoveryApiProvider);
    final updated = post.copyWith(
      likedByMe: !post.likedByMe,
      likeCount: post.likeCount + (post.likedByMe ? -1 : 1),
    );
    _replacePost(updated);
    try {
      if (updated.likedByMe) {
        await api.likePost(post.id);
      } else {
        await api.unlikePost(post.id);
      }
    } catch (_) {
      if (_disposed) return;
      _replacePost(post);
    }
  }

  /// Optimistically toggles a post's bookmark (save for later), reverting on
  /// failure.
  Future<void> toggleSave(FeedPost post) async {
    if (_disposed) return;
    final api = ref.read(discoveryApiProvider);
    final updated = post.copyWith(savedByMe: !post.savedByMe);
    _replacePost(updated);
    try {
      if (updated.savedByMe) {
        await api.savePost(post.id);
      } else {
        await api.unsavePost(post.id);
      }
    } catch (_) {
      if (_disposed) return;
      _replacePost(post);
    }
  }

  void _replacePost(FeedPost updated) {
    state = state.copyWith(posts: [
      for (final p in state.posts) p.id == updated.id ? updated : p,
    ]);
  }
}

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(FeedController.new);

/// Sponsored posts used for the advert strip in Discovery.
final advertFeedProvider = FutureProvider<List<FeedPost>>((ref) async {
  final result = await ref.watch(discoveryApiProvider).fetchFeed(
        sponsored: true,
        limit: 12,
      );
  return result.posts;
});
