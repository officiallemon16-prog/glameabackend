import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/google_auth/google_auth.dart';
import '../../../shared/widgets/widgets.dart';
import '../auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _googleLoading = false;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(authControllerProvider.notifier).clearError();
    if (!_formKey.currentState!.validate()) return;
    ref.read(authControllerProvider.notifier).login(
          _identifier.text.trim(),
          _password.text,
        );
  }

  Future<void> _googleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      final token = await GoogleAuthWeb.signIn();
      if (token == null) {
        if (mounted) {
          setState(() => _googleLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google sign-in was cancelled or the popup was blocked. '
                'Try allowing popups for this site, or check that '
                'your server IP is listed in Google Cloud Console.',
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;

      final payload = GoogleAuthWeb.decodeJwtPayload(token);
      await ref.read(authControllerProvider.notifier).socialLogin(
            provider: 'google',
            idToken: token,
            email: payload?['email'] as String?,
            displayName: payload?['name'] as String?,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.status == AuthStatus.authenticating;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                IconButton(
                  onPressed: () => context.go(AppRoutes.onboarding),
                  icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('Welcome back', style: AppTextStyles.headline1),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Log in to continue your beauty journey.',
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _googleLoading ? null : _googleSignIn,
                    icon: _googleLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.g_mobiledata, color: Colors.black, size: 28),
                    label: const Text('Continue with Google'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const _DividerWithText(label: 'or log in with email'),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _identifier,
                  hintText: 'Email or phone number',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email, AutofillHints.telephoneNumber],
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter your email or phone' : null,
                  prefixIcon: const Icon(Icons.person_outline, color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _password,
                  hintText: 'Password',
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => v == null || v.isEmpty ? 'Enter your password' : null,
                  onSubmitted: (_) => _submit(),
                  prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textMuted),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                  ),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ErrorBanner(message: auth.error!),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppButton(label: 'Log in', loading: loading, onPressed: loading ? null : _submit),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                    ),
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.register),
                      child: Text(
                        'Create one',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _DividerWithText extends StatelessWidget {
  const _DividerWithText({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
        ),
        const Expanded(child: Divider(color: AppColors.borderSubtle)),
      ],
    );
  }
}
