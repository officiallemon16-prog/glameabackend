/// A message thread between a customer and a professional for a booking
/// (backend `messaging.Conversation`).
class Conversation {
  const Conversation({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.professionalId,
    this.professionalUserId = '',
    this.lastMessage = '',
    this.lastMessageAt,
    this.createdAt,
    this.updatedAt,
    this.professionalName = '',
    this.customerName = '',
    this.serviceName = '',
    this.professionalAvatarUrl = '',
    this.customerAvatarUrl = '',
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String? ?? '',
      customerId: json['customer_id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      professionalUserId: json['professional_user_id'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageAt: DateTime.tryParse(json['last_message_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      professionalName: json['professional_name'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      serviceName: json['service_name'] as String? ?? '',
      professionalAvatarUrl: json['professional_avatar_url'] as String? ?? '',
      customerAvatarUrl: json['customer_avatar_url'] as String? ?? '',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String bookingId;
  final String customerId;
  final String professionalId;

  /// The professional's account id (users.id), used to address calls and to
  /// distinguish the pro side from the customer side.
  final String professionalUserId;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String professionalName;
  final String customerName;
  final String serviceName;
  final String professionalAvatarUrl;
  final String customerAvatarUrl;
  final int unreadCount;

  /// Name of the party that is not the given user.
  String otherName(String currentUserId) {
    return currentUserId == professionalUserId ? customerName : professionalName;
  }

  /// User id of the party that is not the given user.
  String otherId(String currentUserId) {
    return currentUserId == professionalUserId ? customerId : professionalUserId;
  }

  /// Avatar URL of the party that is not the given user.
  String otherAvatarUrl(String currentUserId) {
    return currentUserId == professionalUserId
        ? customerAvatarUrl
        : professionalAvatarUrl;
  }
}
