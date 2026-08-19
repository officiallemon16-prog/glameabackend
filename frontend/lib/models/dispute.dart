/// A dispute raised against a booking (backend `disputes.Dispute`).
class Dispute {
  const Dispute({
    required this.id,
    required this.bookingId,
    required this.raisedBy,
    required this.reason,
    required this.status,
    this.description = '',
    this.resolution = '',
    this.resolvedBy,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
    this.raisedByName = '',
  });

  factory Dispute.fromJson(Map<String, dynamic> json) {
    return Dispute(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String? ?? '',
      raisedBy: json['raised_by'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'OPEN',
      resolution: json['resolution'] as String? ?? '',
      resolvedBy: json['resolved_by'] as String?,
      resolvedAt: DateTime.tryParse(json['resolved_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      raisedByName: json['raised_by_name'] as String? ?? '',
    );
  }

  final String id;
  final String bookingId;
  final String raisedBy;
  final String reason;
  final String description;
  final String status;
  final String resolution;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String raisedByName;

  bool get isOpen => status == 'OPEN';
  bool get isResolved => status == 'RESOLVED';
  bool get isClosed => status == 'CLOSED';

  String get statusLabel {
    switch (status) {
      case 'OPEN':
        return 'Open';
      case 'RESOLVED':
        return 'Resolved';
      case 'CLOSED':
        return 'Closed';
      default:
        return status;
    }
  }
}

/// A message inside a dispute thread (backend `disputes.DisputeMessage`).
class DisputeMessage {
  const DisputeMessage({
    required this.id,
    required this.disputeId,
    required this.senderId,
    required this.body,
    this.createdAt,
  });

  factory DisputeMessage.fromJson(Map<String, dynamic> json) {
    return DisputeMessage(
      id: json['id'] as String? ?? '',
      disputeId: json['dispute_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String disputeId;
  final String senderId;
  final String body;
  final DateTime? createdAt;
}
