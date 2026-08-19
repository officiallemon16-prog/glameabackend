import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/core/errors/app_exception.dart';
import 'package:glamea/features/media/data/media_api.dart';
import 'package:glamea/features/media/media_controller.dart';
import 'package:glamea/models/portfolio_item.dart';
import 'package:image_picker/image_picker.dart';

class FakeMediaApi extends MediaApi {
  FakeMediaApi() : super(Dio());

  UploadCapability capability = const UploadCapability(mode: 'local');
  MediaAsset asset = const MediaAsset(id: 'asset-1', secureUrl: 'http://localhost:8080/uploads/abc.jpg');
  int localCalls = 0;
  int cloudinaryCalls = 0;
  Map<String, dynamic>? lastRegisterPayload;
  String? lastFolder;

  @override
  Future<UploadCapability> fetchUploadCapability({
    String folder = 'glamea/portfolio',
    String resourceType = 'image',
  }) async {
    lastFolder = folder;
    return capability;
  }

  @override
  Future<MediaAsset> uploadLocal(Uint8List bytes, String filename) async {
    localCalls++;
    return asset;
  }

  @override
  Future<MediaAsset> registerAsset(Map<String, dynamic> payload) async {
    lastRegisterPayload = payload;
    return asset;
  }

  @override
  Future<CloudinaryUploadResult> uploadToCloudinary(
    CloudinarySignature signature,
    Uint8List bytes,
    String filename,
  ) async {
    cloudinaryCalls++;
    return const CloudinaryUploadResult(
      publicId: 'p-1',
      secureUrl: 'https://res.cloudinary.com/x/image/upload/p-1.jpg',
      format: 'jpg',
      width: 800,
      height: 600,
      bytes: 1234,
    );
  }
}

void main() {
  group('UploadCapability', () {
    test('parses local mode with max bytes', () {
      final c = UploadCapability.fromJson(const {
        'mode': 'local',
        'max_bytes': 10485760,
      });
      expect(c.isLocal, isTrue);
      expect(c.maxBytes, 10485760);
      expect(c.signature, isNull);
    });

    test('parses cloudinary mode with signature', () {
      final c = UploadCapability.fromJson(const {
        'mode': 'cloudinary',
        'signature': {
          'cloud_name': 'demo',
          'api_key': 'key-1',
          'timestamp': 1234567890,
          'signature': 'sig-1',
          'folder': 'glamea/portfolio',
          'resource_type': 'image',
        },
      });
      expect(c.isLocal, isFalse);
      expect(c.signature?.cloudName, 'demo');
      expect(c.signature?.apiKey, 'key-1');
      expect(c.signature?.timestamp, 1234567890);
      expect(c.signature?.folder, 'glamea/portfolio');
    });
  });

  group('CloudinaryUploadResult', () {
    test('parses upload response', () {
      final r = CloudinaryUploadResult.fromJson(const {
        'public_id': 'p-1',
        'secure_url': 'https://res.cloudinary.com/demo/image/upload/p-1.jpg',
        'format': 'jpg',
        'width': 800,
        'height': 600,
        'bytes': 1234,
      });
      expect(r.publicId, 'p-1');
      expect(r.secureUrl, contains('res.cloudinary.com'));
      expect(r.format, 'jpg');
      expect(r.width, 800);
      expect(r.bytes, 1234);
    });
  });

  group('MediaUploadController', () {
    test('local mode uploads bytes and returns the registered asset', () async {
      final api = FakeMediaApi();
      final container = ProviderContainer(
        overrides: [mediaApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(mediaUploadControllerProvider.notifier);
      final file = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'photo.png');

      final asset = await notifier.uploadImage(file, folder: 'glamea/portfolio');

      expect(asset.id, 'asset-1');
      expect(api.localCalls, 1);
      expect(api.lastFolder, 'glamea/portfolio');
      expect(container.read(mediaUploadControllerProvider).status, MediaUploadStatus.done);
    });

    test('cloudinary mode uploads to provider then registers with public_id', () async {
      final api = FakeMediaApi();
      api.capability = const UploadCapability(
        mode: 'cloudinary',
        signature: CloudinarySignature(
          cloudName: 'demo',
          apiKey: 'key-1',
          timestamp: 123,
          signature: 'sig-1',
          folder: 'glamea/portfolio',
          resourceType: 'image',
        ),
      );
      final container = ProviderContainer(
        overrides: [mediaApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(mediaUploadControllerProvider.notifier);
      final file = XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'photo.jpg');

      final asset = await notifier.uploadImage(file);

      expect(api.cloudinaryCalls, 1);
      expect(api.localCalls, 0);
      expect(api.lastRegisterPayload?['public_id'], 'p-1');
      expect(api.lastRegisterPayload?['provider'], 'cloudinary');
      expect(api.lastRegisterPayload?['width'], 800);
      expect(api.lastRegisterPayload?['folder'], 'glamea/portfolio');
      expect(asset.id, 'asset-1');
    });

    test('api failure surfaces an AppException and sets error state', () async {
      final container = ProviderContainer(
        overrides: [
          mediaApiProvider.overrideWithValue(_FailingMediaApi()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(mediaUploadControllerProvider.notifier);
      final file = XFile.fromData(Uint8List.fromList([1]), name: 'photo.jpg');

      await expectLater(
        notifier.uploadImage(file),
        throwsA(isA<AppException>()),
      );
      expect(container.read(mediaUploadControllerProvider).status, MediaUploadStatus.error);
    });

    test('filenameFromPath strips directories', () {
      expect(filenameFromPath('C:/Users/me/photo.png'), 'photo.png');
      expect(filenameFromPath('folder\\sub\\img.jpg'), 'img.jpg');
      expect(filenameFromPath('photo.webp'), 'photo.webp');
    });
  });
}

class _FailingMediaApi extends MediaApi {
  _FailingMediaApi() : super(Dio());

  @override
  Future<UploadCapability> fetchUploadCapability({
    String folder = 'glamea/portfolio',
    String resourceType = 'image',
  }) async {
    throw const ApiException('Upload failed.', code: 'file_too_large', statusCode: 400);
  }
}
