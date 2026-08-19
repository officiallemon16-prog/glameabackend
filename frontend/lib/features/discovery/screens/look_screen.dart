import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/portfolio_item.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../data/discovery_api.dart';

/// Payload for [LookScreen] passed via router `extra`.
class LookScreenData {
  const LookScreenData({required this.item, this.professionalName = ''});

  final PortfolioItem item;
  final String professionalName;
}

/// Resolves a `/looks/{id}` deep link: the item itself plus the artist name,
/// so the CTA can always open a valid professional profile.
final lookDetailProvider =
    FutureProvider.family<LookScreenData, String>((ref, id) async {
  final api = ref.watch(discoveryApiProvider);
  final item = await api.fetchPortfolioItem(id);
  var name = '';
  if (item.professionalId.isNotEmpty) {
    try {
      name = (await api.fetchProfessional(item.professionalId)).name;
    } catch (_) {
      // The look is still viewable even if the artist profile lookup fails.
      name = '';
    }
  }
  return LookScreenData(item: item, professionalName: name);
});

/// Full-screen view of a single portfolio look (spec: look detail).
/// Reached from the portfolio grid (with [data]) or a `/looks/{id}` deep link
/// (with [id], resolved by [lookDetailProvider]).
class LookScreen extends ConsumerWidget {
  const LookScreen({super.key, this.data, this.id});

  final LookScreenData? data;
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data != null) return _LookScaffold(data: data!);

    final lookup = ref.watch(lookDetailProvider(id ?? ''));
    return switch (lookup) {
      AsyncData(:final value) => _LookScaffold(data: value),
      AsyncError(:final error) => Scaffold(
          appBar: const GlameaAppBar(title: 'Look'),
          body: ErrorState(
            message: error is AppException
                ? error.message
                : 'Could not load this look.',
            onRetry: () => ref.invalidate(lookDetailProvider(id ?? '')),
          ),
        ),
      _ => const Scaffold(
          appBar: GlameaAppBar(title: 'Look'),
          body: _LookSkeleton(),
        ),
    };
  }
}

class _LookScaffold extends StatelessWidget {
  const _LookScaffold({required this.data});

  final LookScreenData data;

  void _share(BuildContext context) {
    HapticFeedback.selectionClick();
    final item = data.item;
    final artist = data.professionalName.isEmpty
        ? 'a Glamea professional'
        : data.professionalName;
    final caption = item.caption.isEmpty ? 'A look on Glamea' : item.caption;
    SharePlus.instance.share(
      ShareParams(
        text: '$caption\nBook $artist: https://glamea.app/looks/${item.id}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = data.item;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlameaAppBar(title: 'Look', actions: [
        IconButton(
          onPressed: () => _share(context),
          icon: const Icon(Icons.share_outlined, color: AppColors.primary),
        ),
      ]),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Hero(
            tag: 'look-${item.id}',
            child: AspectRatio(
              aspectRatio: AppDimens.portfolioAspectRatio,
              child: item.hasImage
                  ? AppImage(
                      url: item.imageUrl,
                      fit: BoxFit.cover,
                      placeholderIcon: Icons.photo_outlined,
                    )
                  : Container(
                      color: AppColors.softGrey,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.brush_outlined,
                        size: 56,
                        color: AppColors.roseGold.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.caption.isNotEmpty) ...[
                  Text(
                    item.caption,
                    style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        data.professionalName.isEmpty
                            ? 'Glamea professional'
                            : 'by ${data.professionalName}',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                if (item.isFeatured) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Row(
                    children: [
                      Icon(Icons.star_rounded, size: 18, color: AppColors.rating),
                      SizedBox(width: 4),
                      Text(
                        'Featured look',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Book this artist',
                  icon: Icons.calendar_month_rounded,
                  onPressed: item.professionalId.isEmpty
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          context.push(
                              AppRoutes.professionalFor(item.professionalId));
                        },
                ),
                if (item.professionalId.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        context.push(
                            AppRoutes.professionalFor(item.professionalId));
                      },
                      child: const Text('View artist profile'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer placeholder matching the look layout while a deep link resolves.
class _LookSkeleton extends StatelessWidget {
  const _LookSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        AspectRatio(
          aspectRatio: AppDimens.portfolioAspectRatio,
          child: AppSkeleton(radius: 0),
        ),
        Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 220, height: 20),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(width: 140, height: 14),
              SizedBox(height: AppSpacing.xl),
              AppSkeleton(height: 48, radius: AppSpacing.md),
            ],
          ),
        ),
      ],
    );
  }
}
