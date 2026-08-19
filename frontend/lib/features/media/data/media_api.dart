import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/portfolio_item.dart';

/// Describes how the backend wants uploads to be performed.
/// `mode` is `cloudinary` (upload directly to Cloudinary with a signed
/// request) or `local` (upload the bytes to `/media/upload`).
class UploadCapability {
  const UploadCapability({required this.mode, this.signature, this.maxBytes});

  factory UploadCapability.fromJson(Map<String, dynamic> json) {
    final signature = json['signature'];
    return UploadCapability(
      mode: json['mode'] as String? ?? 'cloudinary',
      signature: signature is Map<String, dynamic>
          ? CloudinarySignature.fromJson(signature)
          : null,
      maxBytes: (json['max_bytes'] as num?)?.toInt(),
    );
  }

  final String mode;
  final CloudinarySignature? signature;
  final int? maxBytes;

  bool get isLocal => mode == 'local';
}

/// Signed upload parameters issued by the backend for Cloudinary.
class CloudinarySignature {
  const CloudinarySignature({
    required this.cloudName,
    required this.apiKey,
    required this.timestamp,
    required this.signature,
    required this.folder,
    this.publicId,
    required this.resourceType,
  });

  factory CloudinarySignature.fromJson(Map<String, dynamic> json) {
    return CloudinarySignature(
      cloudName: json['cloud_name'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      signature: json['signature'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      publicId: json['public_id'] as String?,
      resourceType: json['resource_type'] as String? ?? 'image',
    );
  }

  final String cloudName;
  final String apiKey;
  final int timestamp;
  final String signature;
  final String folder;
  final String? publicId;
  final String resourceType;
}

/// Response from Cloudinary's `/upload` endpoint.
class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.publicId,
    required this.secureUrl,
    required this.format,
    this.width,
    this.height,
    this.bytes = 0,
  });

  factory CloudinaryUploadResult.fromJson(Map<String, dynamic> json) {
    return CloudinaryUploadResult(
      publicId: json['public_id'] as String? ?? '',
      secureUrl: json['secure_url'] as String? ?? '',
      format: json['format'] as String? ?? '',
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String publicId;
  final String secureUrl;
  final String format;
  final int? width;
  final int? height;
  final int bytes;
}

/// Media endpoints (spec section 7 MEDIA UPLOADS).
/// All Glamea API calls are routed through [_guard] so failures surface as
/// [AppException]. The direct Cloudinary upload uses a bare [Dio] because it
/// talks to the provider, not our API.
class MediaApi {
  MediaApi(this._dio);

  final Dio _dio;

  /// Fetches upload mode + Cloudinary signature (or `max_bytes` in local mode).
  Future<UploadCapability> fetchUploadCapability({
    String folder = 'glamea/portfolio',
    String resourceType = 'image',
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/media/upload-signature',
        data: {
          'folder': folder,
          'resource_type': resourceType,
          'public_id': '',
        },
      );
      final data = _data(res.data);
      return UploadCapability.fromJson(data);
    });
  }

  /// Uploads raw bytes to the backend's local storage and registers the asset.
  Future<MediaAsset> uploadLocal(Uint8List bytes, String filename) {
    return _guard(() async {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/media/upload',
        data: form,
      );
      final data = _data(res.data);
      return MediaAsset.fromJson(
        data['asset'] as Map<String, dynamic>? ?? const {},
      );
    });
  }

  /// Registers an asset already uploaded to Cloudinary.
  Future<MediaAsset> registerAsset(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/media', data: payload);
      final data = _data(res.data);
      return MediaAsset.fromJson(
        data['asset'] as Map<String, dynamic>? ?? const {},
      );
    });
  }

  /// Uploads bytes directly to Cloudinary using a signed signature.
  Future<CloudinaryUploadResult> uploadToCloudinary(
    CloudinarySignature signature,
    Uint8List bytes,
    String filename,
  ) async {
    final dio = Dio(
      BaseOptions(
        baseUrl:
            'https://api.cloudinary.com/v1_1/${signature.cloudName}/${signature.resourceType}',
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'api_key': signature.apiKey,
      'timestamp': signature.timestamp,
      'signature': signature.signature,
      'folder': signature.folder,
      'resource_type': signature.resourceType,
      if (signature.publicId != null && signature.publicId!.isNotEmpty)
        'public_id': signature.publicId,
    });
    final res = await dio.post<Map<String, dynamic>>('/upload', data: form);
    return CloudinaryUploadResult.fromJson(res.data ?? const {});
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    return data is Map<String, dynamic> ? data : const {};
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapError(e);
    }
  }
}

final mediaApiProvider =
    Provider<MediaApi>((ref) => MediaApi(ref.watch(apiClientProvider)));
