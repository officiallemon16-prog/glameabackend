import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/beauty_service.dart';
import '../../models/category.dart';
import '../../models/home_feed.dart';
import '../../models/professional.dart';
import 'data/discovery_api.dart';

// ---------------------------------------------------------------------------
// Home feed
// ---------------------------------------------------------------------------

enum HomeFeedStatus { loading, ready, error }

class HomeFeedState {
  const HomeFeedState({required this.status, this.feed, this.error});

  final HomeFeedStatus status;
  final HomeFeed? feed;
  final String? error;
}

/// Loads the curated Home feed once and exposes refresh.
class HomeController extends Notifier<HomeFeedState> {
  bool _disposed = false;

  @override
  HomeFeedState build() {
    _load();
    ref.onDispose(() => _disposed = true);
    return const HomeFeedState(status: HomeFeedStatus.loading);
  }

  Future<void> _load() async {
    if (_disposed) return;
    try {
      final feed = await ref.read(discoveryApiProvider).fetchHome(limit: 10);
      if (_disposed) return;
      state = HomeFeedState(status: HomeFeedStatus.ready, feed: feed);
    } on AppException catch (e) {
      if (_disposed) return;
      try {
        if (state.feed != null) return;
        state = HomeFeedState(status: HomeFeedStatus.error, error: e.message);
      } catch (_) {}
    } catch (_) {
      if (_disposed) return;
      try {
        if (state.feed != null) return;
        state = const HomeFeedState(
          status: HomeFeedStatus.error,
          error: 'Something went wrong. Please try again.',
        );
      } catch (_) {}
    }
  }

  Future<void> refresh() async {
    await _load();
  }
}

final homeControllerProvider = NotifierProvider<HomeController, HomeFeedState>(HomeController.new);

// ---------------------------------------------------------------------------
// Discover / search
// ---------------------------------------------------------------------------

enum DiscoverStatus { idle, searching, loadingMore, error }

class DiscoverState {
  const DiscoverState({
    this.query = '',
    this.categoryId,
    this.verifiedOnly = false,
    this.homeServiceOnly = false,
    this.sort = '',
    this.status = DiscoverStatus.idle,
    this.results = const [],
    this.services = const [],
    this.total = 0,
    this.hasMore = false,
    this.error,
  });

  final String query;
  final String? categoryId;
  final bool verifiedOnly;
  final bool homeServiceOnly;
  final String sort;
  final DiscoverStatus status;
  final List<Professional> results;
  final List<BeautyService> services;
  final int total;
  final bool hasMore;
  final String? error;

  bool get hasActiveFilters => verifiedOnly || homeServiceOnly || (categoryId?.isNotEmpty ?? false) || sort.isNotEmpty;

  static const Object _keep = Object();

  DiscoverState copyWith({
    String? query,
    Object? categoryId = _keep,
    bool? verifiedOnly,
    bool? homeServiceOnly,
    String? sort,
    DiscoverStatus? status,
    List<Professional>? results,
    List<BeautyService>? services,
    int? total,
    bool? hasMore,
    Object? error = _keep,
  }) {
    return DiscoverState(
      query: query ?? this.query,
      categoryId: identical(categoryId, _keep) ? this.categoryId : categoryId as String?,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      homeServiceOnly: homeServiceOnly ?? this.homeServiceOnly,
      sort: sort ?? this.sort,
      status: status ?? this.status,
      results: results ?? this.results,
      services: services ?? this.services,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

/// Search state for the Discover tab: debounced query, filters, paged results.
class DiscoverController extends Notifier<DiscoverState> {
  static const _pageSize = 20;

  Timer? _debounce;
  int _requestId = 0;
  bool _disposed = false;

  @override
  DiscoverState build() {
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });
    Future.microtask(_search);
    return const DiscoverState();
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  void setCategory(String? id) {
    state = state.copyWith(categoryId: id);
    _search();
  }

  void setVerifiedOnly(bool value) {
    state = state.copyWith(verifiedOnly: value);
    _search();
  }

  void setHomeServiceOnly(bool value) {
    state = state.copyWith(homeServiceOnly: value);
    _search();
  }

  void setSort(String sort) {
    state = state.copyWith(sort: sort);
    _search();
  }

  void clearFilters() {
    state = state.copyWith(
      verifiedOnly: false,
      homeServiceOnly: false,
      sort: '',
      categoryId: null,
    );
    _search();
  }

  void clearQuery() {
    _debounce?.cancel();
    state = state.copyWith(query: '');
    _search();
  }

  void retry() => _search();

  Future<void> _search() async {
    if (_disposed) return;
    final id = ++_requestId;
    state = state.copyWith(status: DiscoverStatus.searching, error: null);
    try {
      final result = await ref.read(discoveryApiProvider).search(
            query: state.query,
            categoryId: state.categoryId,
            verifiedOnly: state.verifiedOnly,
            homeServiceOnly: state.homeServiceOnly,
            sort: state.sort,
            limit: _pageSize,
            offset: 0,
          );
      if (_disposed || id != _requestId) return;
      state = state.copyWith(
        status: DiscoverStatus.idle,
        results: result.professionals,
        services: result.services,
        total: result.total,
        hasMore: result.professionals.length >= _pageSize,
      );
    } on AppException catch (e) {
      if (_disposed || id != _requestId) return;
      state = state.copyWith(status: DiscoverStatus.error, error: e.message);
    } catch (_) {
      if (_disposed || id != _requestId) return;
      state = state.copyWith(
        status: DiscoverStatus.error,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> loadMore() async {
    if (_disposed) return;
    final current = state;
    if (current.status == DiscoverStatus.searching ||
        current.status == DiscoverStatus.loadingMore ||
        !current.hasMore) {
      return;
    }
    final id = ++_requestId;
    final offset = current.results.length;
    state = current.copyWith(status: DiscoverStatus.loadingMore);
    try {
      final result = await ref.read(discoveryApiProvider).search(
            query: current.query,
            categoryId: current.categoryId,
            verifiedOnly: current.verifiedOnly,
            homeServiceOnly: current.homeServiceOnly,
            sort: current.sort,
            limit: _pageSize,
            offset: offset,
          );
      if (_disposed || id != _requestId) return;
      final merged = [...current.results, ...result.professionals];
      state = state.copyWith(
        status: DiscoverStatus.idle,
        results: merged,
        total: result.total,
        hasMore: result.professionals.length >= _pageSize,
      );
    } on AppException catch (e) {
      if (_disposed || id != _requestId) return;
      state = state.copyWith(status: DiscoverStatus.idle, error: e.message);
    } catch (_) {
      if (_disposed || id != _requestId) return;
      state = state.copyWith(
        status: DiscoverStatus.idle,
        error: 'Something went wrong. Please try again.',
      );
    }
  }
}

final discoverControllerProvider = NotifierProvider<DiscoverController, DiscoverState>(DiscoverController.new);

// ---------------------------------------------------------------------------
// Categories (shared by Discover filters)
// ---------------------------------------------------------------------------

/// Full category list for browsing.
final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(discoveryApiProvider).fetchCategories();
});
