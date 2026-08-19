import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/conversation.dart';
import '../../../models/message.dart';

/// Messaging endpoints (spec section 12 MESSAGING).
/// All calls are routed through [_guard] so failures surface as [AppException].
class MessagingApi {
  MessagingApi(this._dio);

  final Dio _dio;

  Future<List<Conversation>> fetchConversations({int limit = 50, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/conversations/me',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return [
        for (final item in data['conversations'] as List? ?? const [])
          if (item is Map<String, dynamic>) Conversation.fromJson(item),
      ];
    });
  }

  Future<int> fetchUnreadTotal() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/conversations/me/unread');
      final data = _data(res.data);
      return (data['unread'] as num?)?.toInt() ?? 0;
    });
  }

  Future<Conversation> fetchConversation(String bookingId) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/bookings/$bookingId/conversation');
      final data = _data(res.data);
      return Conversation.fromJson(data['conversation'] as Map<String, dynamic>? ?? const {});
    });
  }

  /// Fetches a page of messages (newest first). Pass [before]/[beforeId] for
  /// keyset pagination of older messages.
  Future<List<Message>> fetchMessages(
    String bookingId, {
    int limit = 50,
    int offset = 0,
    DateTime? before,
    String? beforeId,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/bookings/$bookingId/messages',
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (before != null && beforeId != null)
            'before': before.toUtc().toIso8601String(),
          if (before != null && beforeId != null) 'before_id': beforeId,
        },
      );
      final data = _data(res.data);
      return [
        for (final item in data['messages'] as List? ?? const [])
          if (item is Map<String, dynamic>) Message.fromJson(item),
      ];
    });
  }

  /// Sends a message of any supported [type]. For text messages only [body] is
  /// required; images need [mediaUrl]; locations need [latitude]/[longitude];
  /// call records need [callType].
  Future<Message> sendMessage(
    String bookingId, {
    String body = '',
    String type = 'text',
    String? mediaAssetId,
    String? mediaUrl,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    double? latitude,
    double? longitude,
    String? address,
    String? callType,
    String? callStatus,
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/bookings/$bookingId/messages',
        data: {
          'body': body,
          'type': type,
          'media_asset_id': mediaAssetId,
          'media_url': mediaUrl,
          'mime_type': mimeType,
          'duration_ms': durationMs,
          'width': width,
          'height': height,
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'call_type': callType,
          'call_status': callStatus,
        },
      );
      final data = _data(res.data);
      return Message.fromJson(data['message'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<void> markRead(String bookingId) {
    return _guard(() async {
      await _dio.post<Map<String, dynamic>>('/bookings/$bookingId/messages/read');
    });
  }

  /// STUN/TURN servers for WebRTC calls.
  Future<List<Map<String, dynamic>>> fetchIceServers() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/messaging/ice-servers');
      final data = _data(res.data);
      final servers = data['ice_servers'] as List? ?? const [];
      return [
        for (final s in servers)
          if (s is Map<String, dynamic>) Map<String, dynamic>.from(s),
      ];
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

final messagingApiProvider = Provider<MessagingApi>((ref) => MessagingApi(ref.watch(apiClientProvider)));
