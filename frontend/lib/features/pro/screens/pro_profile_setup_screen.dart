import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../pro_controller.dart';

/// Creates the professional profile (POST /professionals) for a freshly
/// registered PROFESSIONAL account that has no profile yet.
class ProProfileSetupScreen extends ConsumerStatefulWidget {
  const ProProfileSetupScreen({super.key});

  @override
  ConsumerState<ProProfileSetupScreen> createState() =>
      _ProProfileSetupScreenState();
}

class _ProProfileSetupScreenState extends ConsumerState<ProProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _displayName = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _businessName.dispose();
    _displayName.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(proProfileControllerProvider.notifier).create({
        'business_name': _businessName.text.trim(),
        'display_name': _displayName.text.trim(),
        'bio': _bio.text.trim(),
        'city': _city.text.trim(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const GlameaAppBar(title: 'Set up your studio'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tell customers about your business to get started.',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _businessName,
                  hintText: 'Business name',
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _displayName,
                  hintText: 'Display name (optional)',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _city,
                  hintText: 'City (optional)',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _bio,
                  hintText: 'Short bio (optional)',
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppSpacing.sm),
                      border:
                          Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _error!,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Create studio',
                  loading: _saving,
                  onPressed: _saving ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
