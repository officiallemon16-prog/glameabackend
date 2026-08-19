import 'package:dio/dio.dart';

import '../constants/app_constants.dart';

/// Application error hierarchy.
sealed class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// A 4xx business/validation error returned by the backend.
class ApiException extends AppException {
  const ApiException(super.message, {super.code, required this.statusCode});

  final int statusCode;
}

/// No network connection.
class NetworkException extends AppException {
  const NetworkException(super.message);
}

/// The session expired; user must log in again.
class SessionExpiredException extends AppException {
  const SessionExpiredException(
      [super.message = 'Session expired, please log in again.']);
}

/// An in-flight request was cancelled (e.g. screen disposed).
class RequestCancelledException extends AppException {
  const RequestCancelledException([super.message = 'Request cancelled.']);
}

/// Any unexpected failure.
class UnknownException extends AppException {
  const UnknownException(super.message);
}

/// Maps transport errors to [AppException]s with friendly messages.
AppException mapError(Object error) {
  if (error is AppException) {
    return error;
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkException(
            'Connection lost. Check your network and try again.');
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        final code = _extractCode(error.response?.data);
        final message = _friendlyMessage(code, error.response?.data);
        if (status == 401) {
          return const SessionExpiredException();
        }
        return ApiException(message, code: code, statusCode: status);
      case DioExceptionType.cancel:
        return const RequestCancelledException();
      case DioExceptionType.badCertificate:
        return const NetworkException(
            'Certificate verification failed. Check your network settings.');
      default:
        return const NetworkException(
            'Something went wrong. Please try again.');
    }
  }
  return UnknownException(error.toString());
}

/// Maps errors for auth endpoints (login/register). A 401 there means invalid
/// credentials, not an expired session, so the backend message is surfaced.
AppException mapAuthError(Object error) {
  if (error is DioException && error.response?.statusCode == 401) {
    final data = error.response?.data;
    final code = _extractCode(data);
    return ApiException(
      _friendlyMessage(code, data),
      code: code,
      statusCode: 401,
    );
  }
  return mapError(error);
}

String? _extractCode(Object? data) {
  if (data is Map) {
    final error = data['error'];
    if (error is Map) {
      return error['code']?.toString();
    }
  }
  return null;
}

String _friendlyMessage(String? code, Object? data) {
  final mapped = code != null ? AppConstants.errorMessages[code] : null;
  if (mapped != null) {
    return mapped;
  }
  if (data is Map) {
    final error = data['error'];
    if (error is Map) {
      final msg = error['message'];
      if (msg is String && msg.isNotEmpty) {
        return msg;
      }
    }
  }
  return 'Something went wrong. Please try again.';
}
