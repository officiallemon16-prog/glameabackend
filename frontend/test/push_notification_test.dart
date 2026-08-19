import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/core/errors/app_exception.dart';
import 'package:glamea/core/notifications/device_token_api.dart';
import 'package:glamea/core/notifications/device_token_controller.dart';
import 'package:glamea/core/notifications/notification_links.dart';
import 'package:glamea/core/notifications/notification_service.dart';
import 'package:glamea/features/auth/auth_controller.dart';
import 'package:glamea/features/auth/data/auth_api.dart';
import 'package:glamea/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeNotificationService implements NotificationService {
  final _tokenChanges = StreamController<String>.broadcast();
  final _foreground = StreamController<Map<String, String>>.broadcast();
  final _incomingCalls = StreamController<Map<String, String>>.broadcast();

  String? token = 'fcm-token-1';
  String platformLabel = 'android';
  int registerCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  String get platform => platformLabel;

  @override
  Stream<String> get tokenChanges => _tokenChanges.stream;

  @override
  Stream<Map<String, String>> get foregroundMessages => _foreground.stream;

  @override
  Stream<Map<String, String>> get incomingCalls => _incomingCalls.stream;

  @override
  Future<void> initialize(void Function(Map<String, String> data) onTap) async {}

  @override
  Future<String?> registerDeviceToken() async {
    registerCalls++;
    return token;
  }

  /// Simulates FCM rotating the device token.
  void emitTokenRefresh(String newToken) => _tokenChanges.add(newToken);

  void close() {
    if (!_tokenChanges.isClosed) _tokenChanges.close();
    if (!_foreground.isClosed) _foreground.close();
    if (!_incomingCalls.isClosed) _incomingCalls.close();
  }
}

class FakeDeviceTokenApi extends DeviceTokenApi {
  FakeDeviceTokenApi() : super(Dio());

  String? lastRegistered;
  String? lastPlatform;
  String? lastUnregistered;
  bool failRegistration = false;

  @override
  Future<void> register(String token, {String platform = 'android'}) async {
    if (failRegistration) {
      throw mapError(DioException(
        requestOptions: RequestOptions(path: '/notifications/devices'),
        type: DioExceptionType.connectionError,
      ));
    }
    lastRegistered = token;
    lastPlatform = platform;
  }

  @override
  Future<void> unregister(String token) async {
    lastUnregistered = token;
  }
}

/// Auth API whose network call is a no-op (used so logout never touches the
/// network in tests).
class NoopAuthApi extends AuthApi {
  NoopAuthApi() : super(Dio());

  @override
  Future<void> logout(String refreshToken) async {}
}

String cachedUserJson() => jsonEncode(const User(
      id: 'user-1',
      email: 'test@glamea.test',
      firstName: 'Amina',
      lastName: 'Bello',
      role: 'CUSTOMER',
      status: 'ACTIVE',
      emailVerified: true,
      phoneVerified: true,
    ).toJson());

Future<void> waitFor(bool Function() condition, {int tries = 100}) async {
  for (var i = 0; i < tries; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('deepLinkFromPushData', () {
    test('maps a booking notification to its booking screen', () {
      expect(
        deepLinkFromPushData(
            const {'notification_type': 'booking', 'booking_id': 'b-1'}),
        'glamea://bookings/b-1',
      );
    });

    test('maps a message notification to the chat', () {
      expect(
        deepLinkFromPushData(const {
          'notification_type': 'message',
          'booking_id': 'b-1',
          'conversation_id': 'c-1',
        }),
        'glamea://chat/b-1',
      );
    });

    test('maps a dispute notification to the dispute detail', () {
      expect(
        deepLinkFromPushData(
            const {'notification_type': 'dispute', 'dispute_id': 'd-1'}),
        'glamea://disputes/d-1',
      );
    });

    test('maps digest and inactive nudges to discover', () {
      expect(
        deepLinkFromPushData(const {'notification_type': 'digest'}),
        'glamea://discover',
      );
      expect(
        deepLinkFromPushData(const {'notification_type': 'inactive'}),
        'glamea://discover',
      );
    });

    test('falls back to notifications for unknown payloads', () {
      expect(deepLinkFromPushData(const {'notification_type': 'welcome'}),
          'glamea://notifications');
      expect(deepLinkFromPushData(const {}), 'glamea://notifications');
    });
  });

  group('DeviceTokenController', () {
    test('registers the device token for the session', () async {
      final service = FakeNotificationService();
      final api = FakeDeviceTokenApi();
      final container = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);

      await container
          .read(deviceTokenControllerProvider.notifier)
          .registerForCurrentSession();

      expect(api.lastRegistered, 'fcm-token-1');
      expect(api.lastPlatform, 'android');
      expect(container.read(deviceTokenControllerProvider), 'fcm-token-1');
    });

    test('skips registration when no token is available', () async {
      final service = FakeNotificationService()..token = null;
      final api = FakeDeviceTokenApi();
      final container = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);

      await container
          .read(deviceTokenControllerProvider.notifier)
          .registerForCurrentSession();

      expect(api.lastRegistered, isNull);
      expect(container.read(deviceTokenControllerProvider), isNull);
    });

    test('keeps no cached token when registration fails', () async {
      final service = FakeNotificationService();
      final api = FakeDeviceTokenApi()..failRegistration = true;
      final container = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);
      addTearDown(service.close);

      await container
          .read(deviceTokenControllerProvider.notifier)
          .registerForCurrentSession();

      expect(container.read(deviceTokenControllerProvider), isNull);
    });

    test('unregisters the token and clears the cache', () async {
      final service = FakeNotificationService();
      final api = FakeDeviceTokenApi();
      final container = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);
      await container
          .read(deviceTokenControllerProvider.notifier)
          .registerForCurrentSession();

      await container
          .read(deviceTokenControllerProvider.notifier)
          .unregisterFromCurrentSession();

      expect(api.lastUnregistered, 'fcm-token-1');
      expect(container.read(deviceTokenControllerProvider), isNull);
    });

    test('re-registers when FCM rotates the token', () async {
      final service = FakeNotificationService();
      final api = FakeDeviceTokenApi();
      final container = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);
      await container
          .read(deviceTokenControllerProvider.notifier)
          .registerForCurrentSession();

      service.emitTokenRefresh('fcm-token-2');

      await waitFor(() => api.lastRegistered == 'fcm-token-2');
      expect(container.read(deviceTokenControllerProvider), 'fcm-token-2');
    });
  });

  group('AuthController device sync', () {
    test('registers the device token when a session is restored', () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'jwt',
        'current_user': cachedUserJson(),
      });
      final service = FakeNotificationService();
      final api = FakeDeviceTokenApi();
      final container = ProviderContainer(overrides: [
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);
      container.listen(authControllerProvider, (_, __) {});

      await waitFor(() => api.lastRegistered != null);

      expect(api.lastRegistered, 'fcm-token-1');
      expect(api.lastPlatform, 'android');
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    });

    test('unregisters the device token on logout', () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'jwt',
        'current_user': cachedUserJson(),
      });
      final service = FakeNotificationService();
      final api = FakeDeviceTokenApi();
      final container = ProviderContainer(overrides: [
        authApiProvider.overrideWithValue(NoopAuthApi()),
        notificationServiceProvider.overrideWithValue(service),
        deviceTokenApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      addTearDown(service.close);
      container.listen(authControllerProvider, (_, __) {});

      await waitFor(() => api.lastRegistered != null);

      await container.read(authControllerProvider.notifier).logout();

      await waitFor(() => api.lastUnregistered != null);
      expect(api.lastUnregistered, 'fcm-token-1');
      expect(container.read(authControllerProvider).isAuthenticated, isFalse);
    });
  });
}
