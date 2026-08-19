/// An in-app notification for the current user
/// (backend `notifications.Notification`).
class GlameaNotification {
  const GlameaNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body = '',
    this.data,
    this.isRead = false,
    this.readAt,
    this.createdAt,
  });

  factory GlameaNotification.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? data;
    final rawData = json['data'];
    if (rawData is Map<String, dynamic>) {
      data = rawData;
    }
    return GlameaNotification(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: data,
      isRead: json['is_read'] as bool? ?? false,
      readAt: DateTime.tryParse(json['read_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? createdAt;

  GlameaNotification copyWith({bool? isRead, DateTime? readAt}) {
    return GlameaNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }
}
