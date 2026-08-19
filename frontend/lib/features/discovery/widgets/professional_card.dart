import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/professional.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';

/// Vertical card for the 2-column results grid.
class ProfessionalGridCard extends StatelessWidget {
  const ProfessionalGridCard({super.key, required this.professional, this.onTap});

  final Professional professional;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(professional: professional),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          professional.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (professional.verified) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        const Icon(Icons.verified_rounded, size: 16, color: AppColors.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 16, color: AppColors.rating),
                      const SizedBox(width: 2),
                      Text(
                        '${professional.rating.toStringAsFixed(1)} (${Formatters.compact(professional.reviewCount)})',
                        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (professional.location.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            professional.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.professional});

  final Professional professional;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.cardRadiusMobile)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.roseGoldSoft, AppColors.roseGold],
        ),
      ),
      alignment: Alignment.center,
      child: AppAvatar(name: professional.name, radius: 26),
    );
  }
}

/// Horizontal row card for home "Top rated" strip and list rows.
class ProfessionalTile extends StatelessWidget {
  const ProfessionalTile({super.key, required this.professional, this.onTap, this.trailing});

  final Professional professional;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          AppAvatar(name: professional.name, radius: 26),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        professional.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (professional.verified) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      const Icon(Icons.verified_rounded, size: 15, color: AppColors.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 15, color: AppColors.rating),
                    const SizedBox(width: 2),
                    Text(
                      '${professional.rating.toStringAsFixed(1)} \u00B7 ${Formatters.compact(professional.reviewCount)} reviews',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                if (professional.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          professional.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}
