import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../storage/token_storage.dart';
import 'session.dart';

/// One centralized API client (spec section 4).
/// UI -> Provider/Controller -> Repository -> ApiClient -> Go Backend.
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      },
    ),
  );

  // Single-flight refresh: concurrent 401s all await the same rotation instead
  // of each trying to refresh the same token. The backend atomically revokes a
  // refresh token on use (internal/auth/session.go Revoke), so parallel refreshes
  // would make every request but the first fail and wrongly log the user out.
  Future<Map<String, dynamic>?>? refreshInFlight;

  /// Returns the new token pair, or null when there is no refresh token to
  /// use (the request simply had no session - not a reason to log out).
  Future<Map<String, dynamic>?> refreshOnce() {
    final inFlight = refreshInFlight;
    if (inFlight != null) return inFlight;
    final started = () async {
      final storage = ref.read(tokenStorageProvider);
      final refreshToken = await storage.readRefreshToken();
      if (refreshToken == null) return null;
      return _refresh(refreshToken);
    }();
    refreshInFlight = started;
    unawaited(started.whenComplete(() {
      if (identical(refreshInFlight, started)) refreshInFlight = null;
    }));
    return started;
  }

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await ref.read(tokenStorageProvider).readAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // On 401, try to refresh once and retry (spec section 19).
        final retried = error.requestOptions.headers['__retried'] == true;
        final path = error.requestOptions.path;
        // Auth endpoints return 401 for invalid credentials, not an expired
        // session; never trigger a refresh-retry cycle for them.
        final isCredentialEndpoint =
            path == '/auth/login' || path == '/auth/register';
        if (error.response?.statusCode == 401 &&
            !retried &&
            !isCredentialEndpoint) {
          try {
            final newPair = await refreshOnce();
            if (newPair == null) {
              // No refresh token: there is no session to restore, so surface
              // the error instead of tearing down state mid-restore.
              handler.next(error);
              return;
            }
            final accessToken = newPair['access_token'] as String?;
            if (accessToken == null) {
              throw const FormatException('refresh response has no access_token');
            }
            await ref.read(tokenStorageProvider).writeTokens(
                  accessToken: accessToken,
                  refreshToken: newPair['refresh_token'] as String?,
                );
            final request = error.requestOptions;
            request.headers['__retried'] = true;
            request.headers['Authorization'] = 'Bearer $accessToken';
            final response = await dio.fetch(request);
            handler.resolve(response);
            return;
          } on DioException catch (e) {
            // Only a real auth rejection (401/403) from the refresh endpoint
            // means the session is dead. Server errors (5xx), timeouts, and
            // network failures all leave the session intact so the user
            // stays logged out.
            final status = e.response?.statusCode;
            if (status == 401 || status == 403) {
              await ref.read(tokenStorageProvider).clear();
              ref.read(sessionExpiryProvider.notifier).trigger();
            }
            // When offline or on a 5xx, surface a network error instead of
            // the stale 401 so callers show a retry prompt, not a session-
            // expired screen.
            handler.next(DioException(
              requestOptions: error.requestOptions,
              type: DioExceptionType.connectionError,
              error: e,
            ));
            return;
          } catch (_) {
            // Malformed refresh response: leave the session untouched but
            // surface a network error so callers show a retry prompt instead
            // of a false "session expired" error.
            handler.next(DioException(
              requestOptions: error.requestOptions,
              type: DioExceptionType.connectionError,
            ));
            return;
          }
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});

Future<Map<String, dynamic>> _refresh(String refreshToken) async {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
    ),
  );
  final response = await dio.post<Map<String, dynamic>>(
    '/auth/refresh',
    data: {'refresh_token': refreshToken},
  );
  final body = response.data;
  if (body == null) return {};
  final data = body['data'];
  final tokens = data is Map<String, dynamic> ? data['tokens'] : null;
  return tokens is Map<String, dynamic> ? tokens : {};
}

/// Backend standard response envelope:
/// success -> { "data": ... }, error -> { "error": { "code", "message" } }.
class ApiEnvelope {
  const ApiEnvelope({required this.data, this.meta});

  factory ApiEnvelope.fromJson(Map<String, dynamic> json) {
    return ApiEnvelope(
      data: json['data'],
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }

  final dynamic data;
  final Map<String, dynamic>? meta;
}

/// Helpers for image URLs (Cloudinary optimization).
abstract final class ImageUrls {
  static String? uri(String? url) {
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// Requests a resized, auto-optimized variant from Cloudinary.
  static String? thumb(String? url, {int width = 400}) {
    final u = uri(url);
    if (u == null) return null;
    if (u.contains('res.cloudinary.com') && u.contains('/upload/')) {
      return u.replaceFirst('/upload/', '/upload/w_$width,q_auto,f_auto/');
    }
    return u;
  }
}
