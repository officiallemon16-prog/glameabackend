import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../models/category.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';

/// Maps a category name to a representative icon (fallback: sparkle).
IconData categoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('nail') || n.contains('manicure') || n.contains('pedicure')) return Icons.back_hand_outlined;
  if (n.contains('hair') || n.contains('braid') || n.contains('dread') || n.contains('extensions')) {
    return Icons.content_cut_rounded;
  }
  if (n.contains('makeup') || n.contains('face') || n.contains('skin') || n.contains('facial')) {
    return Icons.brush_rounded;
  }
  if (n.contains('lash') || n.contains('brow') || n.contains('eye')) return Icons.visibility_outlined;
  if (n.contains('spa') || n.contains('massage') || n.contains('body')) return Icons.spa_rounded;
  if (n.contains('barber') || n.contains('shave')) return Icons.face_rounded;
  return Icons.auto_awesome_rounded;
}

/// Short descriptor shown under a category image in the services carousel.
String categorySubtitle(String slug) {
  switch (slug.toLowerCase()) {
    case 'hair':
      return 'Salons & stylists';
    case 'nails':
      return 'Manicure & nail art';
    case 'lashes':
      return 'Lash artists';
    case 'brows':
      return 'Brow specialists';
    case 'makeup':
      return 'Makeup artists';
    case 'tattoos':
      return 'Permanent makeup';
    case 'spa':
      return 'Massage & facials';
    case 'barber':
      return 'Barbers & shaves';
    default:
      return 'Beauty professionals';
  }
}

/// Tappable category tile for the "Browse by category" grid.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.onTap});

  final Category category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        children: [
          if (category.hasImage)
            Expanded(
              child: AppImage(
                url: category.imageUrl,
                fit: BoxFit.cover,
                borderRadius: AppDimens.cardRadiusMobile - 2,
                placeholderIcon: categoryIcon(category.name),
              ),
            )
          else
            Expanded(
              child: Container(
                color: AppColors.roseGold.withValues(alpha: 0.14),
                alignment: Alignment.center,
                child: Icon(categoryIcon(category.name), color: AppColors.primary, size: 26),
              ),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
