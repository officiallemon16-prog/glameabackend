import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart';

final verifyNudgeControllerProvider =
    NotifierProvider<VerifyNudgeController, VerifyNudgeState>(
  VerifyNudgeController.new,
);

class VerifyNudgeState {
  const VerifyNudgeState({this.lastShownAt = 0, this.dismissedAt = 0});

  final int lastShownAt; // epoch ms of last display
  final int dismissedAt; // epoch ms of last dismissal

  VerifyNudgeState copyWith({int? lastShownAt, int? dismissedAt}) {
    return VerifyNudgeState(
      lastShownAt: lastShownAt ?? this.lastShownAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
    );
  }
}

/// Decides when to gently remind an unverified user to verify their account.
/// A reminder is shown at most once per [cooldown] window; dismissing or
/// tapping it resets the window so it does not nag.
class VerifyNudgeController extends Notifier<VerifyNudgeState> {
  static const int _cooldownMs = 3 * 24 * 60 * 60 * 1000; // 3 days

  @override
  VerifyNudgeState build() {
    _load();
    return const VerifyNudgeState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('verify_nudge_last') ?? 0;
    final dismissed = prefs.getInt('verify_nudge_dismissed') ?? 0;
    state = VerifyNudgeState(lastShownAt: last, dismissedAt: dismissed);
  }

  bool shouldShow(User? user) {
    if (user == null) return false;
    if (user.isVerified) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - state.dismissedAt < _cooldownMs) return false;
    if (now - state.lastShownAt < _cooldownMs) return false;
    return true;
  }

  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('verify_nudge_dismissed', now);
    await prefs.setInt('verify_nudge_last', now);
    state = VerifyNudgeState(lastShownAt: now, dismissedAt: now);
  }

  Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('verify_nudge_last', now);
    state = state.copyWith(lastShownAt: now);
  }
}
