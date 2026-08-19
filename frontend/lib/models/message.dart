/// A single chat message (backend `messaging.Message`).
import 'dart:typed_data';

enum MessageType { text, image, voice, video, location, call }

/// Kind of a call message (voice or video).
enum CallKind { voice, video }

/// Outcome of a call message (how the call ended).
enum CallStatus { answered, missed, declined }

/// A single chat message (backend `messaging.Message`).
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.body,
    this.type = MessageType.text,
    this.mediaAssetId,
    this.mediaUrl = '',
    this.mimeType = '',
    this.durationMs,
    this.width,
    this.height,
    this.latitude,
    this.longitude,
    this.address = '',
    this.callType,
    this.callStatus,
    this.isRead = false,
    this.readAt,
    this.createdAt,
    this.localBytes,
    this.pending = false,
    this.sendFailed = false,
    this.sendError,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final type = _parseType(json['type'] as String? ?? '');
    return Message(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      recipientId: json['recipient_id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: type,
      mediaAssetId: json['media_asset_id'] as String?,
      mediaUrl: json['media_url'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      address: json['address'] as String? ?? '',
      callType: _parseCallKind(json['call_type'] as String? ?? ''),
      callStatus: _parseCallStatus(json['call_status'] as String? ?? ''),
      isRead: json['is_read'] as bool? ?? false,
      readAt: DateTime.tryParse(json['read_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String body;
  final MessageType type;
  final String? mediaAssetId;
  final String mediaUrl;
  final String mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final double? latitude;
  final double? longitude;
  final String address;
  final CallKind? callType;
  final CallStatus? callStatus;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;

  /// Local image bytes for an optimistic, not-yet-uploaded image message.
  /// Rendered directly on the chat wall while the upload is in flight.
  final Uint8List? localBytes;

  /// True for an optimistic, not-yet-acked local message (sending state).
  final bool pending;

  /// True when the server rejected the send; the message stays visible with a
  /// retry affordance instead of being silently removed.
  final bool sendFailed;
  final String? sendError;

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? recipientId,
    String? body,
    MessageType? type,
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
    bool? isRead,
    DateTime? readAt,
    DateTime? createdAt,
    Uint8List? localBytes,
    bool? pending,
    bool? sendFailed,
    String? sendError,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      body: body ?? this.body,
      type: type ?? this.type,
      mediaAssetId: mediaAssetId ?? this.mediaAssetId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mimeType: mimeType ?? this.mimeType,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      callType: callType ?? this.callType,
      callStatus: callStatus ?? this.callStatus,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
      localBytes: localBytes ?? this.localBytes,
      pending: pending ?? this.pending,
      sendFailed: sendFailed ?? this.sendFailed,
      sendError: sendError ?? this.sendError,
    );
  }

  bool isMine(String currentUserId) => senderId == currentUserId;

  /// Preview text shown in the conversations list for this message.
  String get preview {
    switch (type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.voice:
        return '🎤 Voice message';
      case MessageType.video:
        return '🎬 Video message';
      case MessageType.location:
        return '📍 Location';
      case MessageType.call:
        final kind = callType == CallKind.video ? '📹 Video call' : '📞 Call';
        return callStatus == CallStatus.missed ? 'Missed $kind' : kind;
      case MessageType.text:
        return body;
    }
  }
}

MessageType _parseType(String raw) {
  switch (raw.toUpperCase()) {
    case 'IMAGE':
      return MessageType.image;
    case 'VOICE':
      return MessageType.voice;
    case 'VIDEO':
      return MessageType.video;
    case 'LOCATION':
      return MessageType.location;
    case 'CALL':
      return MessageType.call;
    default:
      return MessageType.text;
  }
}

CallKind? _parseCallKind(String raw) {
  switch (raw.toUpperCase()) {
    case 'VOICE':
      return CallKind.voice;
    case 'VIDEO':
      return CallKind.video;
    default:
      return null;
  }
}

CallStatus? _parseCallStatus(String raw) {
  switch (raw.toUpperCase()) {
    case 'ANSWERED':
      return CallStatus.answered;
    case 'MISSED':
      return CallStatus.missed;
    case 'DECLINED':
      return CallStatus.declined;
    default:
      return null;
  }
}
