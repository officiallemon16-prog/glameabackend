import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/app/app.dart';
import 'package:glamea/core/deeplinks/deep_link_controller.dart';
import 'package:glamea/core/deeplinks/deep_link_parser.dart';
import 'package:glamea/features/booking/screens/booking_detail_screen.dart';
import 'package:glamea/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

String cachedUserJson() => jsonEncode(const User(
      id: 'user-1',
      email: 'test@glamea.test',
      firstName: 'Amina',
      lastName: 'Bello',
      role: 'CUSTOMER',
      status: 'ACTIVE',
      emailVerified: true,
      phoneVerified: true,
    ).toJson());

void main() {
  group('deepLinkPath', () {
    test('maps professional links to the router path', () {
      expect(deepLinkPath('glamea://open/professionals/pro-1'), '/professionals/pro-1');
      expect(deepLinkPath('glamea://professional/pro-1'), '/professionals/pro-1');
      expect(deepLinkPath('https://glamea.app/professionals/pro-1'), '/professionals/pro-1');
    });

    test('maps booking links including sub-paths', () {
      expect(deepLinkPath('glamea://open/bookings/b-1'), '/bookings/b-1');
      expect(deepLinkPath('glamea://booking/b-1'), '/bookings/b-1');
      expect(deepLinkPath('glamea://open/bookings/b-1/chat'), '/bookings/b-1/chat');
      expect(deepLinkPath('glamea://open/bookings/b-1/pay'), '/bookings/b-1/pay');
      expect(deepLinkPath('glamea://open/bookings/b-1/dispute'), '/bookings/b-1/dispute');
      expect(deepLinkPath('glamea://open/bookings'), '/bookings');
    });

    test('maps chat/wallet/notifications/favorites links', () {
      expect(deepLinkPath('glamea://chat/b-1'), '/bookings/b-1/chat');
      expect(deepLinkPath('glamea://open/wallet'), '/wallet');
      expect(deepLinkPath('glamea://open/notifications'), '/notifications');
      expect(deepLinkPath('glamea://open/favorites'), '/favorites');
      expect(deepLinkPath('glamea://open/discover'), '/discover');
    });

    test('maps looks, categories, disputes and reviews', () {
      expect(deepLinkPath('glamea://open/looks/look-1'), '/looks/look-1');
      expect(deepLinkPath('glamea://look/look-1'), '/looks/look-1');
      expect(deepLinkPath('glamea://open/categories/nails'), '/categories/nails');
      expect(deepLinkPath('glamea://open/disputes/d-1'), '/disputes/d-1');
      expect(deepLinkPath('glamea://open/disputes'), '/disputes');
      expect(deepLinkPath('glamea://open/reviews'), '/reviews/me');
    });

    test('rejects unknown or malformed links', () {
      expect(deepLinkPath('glamea://open/unknown/thing'), isNull);
      expect(deepLinkPath('glamea://open/professionals'), isNull);
      expect(deepLinkPath(''), isNull);
      expect(deepLinkPath('not a uri'), isNull);
      expect(deepLinkPath('sms://+2348000000000'), isNull);
    });
  });

  group('DeepLinkController', () {
    test('handleRaw queues a parsed path and consume clears it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pendingDeepLinkProvider.notifier);
      notifier.handleRaw('glamea://open/bookings/b-1');

      expect(container.read(pendingDeepLinkProvider), '/bookings/b-1');

      expect(notifier.consume(), '/bookings/b-1');
      expect(container.read(pendingDeepLinkProvider), isNull);
    });

    test('unsupported links are ignored', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(pendingDeepLinkProvider.notifier).handleRaw('glamea://open/unknown/thing');

      expect(container.read(pendingDeepLinkProvider), isNull);
    });
  });

  group('Router deep link integration', () {
    testWidgets('an inbound booking link navigates after the session loads',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'jwt',
        'current_user': cachedUserJson(),
      });
      final container = ProviderContainer();

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const GlameaApp()),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets);

      container.read(pendingDeepLinkProvider.notifier).handleRaw('glamea://open/bookings/b-1');
      await tester.pumpAndSettle();

      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(find.text('Booking details'), findsOneWidget);

      container.dispose();
    });
  });
}
