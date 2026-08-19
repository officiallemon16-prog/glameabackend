import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fires once when the API client discovers the session can no longer be
/// refreshed (expired/invalid tokens). The auth controller listens and logs
/// the user out so the router redirects to login.
class SessionExpiryController extends Notifier<bool> {
  @override
  bool build() => false;

  void trigger() => state = true;

  void reset() => state = false;
}

final sessionExpiryProvider =
    NotifierProvider<SessionExpiryController, bool>(SessionExpiryController.new);
