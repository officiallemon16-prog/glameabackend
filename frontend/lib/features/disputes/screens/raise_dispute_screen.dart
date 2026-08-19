import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/widgets.dart';
import '../data/dispute_api.dart';

/// Arguments for raising a dispute on a booking.
class RaiseDisputeArgs {
  const RaiseDisputeArgs({required this.bookingId, required this.professionalName});

  final String bookingId;
  final String professionalName;
}

/// Screen to raise a dispute on a booking.
class RaiseDisputeScreen extends ConsumerStatefulWidget {
  const RaiseDisputeScreen({super.key, required this.args});

  final RaiseDisputeArgs args;

  @override
  ConsumerState<RaiseDisputeScreen> createState() => _RaiseDisputeScreenState();
}

class _RaiseDisputeScreenState extends ConsumerState<RaiseDisputeScreen> {
  static const _reasons = [
    'Service not delivered',
    'Quality not as expected',
    'Charging issue',
    'Professional did not show up',
    'Other',
  ];

  final _description = TextEditingController();
  String? _reason;
  bool _submitting = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dispute = await ref.read(disputeApiProvider).raiseDispute(
            bookingId: widget.args.bookingId,
            reason: reason,
            description: _description.text.trim(),
          );
      if (!mounted) return;
      context.pushReplacement(AppRoutes.disputeDetailFor(dispute.id));
    } on AppException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Could not raise the dispute.')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Raise a dispute'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'What went wrong with your booking?',
              style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick a reason and add details. The other party will be able to see your dispute.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final reason in _reasons) ...[
              _ReasonTile(
                label: reason,
                selected: _reason == reason,
                onTap: () => setState(() => _reason = reason),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _description,
              hintText: 'Describe what happened (optional)',
              maxLines: 4,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Submit dispute',
              icon: Icons.gavel_rounded,
              loading: _submitting,
              onPressed: _reason == null || _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            border: Border.all(color: selected ? AppColors.primary : AppColors.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
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
