import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../media/media_controller.dart';

/// Tappable image field: opens the gallery, previews the picked image and
/// lets the user remove it. The picked [XFile] is handed back via [onPicked].
class MediaPickerField extends ConsumerWidget {
  const MediaPickerField({
    super.key,
    this.previewBytes,
    this.label = 'Add photo',
    required this.onPicked,
    required this.onClear,
  });

  final Uint8List? previewBytes;
  final String label;
  final ValueChanged<XFile> onPicked;
  final VoidCallback onClear;

  Future<void> _pick(WidgetRef ref) async {
    final picker = ref.read(imagePickerProvider);
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (file != null) onPicked(file);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = previewBytes;
    return InkWell(
      onTap: () => _pick(ref),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 200,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSubtle, width: 1.5),
        ),
        child: bytes == null
            ? Container(
                color: AppColors.softGrey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 40,
                      color: AppColors.roseGold.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      label,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'JPG, PNG, WEBP, GIF',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onClear,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
