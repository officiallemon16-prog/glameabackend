import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/realtime_client.dart';
import '../../features/auth/auth_controller.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import 'data/messaging_api.dart';

// ---------------------------------------------------------------------------
// Conversation list
// ---------------------------------------------------------------------------

enum ConversationsStatus { loading, ready, error }

class ConversationsState {
  const ConversationsState({
    required this.status,
    this.conversations = const [],
    this.error,
  });

  final ConversationsStatus status;
  final List<Conversation> conversations;
  final String? error;

  /// Total unread, excluding threads where the current user sent the last
  /// message (the backend can report an unread count for a conversation the
  /// user just wrote in, which must not show as a "new message" badge).
  int unreadTotal(String userId) => conversations
      .where((c) => c.lastMessageSenderId != userId)
      .fold(0, (sum, c) => sum + c.unreadCount);
}

/// Loads the user's conversations and keeps them fresh with light polling.
class ConversationsController extends Notifier<ConversationsState> {
  static const _pollInterval = Duration(seconds: 3);

  Timer? _timer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  bool _disposed = false;

  @override
  ConversationsState build() {
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
    final client = ref.read(realtimeClientProvider);
    client.start().catchError((Object _) {});
    _realtimeSub = client.events.listen((event) {
      if (_disposed) return;
      if (event.op != 'message') return;
      _load(silent: true);
    }, onError: (Object _) {});
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _realtimeSub?.cancel();
    });
    Future.microtask(_load);
    return const ConversationsState(status: ConversationsStatus.loading);
  }

  Future<void> _load({bool silent = false}) async {
    if (_disposed) return;
    try {
      if (state.status != ConversationsStatus.ready) {
        state = const ConversationsState(status: ConversationsStatus.loading);
      }
      final conversations = await ref.read(messagingApiProvider).fetchConversations();
      if (_disposed) return;
      state = ConversationsState(status: ConversationsStatus.ready, conversations: conversations);
    } on AppException catch (e) {
      if (_disposed || silent) return;
      try {
        if (state.conversations.isNotEmpty) return;
        state = ConversationsState(status: ConversationsStatus.error, error: e.message);
      } catch (_) {}
    } catch (_) {
      if (_disposed || silent) return;
      try {
        if (state.conversations.isNotEmpty) return;
        state = const ConversationsState(
          status: ConversationsStatus.error,
          error: 'Could not load your messages. Please try again.',
        );
      } catch (_) {}
    }
  }

  Future<void> refresh() => _load();
}

final conversationsControllerProvider =
    NotifierProvider<ConversationsController, ConversationsState>(
  ConversationsController.new,
);

// ---------------------------------------------------------------------------
// Unread total (nav badge)
// ---------------------------------------------------------------------------

/// Tracks the total number of unread messages for the nav badge.
/// Derived from ConversationsController — no separate API call needed.
class UnreadController extends Notifier<int> {
  @override
  int build() {
    final userId = ref.watch(authControllerProvider).user?.id ?? '';
    ref.listen<ConversationsState>(conversationsControllerProvider, (_, next) {
      final total = next.unreadTotal(userId);
      if (total != state) state = total;
    });
    return ref.read(conversationsControllerProvider).unreadTotal(userId);
  }

  Future<void> refresh() async {
    await ref.read(conversationsControllerProvider.notifier).refresh();
  }
}

final unreadControllerProvider = NotifierProvider<UnreadController, int>(
  UnreadController.new,
);

// ---------------------------------------------------------------------------
// Chat (single conversation)
// ---------------------------------------------------------------------------

enum MessagesStatus { loading, ready, error }

class MessagesState {
  const MessagesState({
    required this.status,
    this.conversation,
    this.messages = const [],
    this.error,
    this.sending = false,
    this.sendError,
    this.hasMore = false,
    this.loadingMore = false,
    this.otherTyping = false,
  });

  final MessagesStatus status;
  final Conversation? conversation;
  final List<Message> messages;
  final String? error;
  final bool sending;
  final String? sendError;
  final bool hasMore;
  final bool loadingMore;
  final bool otherTyping;

  MessagesState copyWith({
    MessagesStatus? status,
    Conversation? conversation,
    List<Message>? messages,
    String? error,
    bool clearError = false,
    bool? sending,
    String? sendError,
    bool? hasMore,
    bool? loadingMore,
    bool? otherTyping,
  }) {
    return MessagesState(
      status: status ?? this.status,
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      error: clearError ? null : (error ?? this.error),
      sending: sending ?? this.sending,
      sendError: sendError ?? this.sendError,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      otherTyping: otherTyping ?? this.otherTyping,
    );
  }
}

/// Drives a chat screen for a booking: initial load, send, mark-read and
/// realtime delivery over websocket (HTTP polling as a fallback).
class MessagesController extends FamilyNotifier<MessagesState, String> {
  static const _pollInterval = Duration(seconds: 3);
  static const _pageSize = 50;

  Timer? _pollTimer;
  Timer? _typingClearTimer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  bool _disposed = false;

  @override
  MessagesState build(String bookingId) {
    _loadInitial(bookingId);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll(bookingId));
    _listenRealtime(bookingId);
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
      _realtimeSub?.cancel();
    });
    return const MessagesState(status: MessagesStatus.loading);
  }

  Future<void> _loadInitial(String bookingId) async {
    try {
      final results = await Future.wait([
        ref.read(messagingApiProvider).fetchConversation(bookingId),
        ref.read(messagingApiProvider).fetchMessages(bookingId),
      ]);
      if (_disposed) return;
      final conversation = results[0] as Conversation;
      final messages = results[1] as List<Message>;
      state = state.copyWith(
        status: MessagesStatus.ready,
        conversation: conversation,
        messages: _merge(state.messages, messages),
        hasMore: messages.length >= _pageSize,
        clearError: true,
      );
      await _maybeMarkRead(bookingId);
    } on AppException catch (e) {
      if (_disposed) return;
      _handleLoadError(e.message);
    } catch (_) {
      if (_disposed) return;
      _handleLoadError('Could not load this conversation. Please try again.');
    }
  }

  /// Only surfaces the error state when nothing has been rendered yet - an
  /// already visible thread (or in-flight optimistic message) is never wiped.
  void _handleLoadError(String message) {
    if (state.status != MessagesStatus.loading) return;
    if (state.messages.isEmpty) {
      state = MessagesState(status: MessagesStatus.error, error: message);
    } else {
      // The user already sent a message while the initial load was in flight;
      // show the partial thread instead of a full-screen error or a spinner
      // that would hide the optimistic bubble forever.
      state = state.copyWith(status: MessagesStatus.ready);
    }
  }

  /// Real-time delivery: the backend pushes every new message over the socket,
  /// so bubbles appear instantly instead of waiting for the next poll.
  void _listenRealtime(String bookingId) {
    final client = ref.read(realtimeClientProvider);
    client.start().catchError((Object _) {});
    _realtimeSub = client.events.listen((event) {
      if (_disposed) return;
      if (event.op == 'typing') {
        final isTyping = (event.payload['is_typing'] as bool? ?? false);
        _typingClearTimer?.cancel();
        state = state.copyWith(otherTyping: isTyping);
        if (isTyping) {
          _typingClearTimer = Timer(const Duration(seconds: 4), () {
            if (!_disposed) state = state.copyWith(otherTyping: false);
          });
        }
        return;
      }
      if (event.op != 'message') return;
      final msg = Message.fromJson(event.payload);
      final conversationId = state.conversation?.id;
      if (conversationId == null || msg.conversationId != conversationId) return;
      if (state.messages.any((m) => m.id == msg.id)) return;
      state = state.copyWith(messages: _merge(state.messages, [msg]));
      _maybeMarkRead(bookingId);
    }, onError: (Object _) {});
  }

  Future<void> _poll(String bookingId) async {
    if (_disposed) return;
    try {
      final messages = await ref.read(messagingApiProvider).fetchMessages(bookingId);
      if (_disposed || state.status != MessagesStatus.ready) return;
      state = state.copyWith(messages: _merge(state.messages, messages));
      await _maybeMarkRead(bookingId);
    } catch (_) {
      // Silent: polling must never disrupt the UI.
    }
  }

  Future<void> _maybeMarkRead(String bookingId) async {
    final current = state;
    if (current.status != MessagesStatus.ready || current.conversation == null) return;
    // Any unread message means the counterpart sent something new. The backend
    // scopes the update to messages addressed to this user, so a stale read on
    // our own outgoing messages is harmless.
    final unreadFromOther = current.messages.any((m) => !m.isRead);
    if (!unreadFromOther) return;
    try {
      await ref.read(messagingApiProvider).markRead(bookingId);
    } catch (_) {
      // Best effort; the next poll will retry.
    }
  }

  /// Sends a message. The bubble appears immediately (optimistic) and is
  /// swapped for the server-confirmed copy on success, or marked failed on
  /// error. [localBytes] renders the image straight from memory while the
  /// upload is still in flight so the bubble shows on the wall instantly.
  /// [localId] reuses an existing optimistic bubble (image flow) instead of
  /// creating a new one.
  Future<bool> send(
    String text, {
    required String senderId,
    MessageType type = MessageType.text,
    String? mediaAssetId,
    String? mediaUrl,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    double? latitude,
    double? longitude,
    String? address,
    CallKind? callType,
    CallStatus? callStatus,
    Uint8List? localBytes,
    String? localId,
  }) async {
    final body = text.trim();
    if (type == MessageType.text && body.isEmpty && localId == null) return false;
    if (type == MessageType.image &&
        mediaUrl == null &&
        localBytes == null) {
      return false;
    }
    if (type == MessageType.location &&
        (latitude == null || longitude == null)) {
      return false;
    }

    final conversation = state.conversation;
    final recipientId = conversation != null
        ? (senderId == conversation.professionalUserId
            ? conversation.customerId
            : conversation.professionalUserId)
        : '';

    final id = localId ?? 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Message(
      id: id,
      conversationId: arg,
      senderId: senderId,
      recipientId: recipientId,
      body: body,
      type: type,
      mediaAssetId: mediaAssetId,
      mediaUrl: mediaUrl ?? '',
      mimeType: mimeType ?? '',
      durationMs: durationMs,
      width: width,
      height: height,
      latitude: latitude,
      longitude: longitude,
      address: address ?? '',
      callType: callType,
      callStatus: callStatus,
      localBytes: localBytes,
      createdAt: DateTime.now(),
      pending: true,
    );

    if (localId == null) {
      state = state.copyWith(
        sendError: null,
        messages: [...state.messages, optimistic],
      );
    } else {
      state = state.copyWith(
        sendError: null,
        messages: state.messages.map((m) => m.id == localId ? optimistic : m).toList(),
      );
    }
    try {
      final message = await ref.read(messagingApiProvider).sendMessage(
            arg,
            body: body,
            type: _typeName(type),
            mediaAssetId: mediaAssetId,
            mediaUrl: mediaUrl,
            mimeType: mimeType,
            durationMs: durationMs,
            width: width,
            height: height,
            latitude: latitude,
            longitude: longitude,
            address: address,
            callType: _callKindName(callType),
            callStatus: _callStatusName(callStatus),
          );
      if (_disposed) return false;
      state = state.copyWith(
        messages: state.messages
            .map((m) => m.id == id ? message : m)
            .toList(),
      );
      return true;
    } on AppException catch (e) {
      if (_disposed) return false;
      state = state.copyWith(
        sendError: e.message,
        messages: _markFailed(state.messages, id, e.message),
      );
      return false;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        sendError: 'Could not send your message. Please try again.',
        messages: _markFailed(
            state.messages, id, 'Could not send your message. Please try again.'),
      );
      return false;
    }
  }

  /// Adds an optimistic image bubble rendered straight from [bytes] and returns
  /// its local id, so the caller can commit it (with the uploaded URL) or let
  /// [send] mark it failed once the upload + send round-trip finishes. The
  /// image appears on the chat wall instantly instead of waiting on the upload.
  String addOptimisticImage(Uint8List bytes, {required String senderId}) {
    if (state.status != MessagesStatus.ready) return '';
    final conversation = state.conversation;
    final recipientId = conversation != null
        ? (senderId == conversation.professionalUserId
            ? conversation.customerId
            : conversation.professionalUserId)
        : '';
    final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final msg = Message(
      id: id,
      conversationId: arg,
      senderId: senderId,
      recipientId: recipientId,
      body: '',
      type: MessageType.image,
      localBytes: bytes,
      createdAt: DateTime.now(),
      pending: true,
    );
    state = state.copyWith(messages: [...state.messages, msg]);
    return id;
  }

  /// Loads older messages using keyset pagination keyed on the oldest loaded
  /// message - stable even when new messages keep arriving above it.
  Future<void> loadMore() async {
    if (_disposed) return;
    final current = state;
    if (!current.hasMore || current.loadingMore || current.status != MessagesStatus.ready) return;
    if (current.messages.isEmpty) return;
    state = current.copyWith(loadingMore: true);
    final oldest = current.messages.first;
    try {
      final older = await ref.read(messagingApiProvider).fetchMessages(
            arg,
            limit: _pageSize,
            before: oldest.createdAt,
            beforeId: oldest.id,
          );
      if (_disposed) return;
      state = state.copyWith(
        loadingMore: false,
        messages: _merge(state.messages, older),
        hasMore: older.length >= _pageSize,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Merges by id and keeps chronological order (newest last). [existing] is
  /// already ascending; [incoming] is the server's newest-first page and is
  /// normalised to ascending. Messages that share a timestamp keep their
  /// server order, so bubbles never jump between polls.
  List<Message> _merge(List<Message> existing, List<Message> incoming) {
    final kept = <Message>[];
    final seen = <String>{};
    for (final m in existing) {
      if (seen.add(m.id)) kept.add(m);
    }
    final fresh = <Message>[];
    for (final m in incoming) {
      if (seen.add(m.id)) fresh.add(m);
    }
    final indexed = fresh.asMap().entries.toList()
      ..sort((a, b) {
        final byTime = _compareAsc(a.value, b.value);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    final sorted = [for (final e in indexed) e.value];
    return _stableMergeAsc(kept, sorted);
  }

  /// Removes a local (optimistic) message by its temporary id.
  List<Message> _dropLocal(List<Message> messages, String localId) =>
      [for (final m in messages) if (m.id != localId) m];

  /// Marks a local message as failed instead of removing it, so the user
  /// can see the error and tap to retry.
  List<Message> _markFailed(List<Message> messages, String localId, String error) =>
      [for (final m in messages)
        if (m.id == localId)
          m.copyWith(sendFailed: true, sendError: error, pending: false)
        else
          m
      ];

  /// Retries a failed send by removing the failed bubble and re-sending.
  Future<void> retrySend(String failedMessageId, {required String senderId}) async {
    final current = state;
    final failed = current.messages.where((m) => m.id == failedMessageId).firstOrNull;
    if (failed == null || !failed.sendFailed) return;
    // Remove the failed bubble
    state = state.copyWith(messages: _dropLocal(current.messages, failedMessageId));
    // Re-send
    await send(
      failed.body,
      senderId: senderId,
      type: failed.type,
      mediaAssetId: failed.mediaAssetId,
      mediaUrl: failed.mediaUrl.isEmpty ? null : failed.mediaUrl,
      mimeType: failed.mimeType.isEmpty ? null : failed.mimeType,
      durationMs: failed.durationMs,
      width: failed.width,
      height: failed.height,
      latitude: failed.latitude,
      longitude: failed.longitude,
      address: failed.address.isEmpty ? null : failed.address,
      callType: failed.callType,
      callStatus: failed.callStatus,
    );
  }
}

/// Stable merge of two ascending lists; [a] wins timestamp ties so the
/// ordering is deterministic across polls.
List<Message> _stableMergeAsc(List<Message> a, List<Message> b) {
  final result = <Message>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (_compareAsc(a[i], b[j]) <= 0) {
      result.add(a[i]);
      i++;
    } else {
      result.add(b[j]);
      j++;
    }
  }
  result.addAll(a.sublist(i));
  result.addAll(b.sublist(j));
  return result;
}

int _compareAsc(Message a, Message b) =>
    (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));

String _typeName(MessageType type) {
  switch (type) {
    case MessageType.image:
      return 'image';
    case MessageType.voice:
      return 'voice';
    case MessageType.video:
      return 'video';
    case MessageType.location:
      return 'location';
    case MessageType.call:
      return 'call';
    case MessageType.text:
      return 'text';
  }
}

String? _callKindName(CallKind? kind) {
  switch (kind) {
    case CallKind.voice:
      return 'voice';
    case CallKind.video:
      return 'video';
    case null:
      return null;
  }
}

String? _callStatusName(CallStatus? status) {
  switch (status) {
    case CallStatus.answered:
      return 'answered';
    case CallStatus.missed:
      return 'missed';
    case CallStatus.declined:
      return 'declined';
    case null:
      return null;
  }
}

final messagesControllerProvider =
    NotifierProvider.family<MessagesController, MessagesState, String>(
  MessagesController.new,
);
