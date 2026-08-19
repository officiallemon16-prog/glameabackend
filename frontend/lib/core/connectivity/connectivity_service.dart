import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks connectivity changes (spec sections 6 & 19).
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  /// Live connectivity changes, mapped to a boolean (online when any network
  /// interface is available).
  Stream<bool> get isOnlineStream {
    return _connectivity.onConnectivityChanged.map((results) {
      return results.any((r) => r != ConnectivityResult.none);
    });
  }

  /// The current connectivity state.
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
}

final connectivityProvider =
    Provider<ConnectivityService>((ref) => ConnectivityService());

/// StreamProvider<bool> for reactive offline/online banners.
///
/// Subscribes to live changes first (so no change is missed), then seeds the
/// stream with the current snapshot when no live event has arrived yet. This
/// way launching while offline still surfaces the banner immediately.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityProvider);
  return Stream<bool>.multi((controller) {
    var seeded = false;
    final sub = service.isOnlineStream.listen(
      (online) {
        seeded = true;
        if (!controller.isClosed) controller.add(online);
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
      },
    );
    controller.onCancel = sub.cancel;
    service.isOnline().then((online) {
      if (!seeded && !controller.isClosed) {
        seeded = true;
        controller.add(online);
      }
    }).catchError((Object e) {
      if (!seeded && !controller.isClosed) {
        seeded = true;
        controller.addError(e);
      }
    });
  });
});
