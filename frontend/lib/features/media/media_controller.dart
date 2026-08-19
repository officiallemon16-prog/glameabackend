import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_exception.dart';
import '../../models/portfolio_item.dart';
import 'data/media_api.dart';

/// Injectable image picker so tests can drive uploads without a platform
/// channel (tests override [imagePickerProvider]).
final imagePickerProvider = Provider<ImagePicker>((_) => ImagePicker());

enum MediaUploadStatus { idle, uploading, done, error }

class MediaUploadState {
  const MediaUploadState({
    this.status = MediaUploadStatus.idle,
    this.asset,
    this.error,
  });

  final MediaUploadStatus status;
  final MediaAsset? asset;
  final String? error;

  bool get isUploading => status == MediaUploadStatus.uploading;
}

/// Orchestrates image picking + upload. Branches on the backend capability:
/// local mode uploads bytes to `/media/upload`, Cloudinary mode uploads
/// directly to Cloudinary then registers the asset.
class MediaUploadController extends Notifier<MediaUploadState> {
  @override
  MediaUploadState build() => const MediaUploadState();

  /// Picks, uploads and registers an image, returning the [MediaAsset] ready
  /// for use as a `media_asset_id`. Throws [AppException] on failure.
  Future<MediaAsset> uploadImage(
    XFile file, {
    String folder = 'glamea/portfolio',
  }) async {
    state = const MediaUploadState(status: MediaUploadStatus.uploading);
    try {
      final api = ref.read(mediaApiProvider);
      final capability = await api.fetchUploadCapability(folder: folder);
      final bytes = await file.readAsBytes();
      final asset = capability.isLocal
          ? await api.uploadLocal(bytes, filenameFromPath(file.name))
          : await _uploadCloudinary(api, capability, bytes, file.name);
      state = MediaUploadState(status: MediaUploadStatus.done, asset: asset);
      return asset;
    } on AppException catch (e) {
      state = MediaUploadState(status: MediaUploadStatus.error, error: e.message);
      rethrow;
    } catch (e) {
      state = const MediaUploadState(
        status: MediaUploadStatus.error,
        error: 'Upload failed. Please try again.');
      rethrow;
    }
  }

  Future<MediaAsset> _uploadCloudinary(
    MediaApi api,
    UploadCapability capability,
    Uint8List bytes,
    String filename,
  ) async {
    final signature = capability.signature;
    if (signature == null) {
      throw const ApiException(
        'Media upload is temporarily unavailable.',
        code: 'cloudinary_not_configured',
        statusCode: 503,
      );
    }
    final result = await api.uploadToCloudinary(signature, bytes, filename);
    return api.registerAsset({
      'provider': 'cloudinary',
      'public_id': result.publicId,
      'resource_type': 'image',
      'format': result.format,
      'width': result.width,
      'height': result.height,
      'bytes': result.bytes,
      'secure_url': result.secureUrl,
      'folder': signature.folder,
    });
  }

  void reset() => state = const MediaUploadState();
}

final mediaUploadControllerProvider =
    NotifierProvider<MediaUploadController, MediaUploadState>(
        MediaUploadController.new);

/// Last path segment of a file path, for use as an upload filename.
String filenameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isEmpty ? 'photo' : segments.last;
}
