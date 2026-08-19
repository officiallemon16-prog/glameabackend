import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';

/// Registers/unregisters this device's push token (spec section 13).
class DeviceTokenApi {
  DeviceTokenApi(this._dio);

  final Dio _dio;

  Future<void> register(String token, {String platform = 'android'}) {
    return _guard(() async {
      await _dio.post('/notifications/devices', data: {
        'token': token,
        'platform': platform,
      });
    });
  }

  Future<void> unregister(String token) {
    return _guard(() async {
      await _dio.post('/notifications/devices/unregister', data: {
        'token': token,
      });
    });
  }

  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      throw mapError(e);
    }
  }
}

final deviceTokenApiProvider =
    Provider<DeviceTokenApi>((ref) => DeviceTokenApi(ref.watch(apiClientProvider)));
