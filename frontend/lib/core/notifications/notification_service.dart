import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entry point for messages received while the app process is alive but in the
/// background/killed (Android). Must be a top-level function and registered
/// before runApp. Data-only pushes carry the deep-link fields, so tapping the
/// system notification routes the user on next launch via the initial-message
/// path handled in [NotificationService.initialize].
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase unavailable for this build; nothing to display.
  }
}

/// Push notification abstraction (spec section 13), backed by Firebase Cloud
/// Messaging. When Firebase is not configured for the build, every call
/// degrades to a no-op so the app keeps working without push credentials
/// (in-app notifications still function).
abstract interface class NotificationService {
  /// Sets up FCM: initializes Firebase, requests permission and wires tap
  /// handlers. [onTap] receives the notification data payload (a flat
  /// string map, e.g. {"notification_type": "booking", "booking_id": "..."}).
  Future<void> initialize(void Function(Map<String, String> data) onTap);

  /// The device's FCM token, or null when push is unavailable.
  Future<String?> registerDeviceToken();

  /// Emits whenever FCM rotates the device token so the app can re-register
  /// it with the backend (tokens change on reinstall, app restore, etc.).
  Stream<String> get tokenChanges;

  /// Emits push payloads received while the app is in the foreground, used to
  /// render the in-app banner. Each payload is a flat string map including
  /// `title`/`body` (when present) plus the custom deep-link fields.
  Stream<Map<String, String>> get foregroundMessages;

  /// Emits when an incoming call push arrives while the app is in the
  /// foreground. The call controller listens to show the call overlay.
  Stream<Map<String, String>> get incomingCalls;

  /// Whether real push delivery is supported on this platform/build.
  bool get isAvailable;

  /// Platform identifier reported to the backend ('android' | 'ios').
  String get platform;
}

class NotificationServiceImpl implements NotificationService {
  final _tokenChanges = StreamController<String>.broadcast();
  final _foregroundMessages = StreamController<Map<String, String>>.broadcast();
  final _incomingCallController = StreamController<Map<String, String>>.broadcast();

  bool _initialized = false;

  bool get _enabled {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  bool get isAvailable => _enabled;

  @override
  String get platform {
    if (_enabled && Platform.isIOS) return 'ios';
    return 'android';
  }

  @override
  Stream<String> get tokenChanges => _tokenChanges.stream;

  @override
  Stream<Map<String, String>> get foregroundMessages => _foregroundMessages.stream;

  @override
  Stream<Map<String, String>> get incomingCalls => _incomingCallController.stream;

  @override
  Future<void> initialize(void Function(Map<String, String> data) onTap) async {
    if (!_enabled || _initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // Token rotation: re-register the new token upstream.
      messaging.onTokenRefresh.listen((token) {
        if (token.isNotEmpty) _tokenChanges.add(token);
      });

      // Foreground delivery: surface a lightweight in-app banner. The
      // NotificationsController keeps the in-app list and unread badge in sync.
      // Incoming call notifications are forwarded to the call controller.
      FirebaseMessaging.onMessage.listen((message) {
        final data = <String, String>{};
        final notification = message.notification;
        if (notification != null) {
          if (notification.title != null) data['title'] = notification.title!;
          if (notification.body != null) data['body'] = notification.body!;
        }
        message.data.forEach((k, v) => data[k] = v.toString());
        if (data.isNotEmpty) {
          if (data['notification_type'] == 'incoming_call') {
            _incomingCallController.add(data);
          } else {
            _foregroundMessages.add(data);
          }
        }
      });

      // Tap handling: from a terminated app (initial message), from the
      // background (onMessageOpenedApp) and foreground taps (onMessage with
      // notificationTap). The latter two are both routed via onMessageOpenedApp
      // or, on Android foreground taps, via the banner's own on-tap handler.
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _deliver(message, onTap));
      final initial = await messaging.getInitialMessage();
      if (initial != null) _deliver(initial, onTap);
    } catch (_) {
      // Firebase unavailable (no google-services.json / GoogleService-Info.plist).
      _initialized = false;
    }
  }

  void _deliver(RemoteMessage message, void Function(Map<String, String>) onTap) {
    final data = message.data;
    if (data.isEmpty) return;
    onTap(data.map((k, v) => MapEntry(k, v.toString())));
  }

  @override
  Future<String?> registerDeviceToken() async {
    if (!_enabled) return null;
    try {
      await Firebase.initializeApp();
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationServiceImpl(),
);
