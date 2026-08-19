import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../profile/profile_controller.dart';
import 'auth_controller.dart';
import 'data/auth_api.dart';

enum VerifyEmailStatus { idle, sending, verifying, verified }

class VerifyEmailState {
  const VerifyEmailState({this.status = VerifyEmailStatus.idle, this.error});

  final VerifyEmailStatus status;
  final String? error;

  VerifyEmailState copyWith({VerifyEmailStatus? status, String? error}) {
    return VerifyEmailState(
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}

/// Sends and validates the 6-digit email verification code.
/// On success it refreshes the cached session user so `email_verified` is
/// reflected immediately (profile, onboarding checks, etc.).
class VerifyEmailController extends Notifier<VerifyEmailState> {
  @override
  VerifyEmailState build() => const VerifyEmailState();

  Future<bool> request(String email) async {
    state = const VerifyEmailState(status: VerifyEmailStatus.sending);
    try {
      await ref.read(authApiProvider).sendEmailCode(email);
      state = const VerifyEmailState(status: VerifyEmailStatus.idle);
      return true;
    } on AppException catch (e) {
      state = VerifyEmailState(status: VerifyEmailStatus.idle, error: e.message);
      return false;
    }
  }

  Future<bool> verify(String email, String code) async {
    state = const VerifyEmailState(status: VerifyEmailStatus.verifying);
    try {
      await ref.read(authApiProvider).verifyEmail(email, code);
      await _refreshSessionUser();
      state = const VerifyEmailState(status: VerifyEmailStatus.verified);
      return true;
    } on AppException catch (e) {
      state = VerifyEmailState(status: VerifyEmailStatus.idle, error: e.message);
      return false;
    }
  }

  /// Best-effort: verification already succeeded, so a profile refresh
  /// failure must not surface as a verification error.
  Future<void> _refreshSessionUser() async {
    try {
      final profile = ref.read(profileControllerProvider.notifier);
      await profile.refresh();
      final updated = ref.read(profileControllerProvider).user;
      if (updated != null) {
        await ref.read(authControllerProvider.notifier).updateUser(updated);
      }
    } catch (_) {}
  }
}

final verifyEmailControllerProvider =
    NotifierProvider<VerifyEmailController, VerifyEmailState>(
  VerifyEmailController.new,
);
