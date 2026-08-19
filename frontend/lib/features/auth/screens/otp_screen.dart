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

/// Route: /otp. Phone verification with a 6-digit code (spec section 7/17).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  Timer? _resendTimer;
  int _countdown = 0;

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
    ref.read(authControllerProvider.notifier).verifyOtp(code);
  }

  Future<void> _resend() async {
    _startCountdown();
    await ref.read(authControllerProvider.notifier).resendOtp();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.status == AuthStatus.authenticating;
    final phone = auth.pendingPhone ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.md),
              IconButton(
                onPressed: () {
                  ref
                      .read(authControllerProvider.notifier)
                      .cancelPhoneVerification();
                  context.pop();
                },
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
                child: const Icon(Icons.sms_outlined, color: AppColors.primary, size: 36),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Verify your phone', style: AppTextStyles.display),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'We sent a 6-digit code to $phone. Enter it below to secure your account.',
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
                  Text('Hidden for your privacy', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                ],
              ),
              if (auth.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(auth.error!, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Verify',
                loading: loading,
                onPressed: loading ? null : (_code.text.length == 6 ? _verify : null),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: _countdown > 0 ? null : _resend,
                  child: Text(
                    _countdown > 0 ? 'Resend code in ${_countdown}s' : 'Resend code',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: _countdown > 0 ? AppColors.textMuted : AppColors.primary,
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
}
