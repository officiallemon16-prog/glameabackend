import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/dispute.dart';

/// Dispute endpoints available to the customer (raise, list, detail, thread).
class DisputeApi {
  DisputeApi(this._dio);

  final Dio _dio;

  Future<Dispute> raiseDispute({
    required String bookingId,
    required String reason,
    String description = '',
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/disputes',
        data: {'booking_id': bookingId, 'reason': reason, 'description': description},
      );
      final data = _data(res.data);
      return Dispute.fromJson(data['dispute'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<({List<Dispute> items, int total})> fetchMyDisputes({int limit = 50, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/disputes/me',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return (
        items: [
          for (final item in data['disputes'] as List? ?? const [])
            if (item is Map<String, dynamic>) Dispute.fromJson(item),
        ],
        total: (data['total'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<Dispute> fetchDispute(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/disputes/$id');
      final data = _data(res.data);
      return Dispute.fromJson(data['dispute'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<List<DisputeMessage>> fetchMessages(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/disputes/$id/messages');
      final data = _data(res.data);
      return [
        for (final item in data['messages'] as List? ?? const [])
          if (item is Map<String, dynamic>) DisputeMessage.fromJson(item),
      ];
    });
  }

  Future<DisputeMessage> addMessage(String id, String body) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/disputes/$id/messages',
        data: {'body': body},
      );
      final data = _data(res.data);
      return DisputeMessage.fromJson(data['message'] as Map<String, dynamic>? ?? const {});
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

final disputeApiProvider = Provider<DisputeApi>((ref) => DisputeApi(ref.watch(apiClientProvider)));
