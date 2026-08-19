import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/beauty_service.dart';
import '../../../models/category.dart';
import '../../../models/category_result.dart';
import '../../../models/feed_post.dart';
import '../../../models/home_feed.dart';
import '../../../models/portfolio_item.dart';
import '../../../models/professional.dart';
import '../../../models/review.dart';
import '../../../models/search_result.dart';

/// Discovery + catalog endpoints (spec section 9 DISCOVER).
/// All calls are routed through [_guard] so failures surface as [AppException].
class DiscoveryApi {
  DiscoveryApi(this._dio);

  final Dio _dio;

  Future<HomeFeed> fetchHome({int limit = 10}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/discovery/home',
        queryParameters: {'limit': limit},
      );
      return HomeFeed.fromJson(_data(res.data));
    });
  }

  /// Instagram-style feed of posts. `categoryId` filters; `sponsored` optionally
  /// restricts to adverts only (e.g. the Discovery promotions strip).
  Future<FeedResult> fetchFeed({
    String? categoryId,
    bool? sponsored,
    int limit = 30,
    int offset = 0,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/feed',
        queryParameters: {
          if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
          if (sponsored != null) 'sponsored': sponsored,
          'limit': limit,
          'offset': offset,
        },
      );
      return FeedResult.fromJson(_data(res.data));
    });
  }

  Future<SearchResult> search({
    String? query,
    String? categoryId,
    String? city,
    bool verifiedOnly = false,
    bool homeServiceOnly = false,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/discovery/search',
        queryParameters: {
          if (query != null && query.isNotEmpty) 'q': query,
          if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
          if (city != null && city.isNotEmpty) 'city': city,
          if (verifiedOnly) 'verified': 'true',
          if (homeServiceOnly) 'home_service': 'true',
          if (sort != null && sort.isNotEmpty) 'sort': sort,
          'limit': limit,
          'offset': offset,
        },
      );
      return SearchResult.fromJson(_data(res.data));
    });
  }

  Future<CategoryResult> fetchCategory(String slug) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/discovery/categories/$slug');
      return CategoryResult.fromJson(_data(res.data));
    });
  }

  Future<List<Category>> fetchCategories() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/categories');
      final data = _data(res.data);
      return [
        for (final item in data['categories'] as List? ?? const [])
          if (item is Map<String, dynamic>) Category.fromJson(item),
      ];
    });
  }

  Future<Professional> fetchProfessional(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/professionals/$id');
      final data = _data(res.data);
      return Professional.fromJson(data['professional'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<List<BeautyService>> fetchServices({String? professionalId, int perPage = 50}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/services',
        queryParameters: {
          if (professionalId != null && professionalId.isNotEmpty) 'professional_id': professionalId,
          'per_page': perPage,
        },
      );
      final data = _data(res.data);
      return [
        for (final item in data['services'] as List? ?? const [])
          if (item is Map<String, dynamic>) BeautyService.fromJson(item),
      ];
    });
  }

  /// Portfolio "looks" of a professional (public).
  Future<List<PortfolioItem>> fetchPortfolio(String professionalId) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/professionals/$professionalId/portfolio');
      final data = _data(res.data);
      return [
        for (final item in data['items'] as List? ?? const [])
          if (item is Map<String, dynamic>) PortfolioItem.fromJson(item),
      ];
    });
  }

  /// A single active portfolio "look" by id (public) - resolves `/looks/{id}`.
  Future<PortfolioItem> fetchPortfolioItem(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/portfolio/$id');
      final data = _data(res.data);
      return PortfolioItem.fromJson(data['item'] as Map<String, dynamic>? ?? const {});
    });
  }

  /// Published reviews of a professional (public).
  Future<List<Review>> fetchReviews(String professionalId, {int perPage = 50}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professionals/$professionalId/reviews',
        queryParameters: {'per_page': perPage},
      );
      final data = _data(res.data);
      return [
        for (final item in data['reviews'] as List? ?? const [])
          if (item is Map<String, dynamic>) Review.fromJson(item),
      ];
    });
  }

  Future<List<Professional>> fetchProfessionals({
    String? categoryId,
    String? city,
    bool verifiedOnly = false,
    bool homeServiceOnly = false,
    String? sort,
    int perPage = 20,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professionals',
        queryParameters: {
          if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
          if (city != null && city.isNotEmpty) 'city': city,
          if (verifiedOnly) 'verified': 'true',
          if (homeServiceOnly) 'home_service': 'true',
          if (sort != null && sort.isNotEmpty) 'sort': sort,
          'per_page': perPage,
        },
      );
      final data = _data(res.data);
      return [
        for (final item in data['professionals'] as List? ?? const [])
          if (item is Map<String, dynamic>) Professional.fromJson(item),
      ];
    });
  }

  /// Favorites a post for the signed-in user.
  Future<void> likePost(String postId) {
    return _guard(() async {
      await _dio.post<Map<String, dynamic>>('/posts/$postId/like');
    });
  }

  /// Removes a post from the signed-in user's favorites.
  Future<void> unlikePost(String postId) {
    return _guard(() async {
      await _dio.delete<Map<String, dynamic>>('/posts/$postId/like');
    });
  }

  /// The signed-in user's favorited posts, newest like first.
  Future<FeedResult> fetchLikedPosts({int limit = 30, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/posts/me/likes',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return FeedResult.fromJson(_data(res.data));
    });
  }

  /// Bookmarks a post for the signed-in user.
  Future<void> savePost(String postId) {
    return _guard(() async {
      await _dio.post<Map<String, dynamic>>('/posts/$postId/save');
    });
  }

  /// Removes a post from the signed-in user's bookmarks.
  Future<void> unsavePost(String postId) {
    return _guard(() async {
      await _dio.delete<Map<String, dynamic>>('/posts/$postId/save');
    });
  }

  /// The signed-in user's bookmarked posts, newest save first.
  Future<FeedResult> fetchSavedPosts({int limit = 30, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/posts/me/saves',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return FeedResult.fromJson(_data(res.data));
    });
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    return data is Map<String, dynamic> ? data : const {};
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapError(e);
    }
  }
}

final discoveryApiProvider = Provider<DiscoveryApi>((ref) => DiscoveryApi(ref.watch(apiClientProvider)));
