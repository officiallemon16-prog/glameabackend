import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../storage/token_storage.dart';

/// One server push event. [payload] is the full frame minus the `op` field,
/// so call signaling (call_id, from_user_id, ...) and message data are both
/// accessible without extra parsing.
class RealtimeEvent {
  const RealtimeEvent({required this.op, required this.payload});

  final String op;
  final Map<String, dynamic> payload;
}

/// Auth'd websocket to the backend for instant message delivery and WebRTC
/// call signaling. Reconnects with exponential backoff while [start] is active
/// and degrades gracefully to HTTP polling when the socket is unavailable.
class RealtimeClient {
  RealtimeClient({required this.readToken});

  final Future<String?> Function() readToken;

  final _controller = StreamController<RealtimeEvent>.broadcast();
  StreamSubscription? _subscription;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  int _attempts = 0;
  bool _keepAlive = false;
  bool _disposed = false;

  Stream<RealtimeEvent> get events => _controller.stream;
  bool get isConnected => _channel != null;

  /// Opens (or reuses) the connection. Idempotent and never throws.
  Future<void> start() async {
    _keepAlive = true;
    _reconnectTimer?.cancel();
    if (_channel != null) return;
    try {
      final token = await readToken();
      if (token == null || token.isEmpty) return;
      _connect(token);
    } catch (_) {
      // Storage/plugin unavailable: fall back to polling.
    }
  }

  void _connect(String token) {
    try {
      final channel = WebSocketChannel.connect(_wsUri(token));
      _channel = channel;
      _attempts = 0;
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _onDisconnected,
        onError: (Object _) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final op = decoded['op'] as String? ?? '';
    if (op.isEmpty) return;
    final payload = Map<String, dynamic>.from(decoded)..remove('op');
    _controller.add(RealtimeEvent(op: op, payload: payload));
  }

  void _onDisconnected() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    if (_keepAlive && !_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final backoffMs = 500 * (1 << _attempts).clamp(1, 8).toInt();
    _attempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: backoffMs), () {
      if (!_keepAlive || _disposed) return;
      readToken().then((token) {
        if (token == null || token.isEmpty) return;
        _connect(token);
      }).catchError((Object _) {});
    });
  }

  /// Sends a JSON frame. Frames sent while disconnected are dropped - the
  /// caller's own retry/fallback (HTTP) covers them.
  void send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(payload));
  }

  Future<void> stop() async {
    _keepAlive = false;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    stop();
    _controller.close();
  }

  Uri _wsUri(String token) {
    const suffix = '/api/v1';
    const base = AppConstants.apiBaseUrl;
    final root = base.endsWith(suffix)
        ? base.substring(0, base.length - suffix.length)
        : base;
    final secure = root.startsWith('https');
    var wsBase =
        root.replaceFirst(RegExp(r'^https?://'), secure ? 'wss://' : 'ws://');
    if (wsBase.endsWith('/')) {
      wsBase = wsBase.substring(0, wsBase.length - 1);
    }
    return Uri.parse('$wsBase$suffix/ws?token=${Uri.encodeQueryComponent(token)}');
  }
}

final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(
    readToken: () => ref.read(tokenStorageProvider).readAccessToken(),
  );
  ref.onDispose(client.dispose);
  return client;
});
