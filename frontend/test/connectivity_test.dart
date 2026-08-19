import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/app/app.dart';
import 'package:glamea/core/connectivity/connectivity_service.dart';
import 'package:glamea/shared/widgets/offline_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [ConnectivityPlatform] backed by a broadcast controller.
class FakeConnectivityPlatform extends ConnectivityPlatform {
  List<ConnectivityResult> current = [ConnectivityResult.wifi];
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }
}

/// Platform whose plugin call fails (as in widget tests without a platform
/// channel implementation).
class FailingConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    throw MissingPluginException('No implementation');
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

const offlineMessage = "You're offline. Some features may be unavailable.";

Widget wrap() {
  return const ProviderScope(
    child: MaterialApp(home: Scaffold(body: OfflineBanner())),
  );
}

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

  group('isOnlineProvider', () {
    test('seeds the current state and forwards live changes', () async {
      final platform = FakeConnectivityPlatform();
      ConnectivityPlatform.instance = platform;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(isOnlineProvider, (_, __) {});

      await waitFor(() => container.read(isOnlineProvider).hasValue);
      expect(container.read(isOnlineProvider).value, isTrue);

      platform.emit(const [ConnectivityResult.none]);
      await waitFor(() => container.read(isOnlineProvider).value == false);
      expect(container.read(isOnlineProvider).value, isFalse);

      platform.emit(const [ConnectivityResult.mobile]);
      await waitFor(() => container.read(isOnlineProvider).value == true);
      expect(container.read(isOnlineProvider).value, isTrue);
    });

    test('has no value when the plugin is unavailable', () async {
      ConnectivityPlatform.instance = FailingConnectivityPlatform();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(isOnlineProvider, (_, __) {});

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(isOnlineProvider).hasValue, isFalse);
    });
  });

  group('OfflineBanner', () {
    testWidgets('is hidden while online', (tester) async {
      ConnectivityPlatform.instance = FakeConnectivityPlatform();
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text(offlineMessage), findsNothing);
    });

    testWidgets('appears when the device goes offline and hides again',
        (tester) async {
      final platform = FakeConnectivityPlatform();
      ConnectivityPlatform.instance = platform;
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text(offlineMessage), findsNothing);

      platform.emit(const [ConnectivityResult.none]);
      await tester.pump();
      await tester.pump();
      expect(find.text(offlineMessage), findsOneWidget);

      platform.emit(const [ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump();
      expect(find.text(offlineMessage), findsNothing);
    });

    testWidgets('is hidden while connectivity is unknown', (tester) async {
      ConnectivityPlatform.instance = FailingConnectivityPlatform();
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text(offlineMessage), findsNothing);
    });
  });

  testWidgets('GlameaApp shows the offline banner above the UI',
      (tester) async {
    ConnectivityPlatform.instance = FakeConnectivityPlatform()
      ..current = const [ConnectivityResult.none];
    await tester.pumpWidget(const ProviderScope(child: GlameaApp()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text(offlineMessage), findsOneWidget);
  });
}
