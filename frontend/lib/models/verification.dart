/// Professional verification document (backend `verification.Document`).
class VerificationDocument {
  const VerificationDocument({
    required this.id,
    required this.professionalId,
    required this.stage,
    required this.documentType,
    this.mediaAssetId,
    this.status = 'PENDING',
    this.reviewerId,
    this.reviewNote = '',
    this.submittedAt,
    this.reviewedAt,
  });

  factory VerificationDocument.fromJson(Map<String, dynamic> json) {
    return VerificationDocument(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      stage: json['stage'] as String? ?? '',
      documentType: json['document_type'] as String? ?? '',
      mediaAssetId: json['media_asset_id'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      reviewerId: json['reviewer_id'] as String?,
      reviewNote: json['review_note'] as String? ?? '',
      submittedAt: DateTime.tryParse(json['submitted_at'] as String? ?? ''),
      reviewedAt: DateTime.tryParse(json['reviewed_at'] as String? ?? ''),
    );
  }

  final String id;
  final String professionalId;
  final String stage;
  final String documentType;
  final String? mediaAssetId;
  final String status;
  final String? reviewerId;
  final String reviewNote;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';
  bool get isPending => status == 'PENDING' || status == 'REVIEWING';

  String get stageLabel => stage.replaceAll('_', ' ').toLowerCase();
}
