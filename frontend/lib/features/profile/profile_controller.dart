import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../features/auth/auth_controller.dart';
import '../../models/notification_item.dart';
import '../../models/user.dart';
import 'data/profile_api.dart';

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

enum ProfileStatus { loading, ready, error }

class ProfileState {
  const ProfileState({required this.status, this.user, this.error});

  final ProfileStatus status;
  final User? user;
  final String? error;
}

/// Loads the current user's profile and keeps the session in sync on edit.
class ProfileController extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    _load();
    return const ProfileState(status: ProfileStatus.loading);
  }

  Future<void> _load() async {
    try {
      final user = await ref.read(profileApiProvider).fetchMe();
      state = ProfileState(status: ProfileStatus.ready, user: user);
    } on AppException catch (e) {
      state = ProfileState(status: ProfileStatus.error, error: e.message);
    } catch (_) {
      state = const ProfileState(
        status: ProfileStatus.error,
        error: 'Could not load your profile. Please try again.',
      );
    }
  }

  Future<void> refresh() => _load();

  /// Updates the profile and refreshes both this controller and the auth session.
  /// Rethrows [AppException] so callers can surface the message.
  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
  }) async {
    final user = await ref.read(profileApiProvider).updateProfile(
          firstName: firstName,
          lastName: lastName,
          email: email,
        );
    await ref.read(authControllerProvider.notifier).updateUser(user);
    state = ProfileState(status: ProfileStatus.ready, user: user);
  }
}

final profileControllerProvider = NotifierProvider<ProfileController, ProfileState>(
  ProfileController.new,
);

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

enum NotificationsStatus { loading, ready, error }

class NotificationsState {
  const NotificationsState({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.unreadCount = 0,
    this.error,
  });

  final NotificationsStatus status;
  final List<GlameaNotification> items;
  final int total;
  final int unreadCount;
  final String? error;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<GlameaNotification>? items,
    int? total,
    int? unreadCount,
    String? error,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      unreadCount: unreadCount ?? this.unreadCount,
      error: error ?? this.error,
    );
  }
}

/// Loads the user's notifications + unread count and supports read actions.
class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() {
    _load();
    return const NotificationsState(status: NotificationsStatus.loading);
  }

  Future<void> _load() async {
    try {
      final api = ref.read(profileApiProvider);
      final result = await api.fetchNotifications();
      final unread = await api.unreadCount();
      state = NotificationsState(
        status: NotificationsStatus.ready,
        items: result.items,
        total: result.total,
        unreadCount: unread,
      );
    } on AppException catch (e) {
      state = NotificationsState(status: NotificationsStatus.error, error: e.message);
    } catch (_) {
      state = const NotificationsState(
        status: NotificationsStatus.error,
        error: 'Could not load notifications. Please try again.',
      );
    }
  }

  Future<void> refresh() => _load();

  Future<void> markRead(String id) async {
    try {
      await ref.read(profileApiProvider).markRead(id);
    } catch (_) {
      return;
    }
    state = state.copyWith(
      unreadCount: state.unreadCount > 0 ? state.unreadCount - 1 : 0,
      items: [
        for (final item in state.items)
          item.id == id ? item.copyWith(isRead: true) : item,
      ],
    );
  }

  Future<void> markAllRead() async {
    try {
      await ref.read(profileApiProvider).markAllRead();
    } catch (_) {
      return;
    }
    state = state.copyWith(
      unreadCount: 0,
      items: [for (final item in state.items) item.copyWith(isRead: true)],
    );
  }
}

final notificationsControllerProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);
