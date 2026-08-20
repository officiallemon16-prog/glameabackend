import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/features/auth/auth_controller.dart';
import 'package:glamea/features/profile/data/profile_api.dart';
import 'package:glamea/features/profile/profile_controller.dart';
import 'package:glamea/models/notification_item.dart';
import 'package:glamea/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

const profileUser = User(
  id: 'u-1',
  email: 'amina@glamea.test',
  phone: '+2348011111111',
  firstName: 'Amina',
  lastName: 'Bello',
  role: 'CUSTOMER',
  status: 'ACTIVE',
  emailVerified: true,
  phoneVerified: true,
);

const updatedUser = User(
  id: 'u-1',
  email: 'amina.new@glamea.test',
  phone: '+2348011111111',
  firstName: 'Amina',
  lastName: 'Okafor',
  role: 'CUSTOMER',
  status: 'ACTIVE',
  emailVerified: true,
  phoneVerified: true,
);

class FakeProfileApi extends ProfileApi {
  FakeProfileApi() : super(Dio());

  int unread = 3;
  String? lastFirstName;
  String? lastLastName;
  String? lastEmail;
  final List<String> markedRead = [];
  int markAllReadCalls = 0;

  @override
  Future<User> fetchMe() async => profileUser;

  @override
  Future<User> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? avatarMediaId,
    String? avatarUrl,
  }) async {
    lastFirstName = firstName;
    lastLastName = lastName;
    lastEmail = email;
    return updatedUser;
  }

  @override
  Future<({List<GlameaNotification> items, int total})> fetchNotifications({
    int limit = 50,
    int offset = 0,
  }) async {
    return (
      items: const [
        GlameaNotification(
          id: 'n-1',
          userId: 'u-1',
          type: 'booking',
          title: 'Booking confirmed',
          body: 'Your appointment is set.',
          isRead: false,
        ),
        GlameaNotification(
          id: 'n-2',
          userId: 'u-1',
          type: 'message',
          title: 'New message',
          body: 'The artist replied.',
          isRead: true,
        ),
      ],
      total: 2,
    );
  }

  @override
  Future<int> unreadCount() async => unread;

  @override
  Future<void> markRead(String id) async {
    markedRead.add(id);
    unread = unread > 0 ? unread - 1 : 0;
  }

  @override
  Future<void> markAllRead() async {
    markAllReadCalls += 1;
    unread = 0;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GlameaNotification', () {
    test('parses payload', () {
      final notification = GlameaNotification.fromJson(const {
        'id': 'n-1',
        'user_id': 'u-1',
        'type': 'booking',
        'title': 'Booking confirmed',
        'body': 'Your appointment is set.',
        'is_read': false,
        'created_at': '2026-08-14T09:00:00Z',
      });

      expect(notification.id, 'n-1');
      expect(notification.type, 'booking');
      expect(notification.title, 'Booking confirmed');
      expect(notification.body, 'Your appointment is set.');
      expect(notification.isRead, isFalse);
      expect(notification.createdAt, isNotNull);
    });

    test('missing fields fall back safely', () {
      final notification = GlameaNotification.fromJson(const {'id': 'n-9'});

      expect(notification.title, isEmpty);
      expect(notification.isRead, isFalse);
      expect(notification.createdAt, isNull);
    });

    test('copyWith marks read', () {
      const notification = GlameaNotification(
        id: 'n-1',
        userId: 'u-1',
        type: 'booking',
        title: 'Booking confirmed',
      );

      final read = notification.copyWith(isRead: true);
      expect(read.isRead, isTrue);
      expect(read.title, 'Booking confirmed');
    });
  });

  group('ProfileController', () {
    test('loads profile into ready state', () async {
      final container = ProviderContainer(
        overrides: [profileApiProvider.overrideWithValue(FakeProfileApi())],
      );
      addTearDown(container.dispose);

      expect(container.read(profileControllerProvider).status, ProfileStatus.loading);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(profileControllerProvider);
      expect(state.status, ProfileStatus.ready);
      expect(state.user?.fullName, 'Amina Bello');
    });

    test('updateProfile updates the profile and the auth session', () async {
      final api = FakeProfileApi();
      final container = ProviderContainer(
        overrides: [profileApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container.read(profileControllerProvider.notifier).updateProfile(
            firstName: 'Amina',
            lastName: 'Okafor',
            email: 'amina.new@glamea.test',
          );

      expect(api.lastLastName, 'Okafor');
      expect(api.lastEmail, 'amina.new@glamea.test');
      expect(container.read(profileControllerProvider).user?.fullName, 'Amina Okafor');
      expect(container.read(authControllerProvider).user?.fullName, 'Amina Okafor');
    });
  });

  group('NotificationsController', () {
    test('loads notifications and unread count', () async {
      final container = ProviderContainer(
        overrides: [profileApiProvider.overrideWithValue(FakeProfileApi())],
      );
      addTearDown(container.dispose);

      expect(
        container.read(notificationsControllerProvider).status,
        NotificationsStatus.loading,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(notificationsControllerProvider);
      expect(state.status, NotificationsStatus.ready);
      expect(state.items, hasLength(2));
      expect(state.unreadCount, 3);
    });

    test('markRead marks one item and decrements unread count', () async {
      final api = FakeProfileApi();
      final container = ProviderContainer(
        overrides: [profileApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container.read(notificationsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container.read(notificationsControllerProvider.notifier).markRead('n-1');

      final state = container.read(notificationsControllerProvider);
      expect(api.markedRead, contains('n-1'));
      expect(state.unreadCount, 2);
      expect(state.items.firstWhere((n) => n.id == 'n-1').isRead, isTrue);
    });

    test('markAllRead clears unread and marks every item read', () async {
      final api = FakeProfileApi();
      final container = ProviderContainer(
        overrides: [profileApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      container.read(notificationsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container.read(notificationsControllerProvider.notifier).markAllRead();

      final state = container.read(notificationsControllerProvider);
      expect(api.markAllReadCalls, 1);
      expect(state.unreadCount, 0);
      expect(state.items.every((n) => n.isRead), isTrue);
    });
  });
}
