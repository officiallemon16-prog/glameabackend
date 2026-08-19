import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/review.dart';

/// Review endpoints for the customer (write + my written reviews).
class ReviewApi {
  ReviewApi(this._dio);

  final Dio _dio;

  Future<Review> createReview({
    required String bookingId,
    required int rating,
    String comment = '',
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/reviews',
        data: {'booking_id': bookingId, 'rating': rating, 'comment': comment},
      );
      final data = _data(res.data);
      return Review.fromJson(data['review'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<({List<Review> items, int total})> fetchMyReviews({int limit = 50, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/reviews/me',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return (
        items: [
          for (final item in data['reviews'] as List? ?? const [])
            if (item is Map<String, dynamic>) Review.fromJson(item),
        ],
        total: (data['total'] as num?)?.toInt() ?? 0,
      );
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

final reviewApiProvider = Provider<ReviewApi>((ref) => ReviewApi(ref.watch(apiClientProvider)));
