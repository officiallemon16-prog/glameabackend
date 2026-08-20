import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/notification_item.dart';
import '../../../models/user.dart';

/// Profile + notification endpoints (spec sections 18-19).
class ProfileApi {
  ProfileApi(this._dio);

  final Dio _dio;

  Future<User> fetchMe() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/users/me');
      final data = _data(res.data);
      return User.fromJson(data['user'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<User> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? avatarMediaId,
  }) {
    return _guard(() async {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/users/me',
        data: {
          if (firstName != null) 'first_name': firstName,
          if (lastName != null) 'last_name': lastName,
          if (email != null) 'email': email,
          if (avatarMediaId != null) 'avatar_media_id': avatarMediaId,
        },
      );
      final data = _data(res.data);
      return User.fromJson(data['user'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<({List<GlameaNotification> items, int total})> fetchNotifications({
    int limit = 50,
    int offset = 0,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/notifications/me',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return (
        items: [
          for (final item in data['notifications'] as List? ?? const [])
            if (item is Map<String, dynamic>) GlameaNotification.fromJson(item),
        ],
        total: (data['total'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<int> unreadCount() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/notifications/me/unread-count');
      final data = _data(res.data);
      return (data['unread_count'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> markRead(String id) {
    return _guard(() async {
      await _dio.post<Map<String, dynamic>>('/notifications/$id/read');
    });
  }

  Future<void> markAllRead() {
    return _guard(() async {
      await _dio.post<Map<String, dynamic>>('/notifications/me/read-all');
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

final profileApiProvider = Provider<ProfileApi>((ref) => ProfileApi(ref.watch(apiClientProvider)));
