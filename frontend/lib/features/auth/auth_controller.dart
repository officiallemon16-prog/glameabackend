import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/session.dart';
import '../../core/notifications/device_token_controller.dart';
import '../../core/storage/token_storage.dart';
import '../../models/user.dart';
import 'data/auth_api.dart';

enum AuthStatus {
  initializing,
  unauthenticated,
  authenticating,
  authenticated,
  verifyingPhone
}

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
    this.pendingPhone,
  });

  final AuthStatus status;
  final User? user;
  final String? error;
  final String? pendingPhone;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// Auth controller - the single source of truth for the session.
/// On any state change it notifies the router so redirects stay in sync.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // When the API client can no longer refresh the session, force a local
    // logout so the router redirects to onboarding/login immediately.
    ref.listen(sessionExpiryProvider, (previous, next) {
      if (next == true) {
        ref.read(sessionExpiryProvider.notifier).reset();
        _sessionExpired();
      }
    });
    // Register/unregister this device's push token with the session.
    listenSelf((previous, next) {
      if (next.isAuthenticated) {
        _syncDeviceToken(register: true);
      } else if (previous?.isAuthenticated ?? false) {
        _syncDeviceToken(register: false);
      }
    });
    _restore();
    return const AuthState(status: AuthStatus.initializing);
  }

  /// Keeps the backend device registry in sync with the auth session.
  Future<void> _syncDeviceToken({required bool register}) async {
    final controller = ref.read(deviceTokenControllerProvider.notifier);
    if (register) {
      await controller.registerForCurrentSession();
    } else {
      await controller.unregisterFromCurrentSession();
    }
  }

  Future<void> _restore() async {
    final storage = ref.read(tokenStorageProvider);
    final access = await storage.readAccessToken();
    final cachedUser = await storage.readCurrentUser();
    if (access != null && cachedUser != null) {
      try {
        final user =
            User.fromJson(jsonDecode(cachedUser) as Map<String, dynamic>);
        _set(AuthState(status: AuthStatus.authenticated, user: user));
        return;
      } catch (_) {
        // Cached user data is corrupt – keep the session so the user can
        // still use the app; a background API call will refresh the profile.
        _set(const AuthState(status: AuthStatus.authenticated));
        return;
      }
    }
    _set(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> login(String identifier, String password) async {
    _set(const AuthState(status: AuthStatus.authenticating));
    try {
      final result =
          await ref.read(authApiProvider).login(identifier, password);
      await _persist(result);
      _afterAuth(result.user, requirePhoneVerification: false);
    } catch (e) {
      final msg = e is AppException ? e.message : 'Login failed. Please try again.';
      _fail(msg);
    }
  }

  Future<void> register({
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    required String password,
    String role = 'CUSTOMER',
  }) async {
    _set(const AuthState(status: AuthStatus.authenticating));
    try {
      final result = await ref.read(authApiProvider).register(
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            password: password,
            role: role,
          );
      await _persist(result);
      _afterAuth(result.user, requirePhoneVerification: true);
    } catch (e) {
      final msg = e is AppException ? e.message : 'Registration failed. Please try again.';
      _fail(msg);
    }
  }

  Future<void> verifyOtp(String code) async {
    final phone = state.pendingPhone;
    if (phone == null || phone.isEmpty) return;
    _set(AuthState(
        status: AuthStatus.authenticating,
        user: state.user,
        pendingPhone: phone));
    try {
      await ref.read(authApiProvider).verifyPhone(phone, code);
      final user = state.user;
      if (user != null) {
        _set(AuthState(status: AuthStatus.authenticated, user: user));
      }
    } on AppException catch (e) {
      _set(AuthState(
        status: AuthStatus.verifyingPhone,
        user: state.user,
        pendingPhone: phone,
        error: e.message,
      ));
    }
  }

  Future<void> resendOtp() async {
    final phone = state.pendingPhone;
    if (phone == null || phone.isEmpty) return;
    try {
      await ref.read(authApiProvider).resendOtp(phone);
    } on AppException catch (e) {
      _set(AuthState(
        status: AuthStatus.verifyingPhone,
        user: state.user,
        pendingPhone: phone,
        error: e.message,
      ));
    }
  }

  /// Aborts an in-progress phone verification. Registration was interrupted
  /// before the number was confirmed, so the unverified session is discarded
  /// and the user can restart the flow (register again or log in).
  Future<void> cancelPhoneVerification() async {
    await ref.read(tokenStorageProvider).clear();
    _set(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> logout() async {
    final storage = ref.read(tokenStorageProvider);
    final refresh = await storage.readRefreshToken();
    if (refresh != null) {
      try {
        await ref.read(authApiProvider).logout(refresh);
      } catch (_) {}
    }
    await storage.clear();
    _set(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> socialLogin({
    required String provider,
    required String idToken,
    String? email,
    String? displayName,
  }) async {
    _set(const AuthState(status: AuthStatus.authenticating));
    try {
      final result = await ref.read(authApiProvider).socialLogin(
            provider: provider,
            idToken: idToken,
            email: email,
            displayName: displayName,
          );
      await _persist(result);
      _afterAuth(result.user, requirePhoneVerification: false);
    } catch (e) {
      final msg = e is AppException ? e.message : 'Social sign-in failed. Please try again.';
      _fail(msg);
    }
  }

  Future<void> clerkSync({
    required String clerkUserId,
    String? email,
    String? firstName,
    String? lastName,
  }) async {
    _set(const AuthState(status: AuthStatus.authenticating));
    try {
      final result = await ref.read(authApiProvider).clerkSync(
            clerkUserId: clerkUserId,
            email: email,
            firstName: firstName,
            lastName: lastName,
          );
      await _persist(result);
      _afterAuth(result.user, requirePhoneVerification: false);
    } catch (e) {
      final msg = e is AppException ? e.message : 'Sign-in sync failed. Please try again.';
      _fail(msg);
    }
  }

  /// Clears an expired session without calling the backend (the refresh token
  /// is already invalid, so the normal logout call would just fail).
  Future<void> _sessionExpired() async {
    await ref.read(tokenStorageProvider).clear();
    _set(const AuthState(status: AuthStatus.unauthenticated));
  }

  void clearError() {
    if (state.error != null) {
      _set(AuthState(
        status: state.status,
        user: state.user,
        pendingPhone: state.pendingPhone,
      ));
    }
  }

  /// Persists an updated profile and refreshes the session user.
  Future<void> updateUser(User user) async {
    final storage = ref.read(tokenStorageProvider);
    await storage.saveCurrentUser(jsonEncode(user.toJson()));
    _set(AuthState(status: AuthStatus.authenticated, user: user));
  }

  Future<void> _persist(AuthResult result) async {
    final storage = ref.read(tokenStorageProvider);
    await storage.writeTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await storage.saveCurrentUser(jsonEncode(result.user.toJson()));
  }

  /// Lands the user in the app. Phone verification (OTP) is an onboarding
  /// step tied to registration only; logging in with valid credentials goes
  /// straight to the dashboard.
  void _afterAuth(User user, {required bool requirePhoneVerification}) {
    final phone = user.phone;
    if (requirePhoneVerification &&
        phone != null &&
        phone.isNotEmpty &&
        !user.phoneVerified) {
      _set(AuthState(
          status: AuthStatus.verifyingPhone, user: user, pendingPhone: phone));
    } else {
      _set(AuthState(status: AuthStatus.authenticated, user: user));
    }
  }

  void _fail(String message) {
    _set(AuthState(status: AuthStatus.unauthenticated, error: message));
  }

  void _set(AuthState next) {
    state = next;
    ref.read(routerRefreshProvider).notify();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
