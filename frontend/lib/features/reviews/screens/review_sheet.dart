import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';

/// Result of the review sheet: 1-5 rating plus optional comment.
typedef ReviewInput = ({int rating, String comment});

/// Bottom sheet that collects a star rating and comment for a completed booking.
Future<ReviewInput?> showReviewSheet(
  BuildContext context, {
  required String professionalName,
}) {
  return showModalBottomSheet<ReviewInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReviewSheet(professionalName: professionalName),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.professionalName});

  final String professionalName;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _comment = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.professionalName.isEmpty ? 'this artist' : widget.professionalName;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('How was your appointment?', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Share a rating for $name.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = i),
                    iconSize: 34,
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    icon: Icon(
                      i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: i <= _rating ? AppColors.warning : AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _comment,
            hintText: 'Tell us about your experience (optional)',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Submit review',
            icon: Icons.star_rounded,
            onPressed: () => Navigator.of(context).pop(
              (rating: _rating, comment: _comment.text.trim()),
            ),
          ),
        ],
      ),
    );
  }
}
