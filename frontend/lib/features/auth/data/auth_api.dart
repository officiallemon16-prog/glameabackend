import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/user.dart';

/// Result of a successful login/register.
class AuthResult {
  const AuthResult(
      {required this.user,
      required this.accessToken,
      required this.refreshToken});

  final User user;
  final String accessToken;
  final String refreshToken;
}

/// Auth endpoints (spec section 17 AUTH).
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<AuthResult> login(String identifier, String password) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'identifier': identifier, 'password': password},
      );
      return _parseAuth(res.data);
    });
  }

  Future<AuthResult> register({
    required String firstName,
    required String lastName,
    String? email,
    String? phone,
    required String password,
    String role = 'CUSTOMER',
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'email': email ?? '',
          'phone': phone ?? '',
          'password': password,
          'role': role,
        },
      );
      return _parseAuth(res.data);
    });
  }

  Future<void> logout(String refreshToken) {
    return _guard(() async {
      await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
    });
  }

  Future<void> verifyPhone(String phone, String code) {
    return _guard(() async {
      await _dio
          .post('/auth/verify-phone', data: {'phone': phone, 'code': code});
    });
  }

  Future<void> resendOtp(String phone) {
    return _guard(() async {
      await _dio.post('/auth/resend-otp', data: {'phone': phone});
    });
  }

  Future<void> sendEmailCode(String email) {
    return _guard(() async {
      await _dio.post('/auth/send-email-code', data: {'email': email});
    });
  }

  Future<void> verifyEmail(String email, String code) {
    return _guard(() async {
      await _dio
          .post('/auth/verify-email', data: {'email': email, 'code': code});
    });
  }

  Future<AuthResult> clerkSync({
    required String clerkUserId,
    String? email,
    String? firstName,
    String? lastName,
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/clerk-sync',
        data: {
          'clerk_user_id': clerkUserId,
          if (email != null) 'email': email,
          if (firstName != null) 'first_name': firstName,
          if (lastName != null) 'last_name': lastName,
        },
      );
      return _parseAuth(res.data);
    });
  }

  Future<AuthResult> socialLogin({
    required String provider,
    required String idToken,
    String? email,
    String? displayName,
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/$provider',
        data: {
          'id_token': idToken,
          if (email != null) 'email': email,
          if (displayName != null) 'display_name': displayName,
        },
      );
      return _parseAuth(res.data);
    });
  }

  /// Wraps transport errors so controllers always receive [AppException]s.
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  AuthResult _parseAuth(Map<String, dynamic>? body) {
    final data = (body?['data'] as Map<String, dynamic>?) ?? const {};
    final user =
        User.fromJson((data['user'] as Map<String, dynamic>?) ?? const {});
    final tokens = (data['tokens'] as Map<String, dynamic>?) ?? const {};
    return AuthResult(
      user: user,
      accessToken: tokens['access_token'] as String? ?? '',
      refreshToken: tokens['refresh_token'] as String? ?? '',
    );
  }
}

final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
