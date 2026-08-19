import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import 'deep_link_parser.dart';

/// Captures inbound deep links (cold start + warm stream) and holds them until
/// the router can consume them once the user is authenticated.
class DeepLinkController extends Notifier<String?> {
  StreamSubscription<Uri>? _sub;
  bool _initialised = false;

  @override
  String? build() {
    if (!_initialised) {
      _initialised = true;
      _listen();
    }
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  /// Registers the app_links listeners. Failures (e.g. tests or unsupported
  /// platforms) are swallowed so deep links stay an enhancement.
  Future<void> _listen() async {
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) handleUri(initial);
      _sub = links.uriLinkStream.listen(handleUri, onError: (_) {});
    } catch (_) {
      // Deep links unavailable.
    }
  }

  /// Parses and queues an inbound link. Also used by tests to simulate links.
  void handleRaw(String raw) {
    final path = deepLinkPath(raw);
    if (path == null) return;
    state = path;
    ref.read(routerRefreshProvider).notify();
  }

  void handleUri(Uri uri) => handleRaw(uri.toString());

  /// Removes and returns the pending deep link path, if any.
  String? consume() {
    final pending = state;
    state = null;
    return pending;
  }
}

final pendingDeepLinkProvider =
    NotifierProvider<DeepLinkController, String?>(DeepLinkController.new);
