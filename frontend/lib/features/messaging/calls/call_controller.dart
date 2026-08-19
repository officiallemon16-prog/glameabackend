import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/realtime_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../models/message.dart';
import '../../auth/auth_controller.dart';
import '../data/messaging_api.dart';

/// Lifecycle of a peer-to-peer call. Purely signaling state - the actual audio
/// and video flow over a WebRTC peer connection.
enum CallPhase { idle, incoming, outgoing, connecting, active, failed }

class CallState {
  const CallState({
    this.phase = CallPhase.idle,
    this.kind = CallKind.voice,
    this.otherUserId = '',
    this.otherName = '',
    this.callId = '',
    this.error,
    this.isMuted = false,
    this.isCameraFront = true,
    this.durationSeconds = 0,
  });

  final CallPhase phase;
  final CallKind kind;
  final String otherUserId;
  final String otherName;
  final String callId;
  final String? error;
  final bool isMuted;
  final bool isCameraFront;
  final int durationSeconds;

  CallState copyWith({
    CallPhase? phase,
    CallKind? kind,
    String? otherUserId,
    String? otherName,
    String? callId,
    String? error,
    bool clearError = false,
    bool? isMuted,
    bool? isCameraFront,
    int? durationSeconds,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      kind: kind ?? this.kind,
      otherUserId: otherUserId ?? this.otherUserId,
      otherName: otherName ?? this.otherName,
      callId: callId ?? this.callId,
      error: clearError ? null : (error ?? this.error),
      isMuted: isMuted ?? this.isMuted,
      isCameraFront: isCameraFront ?? this.isCameraFront,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}

/// Drives one call: places/answers/rejects, negotiates the peer connection over
/// the websocket and persists a call-record message when the call ends.
class CallController extends Notifier<CallState> {
  static const _ringTimeout = Duration(seconds: 45);

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  bool _disposed = false;

  StreamSubscription<RealtimeEvent>? _sub;
  StreamSubscription<Map<String, String>>? _fcmSub;
  Timer? _ringTimer;
  Timer? _durationTimer;
  DateTime? _answeredAt;
  String? _pendingOffer;
  bool _isCaller = false;
  String _bookingId = '';

  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  @override
  CallState build() {
    final rt = ref.read(realtimeClientProvider);
    rt.start().catchError((Object _) {});
    _sub = rt.events.listen(_onEvent, onError: (Object _) {});
    // Also listen for incoming call pushes via FCM (when callee is offline
    // on WebSocket but receives a push notification).
    _fcmSub = ref
        .read(notificationServiceProvider)
        .incomingCalls
        .listen(_onFcmIncomingCall, onError: (Object _) {});
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _fcmSub?.cancel();
      unawaited(_teardown());
    });
    return const CallState();
  }

  // -------------------------------------------------------------------------
  // Public actions
  // -------------------------------------------------------------------------

  /// Places a call to [otherUserId] for [bookingId]. Fails silently (keeping
  /// the previous state) when a call is already in progress.
  Future<void> startCall({
    required String bookingId,
    required String otherUserId,
    required String otherName,
    CallKind kind = CallKind.voice,
  }) async {
    if (state.phase != CallPhase.idle) return;
    _bookingId = bookingId;
    _isCaller = true;
    _answeredAt = null;

    final callId = const Uuid().v4();
    state = CallState(
      phase: CallPhase.outgoing,
      kind: kind,
      otherUserId: otherUserId,
      otherName: otherName,
      callId: callId,
    );
    try {
      await _initPeer(kind);
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);

      final rt = ref.read(realtimeClientProvider);
      rt.send({
        'op': 'call_request',
        'call_id': callId,
        'call_type': _kindName(kind),
        'to_user_id': otherUserId,
        'data': {'from_name': _myName()},
      });
      _sendSignal(callId, otherUserId, kind: 'offer', sdp: offer.sdp);

      _ringTimer?.cancel();
      _ringTimer = Timer(_ringTimeout, () {
        if (state.phase == CallPhase.outgoing || state.phase == CallPhase.connecting) {
          unawaited(_finishWithRecord(0, status: CallStatus.missed));
        }
      });
    } catch (_) {
      state = CallState(
        phase: CallPhase.failed,
        error: 'Could not start the call.',
        otherName: state.otherName,
        kind: state.kind,
      );
      await _teardown();
      Future.delayed(const Duration(seconds: 3), () {
        if (!_disposed && state.phase == CallPhase.failed) {
          state = const CallState(phase: CallPhase.idle);
        }
      });
    }
  }

  /// Accepts an incoming call and answers with a WebRTC answer.
  Future<void> acceptCall() async {
    final current = state;
    if (current.phase != CallPhase.incoming || _pendingOffer == null) return;
    _isCaller = false;
    _answeredAt = DateTime.now();
    state = current.copyWith(phase: CallPhase.connecting, error: null);
    try {
      await _initPeer(current.kind);
      await _peer!.setRemoteDescription(RTCSessionDescription(_pendingOffer!, 'offer'));
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);

      final rt = ref.read(realtimeClientProvider);
      rt.send({
        'op': 'call_accept',
        'call_id': current.callId,
        'to_user_id': current.otherUserId,
        'data': <String, dynamic>{},
      });
      _sendSignal(current.callId, current.otherUserId, kind: 'answer', sdp: answer.sdp);

      state = current.copyWith(phase: CallPhase.active, error: null);
      _startDuration();
    } catch (_) {
      await _endRemote('Call failed to connect.');
    }
  }

  /// Declines an incoming call.
  Future<void> rejectCall() async {
    final current = state;
    if (current.phase != CallPhase.incoming) return;
    ref.read(realtimeClientProvider).send({
      'op': 'call_reject',
      'call_id': current.callId,
      'to_user_id': current.otherUserId,
      'data': <String, dynamic>{},
    });
    state = const CallState(phase: CallPhase.idle);
    await _teardown();
  }

  /// Hangs up: active calls are recorded, unanswered ones are just cancelled.
  Future<void> endCall() async {
    final current = state;
    if (current.phase == CallPhase.active) {
      await _finishWithRecord(_durationMs());
      return;
    }
    if (current.phase == CallPhase.outgoing || current.phase == CallPhase.connecting) {
      ref.read(realtimeClientProvider).send({
        'op': 'call_cancel',
        'call_id': current.callId,
        'to_user_id': current.otherUserId,
        'data': <String, dynamic>{},
      });
      state = const CallState(phase: CallPhase.idle);
      await _teardown();
    }
  }

  Future<void> toggleMute() async {
    final muted = !state.isMuted;
    _localStream?.getAudioTracks().forEach((track) => track.enabled = !muted);
    state = state.copyWith(isMuted: muted);
  }

  Future<void> switchCamera() async {
    if (state.kind != CallKind.video) return;
    final media = _localStream;
    final videoTracks = media?.getVideoTracks() ?? const [];
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
    state = state.copyWith(isCameraFront: !state.isCameraFront);
  }

  // -------------------------------------------------------------------------
  // Realtime events
  // -------------------------------------------------------------------------

  Future<void> _onEvent(RealtimeEvent event) async {
    if (_disposed) return;
    switch (event.op) {
      case 'call_request':
        await _onCallRequest(event.payload);
      case 'call_signal':
        await _onCallSignal(event.payload);
      case 'call_accept':
        if (_matches(event) && _isCaller && state.phase == CallPhase.outgoing) {
          _answeredAt = DateTime.now();
          state = state.copyWith(phase: CallPhase.connecting, error: null);
        }
      case 'call_reject':
        if (_matches(event) && _isCaller) {
          state = CallState(
            phase: CallPhase.failed,
            error: '${state.otherName.isEmpty ? "User" : state.otherName} declined the call.',
            otherName: state.otherName,
            kind: state.kind,
          );
          await _teardown();
          Future.delayed(const Duration(seconds: 3), () {
            if (!_disposed && state.phase == CallPhase.failed) {
              state = const CallState(phase: CallPhase.idle);
            }
          });
        }
      case 'call_cancel':
        if (_matches(event) && !_isCaller && state.phase == CallPhase.incoming) {
          state = const CallState(phase: CallPhase.idle);
          await _teardown();
        }
      case 'call_unavailable':
        if (event.payload['call_id'] == state.callId && _isCaller) {
          state = CallState(
            phase: CallPhase.failed,
            error: '${state.otherName.isEmpty ? "User" : state.otherName} is unavailable.',
            otherName: state.otherName,
            kind: state.kind,
          );
          await _teardown();
          Future.delayed(const Duration(seconds: 3), () {
            if (!_disposed && state.phase == CallPhase.failed) {
              state = const CallState(phase: CallPhase.idle);
            }
          });
        }
      case 'call_end':
        await _onCallEnd(event);
    }
  }

  Future<void> _onCallRequest(Map<String, dynamic> payload) async {
    final callId = payload['call_id'] as String? ?? '';
    final callType = (payload['call_type'] as String? ?? '').toUpperCase();
    final fromId = payload['from_user_id'] as String? ?? '';
    final data = payload['data'];
    final fromName = data is Map ? (data['from_name'] as String? ?? '') : '';

    if (state.phase != CallPhase.idle) {
      // Busy: reject so the caller sees "no answer" right away.
      ref.read(realtimeClientProvider).send({
        'op': 'call_reject',
        'call_id': callId,
        'to_user_id': fromId,
        'data': <String, dynamic>{},
      });
      return;
    }

    _pendingOffer = null;
    _isCaller = false;
    _answeredAt = null;
    _bookingId = '';
    state = CallState(
      phase: CallPhase.incoming,
      kind: callType == 'VIDEO' ? CallKind.video : CallKind.voice,
      otherUserId: fromId,
      otherName: fromName,
      callId: callId,
    );
  }

  Future<void> _onCallSignal(Map<String, dynamic> payload) async {
    if (payload['call_id'] != state.callId) return;
    if (payload['from_user_id'] != state.otherUserId) return;
    final data = payload['data'];
    if (data is! Map) return;
    final kind = data['kind'] as String? ?? '';

    switch (kind) {
      case 'offer':
        _pendingOffer = data['sdp'] as String?;
      case 'answer':
        final sdp = data['sdp'] as String?;
        if (sdp == null || _peer == null) return;
        try {
          await _peer!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          _answeredAt ??= DateTime.now();
          if (state.phase == CallPhase.outgoing || state.phase == CallPhase.connecting) {
            state = state.copyWith(phase: CallPhase.active, error: null);
            _startDuration();
          }
        } catch (_) {
          await _finishWithRecord(0);
        }
      case 'ice':
        final candidate = data['candidate'];
        if (candidate is! Map || _peer == null) return;
        await _peer!.addCandidate(RTCIceCandidate(
          candidate['candidate'] as String?,
          candidate['sdpMid'] as String?,
          (candidate['sdpMLineIndex'] as num?)?.toInt(),
        ));
    }
  }

  Future<void> _onCallEnd(RealtimeEvent event) async {
    if (!_matches(event)) return;
    if (state.phase == CallPhase.active) {
      // Both parties record the call
      await _finishWithRecord(_durationMs());
      return;
    }
    state = const CallState(phase: CallPhase.idle);
    await _teardown();
  }

  bool _matches(RealtimeEvent event) =>
      event.payload['call_id'] == state.callId &&
      event.payload['from_user_id'] == state.otherUserId;

  /// Handles incoming calls delivered via FCM push (when the callee was
  /// offline on WebSocket). We show the incoming call overlay using the
  /// push data. Actual WebRTC negotiation still requires the caller to
  /// re-initiate once both parties are online.
  void _onFcmIncomingCall(Map<String, String> data) {
    if (_disposed || state.phase != CallPhase.idle) return;
    final callId = data['call_id'] ?? '';
    final callType = (data['call_type'] ?? '').toUpperCase();
    final fromId = data['from_user_id'] ?? '';
    final fromName = data['from_name'] ?? '';
    if (callId.isEmpty || fromId.isEmpty) return;
    state = CallState(
      phase: CallPhase.incoming,
      kind: callType == 'VIDEO' ? CallKind.video : CallKind.voice,
      otherUserId: fromId,
      otherName: fromName,
      callId: callId,
    );
  }

  // -------------------------------------------------------------------------
  // WebRTC plumbing
  // -------------------------------------------------------------------------

  Future<void> _initPeer(CallKind kind) async {
    if (_peer != null) return;
    if (!_renderersReady) {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _renderersReady = true;
    }

    final pc = await createPeerConnection({
      'iceServers': await _loadIceServers(),
    });
    _peer = pc;
    pc.onIceCandidate = (candidate) {
      _sendSignal(
        state.callId,
        state.otherUserId,
        kind: 'ice',
        candidate: Map<String, dynamic>.from(candidate.toMap() as Map),
      );
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
      }
    };

    final media = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': kind == CallKind.video
          ? {'facingMode': 'user', 'width': 1280, 'height': 720}
          : false,
    });
    _localStream = media;
    _localRenderer.srcObject = media;
    for (final track in media.getTracks()) {
      await pc.addTrack(track, media);
    }
  }

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    try {
      final servers = await ref.read(messagingApiProvider).fetchIceServers();
      if (servers.isNotEmpty) return servers;
    } catch (_) {
      // Fall through to public STUN.
    }
    return const [
      {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
    ];
  }

  void _sendSignal(
    String callId,
    String toUser, {
    required String kind,
    String? sdp,
    Map<String, dynamic>? candidate,
  }) {
    ref.read(realtimeClientProvider).send({
      'op': 'call_signal',
      'call_id': callId,
      'to_user_id': toUser,
      'data': {
        'kind': kind,
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate,
      },
    });
  }

  // -------------------------------------------------------------------------
  // Bookkeeping
  // -------------------------------------------------------------------------

  /// Records the call as a chat message (caller only), notifies the remote
  /// side and resets to idle.
  Future<void> _finishWithRecord(int durationMs, {CallStatus status = CallStatus.answered}) async {
    final current = state;
    if (_bookingId.isNotEmpty) {
      try {
        await ref.read(messagingApiProvider).sendMessage(
              _bookingId,
              type: 'call',
              callType: _kindName(current.kind),
              callStatus: _statusName(status),
              durationMs: durationMs,
            );
      } catch (_) {
        // The record is best effort; the call itself is still torn down.
      }
    }
    if (current.phase != CallPhase.idle) {
      ref.read(realtimeClientProvider).send({
        'op': 'call_end',
        'call_id': current.callId,
        'to_user_id': current.otherUserId,
        'data': <String, dynamic>{},
      });
    }
    state = const CallState();
    await _teardown();
  }

  Future<void> _endRemote(String reason) async {
    final current = state;
    if (current.phase == CallPhase.idle) return;
    ref.read(realtimeClientProvider).send({
      'op': 'call_end',
      'call_id': current.callId,
      'to_user_id': current.otherUserId,
      'data': <String, dynamic>{},
    });
    state = CallState(phase: CallPhase.failed, error: reason, otherName: current.otherName, kind: current.kind);
    await _teardown();
    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!_disposed && state.phase == CallPhase.failed) {
        state = const CallState(phase: CallPhase.idle);
      }
    });
  }

  int _durationMs() {
    final start = _answeredAt;
    if (start == null) return 0;
    return DateTime.now().difference(start).inMilliseconds;
  }

  void _startDuration() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || state.phase != CallPhase.active) return;
      state = state.copyWith(durationSeconds: _durationMs() ~/ 1000);
    });
  }

  Future<void> _teardown() async {
    _ringTimer?.cancel();
    _durationTimer?.cancel();
    _ringTimer = null;
    _durationTimer = null;
    _pendingOffer = null;
    _answeredAt = null;
    _isCaller = false;
    _bookingId = '';

    final pc = _peer;
    _peer = null;
    try {
      if (pc != null) {
        pc.onIceCandidate = null;
        pc.onTrack = null;
        await pc.close();
      }
      final media = _localStream;
      _localStream = null;
      if (media != null) {
        for (final track in media.getTracks()) {
          await track.stop();
        }
        await media.dispose();
      }
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      if (_renderersReady) {
        await _localRenderer.dispose();
        await _remoteRenderer.dispose();
        _renderersReady = false;
      }
    } catch (_) {
      // Best effort cleanup.
    }
  }

  String _myName() {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return '';
    return user.fullName;
  }

  String _kindName(CallKind kind) =>
      kind == CallKind.video ? 'video' : 'voice';

  String _statusName(CallStatus status) {
    switch (status) {
      case CallStatus.answered:
        return 'answered';
      case CallStatus.missed:
        return 'missed';
      case CallStatus.declined:
        return 'declined';
    }
  }
}

final callControllerProvider =
    NotifierProvider<CallController, CallState>(CallController.new);
