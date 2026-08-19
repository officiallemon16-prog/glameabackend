import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/verification.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../../media/media_controller.dart';
import '../../media/media_picker_field.dart';
import '../pro_controller.dart';

/// Professional verification: document status + submission.
class ProVerificationTab extends ConsumerWidget {
  const ProVerificationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proVerificationControllerProvider);
    final profileState = ref.watch(proProfileControllerProvider);
    final profileStatus = profileState.profile?.verificationStatus ?? 'UNVERIFIED';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Text('Verification', style: AppTextStyles.headline2),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proVerificationControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(context, ref, state, profileStatus),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, ProListState<VerificationDocument> state, String profileStatus) {
    if (state.status == ProListStatus.loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonList(count: 3)],
      );
    }
    if (state.status == ProListStatus.error) {
      return ListView(
        children: [
          ErrorState(
            message: state.error ?? 'Could not load verification documents.',
            onRetry: () => ref.read(proVerificationControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      children: [
        _StatusBanner(status: profileStatus),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Expanded(child: Text('Documents', style: AppTextStyles.title)),
            IconButton(
              onPressed: () => showGlameaSheet(context, child: const VerificationSheet()),
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              tooltip: 'Submit document',
            ),
          ],
        ),
        if (state.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'No documents submitted yet. Upload your ID, professional certificate or license to get verified.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          )
        else
          for (final doc in state.items) _DocumentCard(document: doc),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'VERIFIED' => (AppColors.success, 'You are verified'),
      'REJECTED' => (AppColors.error, 'Verification rejected'),
      'PENDING' || 'REVIEWING' => (AppColors.warning, 'Verification in review'),
      _ => (AppColors.textSecondary, 'Not verified yet'),
    };
    return AppCard(
      color: color.withValues(alpha: 0.06),
      child: Row(
        children: [
          Icon(status == 'VERIFIED' ? Icons.verified_rounded : Icons.verified_outlined, color: color, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.title.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(
                  status == 'VERIFIED'
                      ? 'Your badge is live on your profile.'
                      : 'Submit your documents to get the verified badge.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});
  final VerificationDocument document;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (document.status) {
      'APPROVED' => (AppColors.success, 'Approved'),
      'REJECTED' => (AppColors.error, 'Rejected'),
      _ => (AppColors.warning, 'Pending'),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  document.documentType.replaceAll('_', ' ').toUpperCase(),
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Stage: ${document.stageLabel}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          if (document.submittedAt != null)
            Text('Submitted ${Formatters.date(document.submittedAt)}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          if (document.isRejected && document.reviewNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('Note: ${document.reviewNote}', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
            ),
        ],
      ),
    );
  }
}

class VerificationSheet extends ConsumerStatefulWidget {
  const VerificationSheet({super.key});

  @override
  ConsumerState<VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends ConsumerState<VerificationSheet> {
  static const _types = ['NATIONAL_ID', 'DRIVER_LICENSE', 'PASSPORT', 'PROFESSIONAL_CERTIFICATE', 'BUSINESS_REGISTRATION'];
  static const _stages = ['IDENTITY', 'BUSINESS', 'LOCATION', 'CERTIFICATE'];

  String? _type;
  String _stage = _stages.first;
  bool _saving = false;
  XFile? _imageFile;
  Uint8List? _imageBytes;

  Future<void> _pick(XFile file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageFile = file;
      _imageBytes = bytes;
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (_type == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Choose a document type')));
      return;
    }
    final image = _imageFile;
    if (image == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Choose a document photo first')));
      return;
    }
    setState(() => _saving = true);
    try {
      final asset = await ref
          .read(mediaUploadControllerProvider.notifier)
          .uploadImage(image, folder: 'glamea/verification');
      await ref.read(proVerificationControllerProvider.notifier).submit({
        'stage': _stage,
        'document_type': _type,
        'media_asset_id': asset.id,
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Document submitted for review')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Submit verification document', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Upload a clear photo of your ID, certificate or license.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          MediaPickerField(
            previewBytes: _imageBytes,
            label: 'Choose a document photo',
            onPicked: _pick,
            onClear: () => setState(() {
              _imageFile = null;
              _imageBytes = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Document type'),
            items: [
              for (final t in _types)
                DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ').toLowerCase())),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _stage,
            decoration: const InputDecoration(labelText: 'Verification stage'),
            items: [
              for (final s in _stages)
                DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' ').toLowerCase())),
            ],
            onChanged: (v) => setState(() => _stage = v!),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Submit', onPressed: _saving ? null : _save, loading: _saving),
        ],
      ),
    );
  }
}
