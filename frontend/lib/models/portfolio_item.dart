/// Media asset attached to a portfolio item (backend `media.Asset`).
/// `secureUrl` is a CDN/Cloudinary URL ready for display.
class MediaAsset {
  const MediaAsset({
    this.id = '',
    this.uploaderId,
    this.provider = '',
    this.publicId = '',
    this.resourceType = '',
    this.format = '',
    this.width,
    this.height,
    this.durationMs,
    this.bytes = 0,
    this.secureUrl,
    this.folder = '',
  });

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    return MediaAsset(
      id: json['id'] as String? ?? '',
      uploaderId: json['uploader_id'] as String?,
      provider: json['provider'] as String? ?? '',
      publicId: json['public_id'] as String? ?? '',
      resourceType: json['resource_type'] as String? ?? '',
      format: json['format'] as String? ?? '',
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      secureUrl: json['secure_url'] as String?,
      folder: json['folder'] as String? ?? '',
    );
  }

  final String id;
  final String? uploaderId;
  final String provider;
  final String publicId;
  final String resourceType;
  final String format;
  final int? width;
  final int? height;
  final int? durationMs;
  final int bytes;
  final String? secureUrl;
  final String folder;
}

/// A professional's portfolio "look" (backend `portfolio.Item`).
/// `asset` is populated by the portfolio endpoints.
class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.professionalId,
    this.mediaAssetId,
    this.serviceId,
    this.caption = '',
    this.isFeatured = false,
    this.displayOrder = 0,
    this.beforeAfterPairId,
    this.isVerification = false,
    this.asset,
  });

  factory PortfolioItem.fromJson(Map<String, dynamic> json) {
    final assetJson = json['asset'];
    return PortfolioItem(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      mediaAssetId: json['media_asset_id'] as String?,
      serviceId: json['service_id'] as String?,
      caption: json['caption'] as String? ?? '',
      isFeatured: json['is_featured'] as bool? ?? false,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      beforeAfterPairId: json['before_after_pair_id'] as String?,
      isVerification: json['is_verification'] as bool? ?? false,
      asset: assetJson is Map<String, dynamic> ? MediaAsset.fromJson(assetJson) : null,
    );
  }

  final String id;
  final String professionalId;
  final String? mediaAssetId;
  final String? serviceId;
  final String caption;
  final bool isFeatured;
  final int displayOrder;
  final String? beforeAfterPairId;
  final bool isVerification;
  final MediaAsset? asset;

  /// Display URL, falling back to an empty string for placeholders.
  String get imageUrl => asset?.secureUrl ?? '';

  bool get hasImage => imageUrl.isNotEmpty;
}
