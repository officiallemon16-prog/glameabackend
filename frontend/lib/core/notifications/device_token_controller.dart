import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_token_api.dart';
import 'notification_service.dart';

/// Tracks the FCM token registered for the current session so it can be
/// removed on logout. Also re-registers whenever FCM rotates the token
/// (reinstall, app data restore, etc.). Best-effort: push failures never
/// block the auth flow.
class DeviceTokenController extends Notifier<String?> {
  StreamSubscription<String>? _tokenSub;

  @override
  String? build() {
    ref.onDispose(() => _tokenSub?.cancel());
    return null;
  }

  /// Fetches this device's FCM token and registers it for the session.
  Future<void> registerForCurrentSession() async {
    final service = ref.read(notificationServiceProvider);
    final token = await service.registerDeviceToken();
    if (token == null || token.isEmpty) return;
    await _register(token, service.platform);

    // Keep the registration fresh across FCM token rotations.
    _tokenSub ??= service.tokenChanges.listen((newToken) {
      if (newToken.isEmpty) return;
      _register(newToken, service.platform);
    });
  }

  /// Unregisters the previously registered token (e.g. on logout).
  Future<void> unregisterFromCurrentSession() async {
    final token = state;
    state = null;
    if (token == null || token.isEmpty) return;
    try {
      await ref.read(deviceTokenApiProvider).unregister(token);
    } catch (_) {
      // Best-effort; the server also invalidates tokens it no longer sees.
    }
  }

  Future<void> _register(String token, String platform) async {
    try {
      await ref.read(deviceTokenApiProvider).register(token, platform: platform);
      state = token;
    } catch (_) {
      // Registration is best-effort; a later token rotation retries.
    }
  }
}

final deviceTokenControllerProvider =
    NotifierProvider<DeviceTokenController, String?>(DeviceTokenController.new);
