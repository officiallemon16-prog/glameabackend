import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../models/beauty_service.dart';
import '../../../models/portfolio_item.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../../media/media_controller.dart';
import '../../media/media_picker_field.dart';
import '../pro_controller.dart';

/// Professional portfolio: gallery of "looks" with add/delete.
class ProPortfolioTab extends ConsumerWidget {
  const ProPortfolioTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proPortfolioControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                const Expanded(child: Text('Portfolio', style: AppTextStyles.headline2)),
                AppButton(
                  label: 'Add look',
                  icon: Icons.add_rounded,
                  expanded: false,
                  onPressed: () => showGlameaSheet(context, child: const PortfolioSheet()),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proPortfolioControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildGrid(context, ref, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, WidgetRef ref, ProListState<PortfolioItem> state) {
    if (state.status == ProListStatus.loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonGrid(count: 6)],
      );
    }
    if (state.status == ProListStatus.error) {
      return ListView(
        children: [
          ErrorState(
            message: state.error ?? 'Could not load portfolio.',
            onRetry: () => ref.read(proPortfolioControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No looks yet',
            message: 'Add photos of your work to help customers choose you.',
          ),
        ],
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 3 / 4,
      ),
      itemCount: state.items.length,
      itemBuilder: (_, i) => _PortfolioCard(
        item: state.items[i],
        onDelete: () => _confirmDelete(context, ref, state.items[i]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, PortfolioItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this look?'),
        content: Text(item.caption.isEmpty ? 'This portfolio item will be removed.' : '"${item.caption}" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(proPortfolioControllerProvider.notifier).remove(item.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Look removed')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

class _PortfolioCard extends StatelessWidget {
  const _PortfolioCard({required this.item, required this.onDelete});
  final PortfolioItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.hasImage)
            AppImage(url: item.imageUrl, fit: BoxFit.cover)
          else
            Container(color: AppColors.softGrey, child: const Icon(Icons.photo_outlined, color: AppColors.textSecondary, size: 40)),
          if (item.isFeatured)
            const Positioned(
              top: 8,
              left: 8,
              child: _Tag(label: 'Featured'),
            ),
          if (item.isVerification)
            const Positioned(
              top: 8,
              right: 8,
              child: _Tag(label: 'Verified'),
            ),
          if (item.caption.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                color: Colors.black.withValues(alpha: 0.45),
                child: Text(item.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: Colors.white)),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: onDelete,
              style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35), foregroundColor: Colors.white),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}

class PortfolioSheet extends ConsumerStatefulWidget {
  const PortfolioSheet({super.key});

  @override
  ConsumerState<PortfolioSheet> createState() => _PortfolioSheetState();
}

class _PortfolioSheetState extends ConsumerState<PortfolioSheet> {
  final _caption = TextEditingController();
  String? _serviceId;
  bool _featured = false;
  bool _saving = false;
  XFile? _imageFile;
  Uint8List? _imageBytes;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

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
    final image = _imageFile;
    if (image == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Choose a photo first')));
      return;
    }
    setState(() => _saving = true);
    try {
      final asset = await ref
          .read(mediaUploadControllerProvider.notifier)
          .uploadImage(image, folder: 'glamea/portfolio');
      await ref.read(proPortfolioControllerProvider.notifier).create({
        'media_asset_id': asset.id,
        'caption': _caption.text.trim(),
        'service_id': _serviceId,
        'is_featured': _featured,
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Look added')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesState = ref.watch(proServicesControllerProvider);
    final services = servicesState.status == ProListStatus.ready ? servicesState.items : <BeautyService>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Add portfolio look', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Upload a photo of this look. It will be shown on your public profile.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          MediaPickerField(
            previewBytes: _imageBytes,
            label: 'Choose a photo',
            onPicked: _pick,
            onClear: () => setState(() {
              _imageFile = null;
              _imageBytes = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _caption,
            decoration: const InputDecoration(labelText: 'Caption'),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _serviceId,
            decoration: const InputDecoration(labelText: 'Service (optional)'),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('No service')),
              for (final s in services) DropdownMenuItem<String>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _serviceId = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            value: _featured,
            onChanged: (v) => setState(() => _featured = v),
            title: const Text('Feature this look'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Add look', onPressed: _saving ? null : _save, loading: _saving),
        ],
      ),
    );
  }
}
