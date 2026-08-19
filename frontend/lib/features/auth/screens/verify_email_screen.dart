import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../auth_controller.dart';
import '../verify_email_controller.dart';

/// Route: /verify-email. 6-digit email verification code, reachable from the
/// profile when the account has an unverified email (spec section 17).
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  Timer? _resendTimer;
  int _countdown = 0;

  String get _email =>
      ref.read(authControllerProvider).user?.email?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCountdown();
      ref.read(verifyEmailControllerProvider.notifier).request(_email);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 30);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  void _verify() {
    final code = _code.text.trim();
    if (code.length != 6) return;
    ref.read(verifyEmailControllerProvider.notifier).verify(_email, code);
  }

  Future<void> _resend() async {
    _startCountdown();
    await ref.read(verifyEmailControllerProvider.notifier).request(_email);
  }

  @override
  Widget build(BuildContext context) {
    final verify = ref.watch(verifyEmailControllerProvider);
    final loading = verify.status == VerifyEmailStatus.sending ||
        verify.status == VerifyEmailStatus.verifying;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: verify.status == VerifyEmailStatus.verified
              ? _verifiedBody(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.roseGold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.mark_email_read_outlined,
                          color: AppColors.primary, size: 36),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const Text('Verify your email', style: AppTextStyles.display),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'We sent a 6-digit code to $_email. Enter it below to secure your account.',
                      style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _verify(),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headline1.copyWith(letterSpacing: 16),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••••',
                        hintStyle: AppTextStyles.headline1.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 16,
                        ),
                        filled: true,
                        fillColor: AppColors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                          borderSide: const BorderSide(color: AppColors.borderSubtle),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                          borderSide: const BorderSide(color: AppColors.borderSubtle),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.visibility_off, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('Hidden for your privacy',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                      ],
                    ),
                    if (verify.error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppSpacing.sm),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Text(verify.error!,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      label: 'Verify',
                      loading: loading,
                      onPressed:
                          loading ? null : (_code.text.length == 6 ? _verify : null),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: TextButton(
                        onPressed: _countdown > 0 ? null : _resend,
                        child: Text(
                          _countdown > 0
                              ? 'Resend code in ${_countdown}s'
                              : 'Resend code',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color:
                                _countdown > 0 ? AppColors.textMuted : AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _verifiedBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.verified_rounded, color: AppColors.success, size: 36),
        ),
        const SizedBox(height: AppSpacing.xl),
        const Text('Email verified', style: AppTextStyles.display),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your email is verified. You\'re all set.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Done',
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
