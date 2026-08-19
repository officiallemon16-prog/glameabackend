import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/core/utils/formatters.dart';
import 'package:glamea/models/beauty_service.dart';
import 'package:glamea/models/category.dart';
import 'package:glamea/models/category_result.dart';
import 'package:glamea/models/deal.dart';
import 'package:glamea/models/home_feed.dart';
import 'package:glamea/models/professional.dart';
import 'package:glamea/models/search_result.dart';

void main() {
  group('Category', () {
    test('parses discovery home payload', () {
      final category = Category.fromJson(const {
        'id': 'cat-1',
        'slug': 'nails',
        'name': 'Nails',
        'description': 'Manicure & pedicure',
        'display_order': 0,
        'is_active': true,
      });

      expect(category.id, 'cat-1');
      expect(category.slug, 'nails');
      expect(category.name, 'Nails');
      expect(category.iconMediaId, isNull);
    });
  });

  group('Professional', () {
    const proJson = {
      'id': 'pro-1',
      'user_id': 'u-1',
      'business_name': 'Ada\u0027s Beauty Studio',
      'display_name': 'Ada\u0027s Studio',
      'bio': 'Expert braids and styling',
      'rating': 5,
      'review_count': 2,
      'booking_count': 4,
      'status': 'ACTIVE',
      'verification_status': 'VERIFIED',
      'city': 'Lagos',
      'country': 'NG',
      'home_service_enabled': true,
      'service_radius_km': 10,
      'travel_fee_per_km': 500,
    };

    test('parses list payload and derives helpers', () {
      final pro = Professional.fromJson(proJson);

      expect(pro.id, 'pro-1');
      expect(pro.name, 'Ada\u0027s Studio');
      expect(pro.verified, isTrue);
      expect(pro.isActive, isTrue);
      expect(pro.location, 'Lagos, NG');
      expect(pro.homeServiceEnabled, isTrue);
      expect(pro.user, isNull);
    });

    test('parses detail payload with nested user', () {
      final pro = Professional.fromJson({
        ...proJson,
        'user': {'first_name': 'Ada', 'last_name': 'Okafor'},
      });

      expect(pro.user?.fullName, 'Ada Okafor');
      expect(pro.user?.avatarMediaId, isNull);
    });

    test('falls back to business name and unverified', () {
      final pro = Professional.fromJson(const {
        'id': 'pro-2',
        'user_id': 'u-2',
        'business_name': 'Glam Bar',
        'status': 'PENDING',
        'verification_status': 'UNVERIFIED',
      });

      expect(pro.name, 'Glam Bar');
      expect(pro.verified, isFalse);
      expect(pro.rating, 0);
      expect(pro.location, '');
    });
  });

  group('BeautyService', () {
    test('parses service payload', () {
      final service = BeautyService.fromJson(const {
        'id': 'svc-1',
        'professional_id': 'pro-1',
        'name': 'Classic Manicure',
        'description': 'Gel removal included',
        'base_price': 1000,
        'currency': 'NGN',
        'duration_minutes': 60,
        'deposit_percentage': 10,
        'home_service_available': false,
        'is_active': true,
      });

      expect(service.id, 'svc-1');
      expect(service.professionalId, 'pro-1');
      expect(service.basePrice, 1000);
      expect(service.currency, 'NGN');
      expect(service.durationMinutes, 60);
      expect(service.homeServiceAvailable, isFalse);
    });
  });

  group('Deal', () {
    test('parses deal and builds badge', () {
      final deal = Deal.fromJson(const {
        'id': 'deal-1',
        'professional_id': 'pro-1',
        'code': 'GLAM10',
        'name': '10% off your first visit',
        'discount_type': 'PERCENT',
        'discount_value': 10,
        'min_order_amount': 1000,
        'times_used': 3,
        'is_active': true,
      });

      expect(deal.code, 'GLAM10');
      expect(deal.isPercent, isTrue);
      expect(deal.badgeLabel, '-10%');
      expect(deal.minOrderAmount, 1000);
    });

    test('fixed deals use currency-agnostic label', () {
      final deal = Deal.fromJson(const {
        'id': 'deal-2',
        'professional_id': 'pro-1',
        'code': 'FIX',
        'name': 'Flat off',
        'discount_type': 'FIXED',
        'discount_value': 500,
      });

      expect(deal.isPercent, isFalse);
      expect(deal.badgeLabel, '-500');
    });
  });

  group('HomeFeed', () {
    test('parses discovery/home data', () {
      final feed = HomeFeed.fromJson({
        'categories': [
          {'id': 'cat-1', 'slug': 'nails', 'name': 'Nails'},
        ],
        'professionals': [
          {'id': 'pro-1', 'user_id': 'u-1', 'business_name': 'Ada', 'rating': 5, 'review_count': 2},
        ],
        'services': [
          {'id': 'svc-1', 'professional_id': 'pro-1', 'name': 'Manicure', 'base_price': 1000, 'currency': 'NGN', 'duration_minutes': 60},
        ],
        'deals': [
          {'id': 'deal-1', 'professional_id': 'pro-1', 'code': 'GLAM10', 'name': 'Offer', 'discount_type': 'PERCENT', 'discount_value': 10},
        ],
      });

      expect(feed.categories, hasLength(1));
      expect(feed.professionals, hasLength(1));
      expect(feed.services, hasLength(1));
      expect(feed.deals, hasLength(1));
    });

    test('tolerates empty data', () {
      final feed = HomeFeed.fromJson(const {});
      expect(feed.categories, isEmpty);
      expect(feed.professionals, isEmpty);
      expect(feed.services, isEmpty);
      expect(feed.deals, isEmpty);
    });
  });

  group('SearchResult', () {
    test('parses discovery/search data', () {
      final result = SearchResult.fromJson({
        'professionals': [
          {'id': 'pro-1', 'user_id': 'u-1', 'business_name': 'Ada', 'rating': 5, 'review_count': 2},
        ],
        'services': [
          {'id': 'svc-1', 'professional_id': 'pro-1', 'name': 'Braids', 'base_price': 5000, 'currency': 'NGN', 'duration_minutes': 120},
        ],
        'total': 3,
      });

      expect(result.professionals, hasLength(1));
      expect(result.services, hasLength(1));
      expect(result.total, 3);
    });
  });

  group('CategoryResult', () {
    test('parses discovery/categories/{slug} data', () {
      final result = CategoryResult.fromJson({
        'category': {'id': 'cat-1', 'slug': 'nails', 'name': 'Nails'},
        'professionals': [
          {'id': 'pro-1', 'user_id': 'u-1', 'business_name': 'Ada', 'rating': 5, 'review_count': 2},
        ],
      });

      expect(result.category.name, 'Nails');
      expect(result.professionals, hasLength(1));
    });
  });

  group('Formatters', () {
    test('money formats NGN without decimals', () {
      expect(Formatters.money(1000, 'NGN'), '\u20A61,000');
    });

    test('money keeps decimals when needed', () {
      expect(Formatters.money(49.9, 'NGN'), '\u20A649.90');
    });

    test('duration formats hours and minutes', () {
      expect(Formatters.duration(45), '45 min');
      expect(Formatters.duration(60), '1 hr');
      expect(Formatters.duration(90), '1 hr 30 min');
    });

    test('compact abbreviates thousands', () {
      expect(Formatters.compact(1200), '1.2k');
      expect(Formatters.compact(250), '250');
    });
  });
}
