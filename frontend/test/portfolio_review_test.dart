import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/core/utils/formatters.dart';
import 'package:glamea/models/portfolio_item.dart';
import 'package:glamea/models/review.dart';

void main() {
  group('MediaAsset', () {
    test('parses asset with secure URL', () {
      final asset = MediaAsset.fromJson(const {
        'id': 'm-1',
        'uploader_id': 'u-1',
        'provider': 'cloudinary',
        'public_id': 'glamea/look1',
        'resource_type': 'image',
        'format': 'jpg',
        'width': 1200,
        'height': 1500,
        'bytes': 204800,
        'secure_url': 'https://res.cloudinary.com/x/glamea/look1.jpg',
        'folder': 'glamea',
      });

      expect(asset.id, 'm-1');
      expect(asset.width, 1200);
      expect(asset.secureUrl, 'https://res.cloudinary.com/x/glamea/look1.jpg');
    });

    test('asset without URL is not image', () {
      final item = PortfolioItem.fromJson(const {
        'id': 'i-1',
        'professional_id': 'pro-1',
        'asset': {'id': 'm-1'},
      });

      expect(item.hasImage, isFalse);
      expect(item.imageUrl, isEmpty);
    });
  });

  group('PortfolioItem', () {
    const itemJson = {
      'id': 'i-1',
      'professional_id': 'pro-1',
      'media_asset_id': 'm-1',
      'service_id': 's-1',
      'caption': 'Soft glam for the wedding',
      'is_featured': true,
      'display_order': 2,
      'is_verification': false,
      'asset': {
        'id': 'm-1',
        'secure_url': 'https://res.cloudinary.com/x/glamea/soft-glam.jpg',
      },
    };

    test('parses item with nested asset', () {
      final item = PortfolioItem.fromJson(itemJson);

      expect(item.id, 'i-1');
      expect(item.professionalId, 'pro-1');
      expect(item.serviceId, 's-1');
      expect(item.caption, 'Soft glam for the wedding');
      expect(item.isFeatured, isTrue);
      expect(item.displayOrder, 2);
      expect(item.hasImage, isTrue);
      expect(item.imageUrl, 'https://res.cloudinary.com/x/glamea/soft-glam.jpg');
    });

    test('missing asset fields fall back safely', () {
      final item = PortfolioItem.fromJson(const {
        'id': 'i-2',
        'professional_id': 'pro-1',
      });

      expect(item.mediaAssetId, isNull);
      expect(item.caption, isEmpty);
      expect(item.isFeatured, isFalse);
      expect(item.asset, isNull);
    });
  });

  group('Review', () {
    const reviewJson = {
      'id': 'r-1',
      'booking_id': 'b-1',
      'professional_id': 'pro-1',
      'customer_id': 'c-1',
      'service_id': 's-1',
      'rating': 5,
      'comment': 'Loved it',
      'response': 'Thank you!',
      'responded_at': '2026-08-14T09:00:00Z',
      'is_published': true,
      'created_at': '2026-08-13T08:25:09Z',
      'professional_name': "Ada's Beauty Studio",
      'customer_name': 'Adaeze Okafor',
    };

    test('parses full review payload', () {
      final review = Review.fromJson(reviewJson);

      expect(review.id, 'r-1');
      expect(review.bookingId, 'b-1');
      expect(review.rating, 5);
      expect(review.comment, 'Loved it');
      expect(review.response, 'Thank you!');
      expect(review.customerName, 'Adaeze Okafor');
      expect(review.professionalName, "Ada's Beauty Studio");
      expect(review.respondedAt, isNotNull);
      expect(review.createdAt, isNotNull);
    });

    test('response is null when absent', () {
      final review = Review.fromJson(const {
        'id': 'r-2',
        'professional_id': 'pro-1',
        'rating': 4,
        'comment': 'Good',
      });

      expect(review.response, isNull);
      expect(review.respondedAt, isNull);
      expect(review.rating, 4);
    });

    test('rating defaults to 0', () {
      final review = Review.fromJson(const {
        'id': 'r-3',
        'professional_id': 'pro-1',
      });

      expect(review.rating, 0);
      expect(review.comment, isEmpty);
      expect(review.createdAt, isNull);
    });
  });

  group('Formatters', () {
    test('date formats to day month year', () {
      expect(
        Formatters.date(DateTime.utc(2026, 8, 13)),
        '13 Aug 2026',
      );
    });

    test('date handles null', () {
      expect(Formatters.date(null), isEmpty);
    });
  });
}
