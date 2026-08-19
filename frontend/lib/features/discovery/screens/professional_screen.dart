import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/beauty_service.dart';
import '../../../models/portfolio_item.dart';
import '../../../models/professional.dart';
import '../../../models/review.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../../booking/booking_controller.dart';
import '../data/discovery_api.dart';
import '../widgets/review_tile.dart';
import '../widgets/service_tile.dart';
import 'look_screen.dart';

/// Professional detail: profile, stats, bio and bookable services.
class ProfessionalScreen extends ConsumerWidget {
  const ProfessionalScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(professionalProfileProvider(id));
    final professional = async.valueOrNull?.professional;
    final services = async.valueOrNull?.services ?? const <BeautyService>[];
    final bookable = services.where((s) => s.isActive).toList();

    return Scaffold(
      appBar: GlameaAppBar(title: professional?.name ?? 'Professional'),
      body: switch (async) {
        AsyncData(:final value) => _ProfessionalBody(profile: value),
        AsyncError(:final error) => ErrorState(
            message: error is AppException
                ? error.message
                : 'Could not load this professional.',
            onRetry: () => ref.invalidate(professionalProfileProvider(id)),
          ),
        _ => const _ProfessionalSkeleton(),
      },
      bottomNavigationBar: professional == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
                child: AppButton(
                  label: bookable.isEmpty ? 'No bookable services' : 'Book now',
                  icon: Icons.calendar_month_rounded,
                  onPressed: bookable.isEmpty
                      ? null
                      : () => _startBooking(context,
                          professional: professional, services: bookable),
                ),
              ),
            ),
    );
  }

  void _startBooking(
    BuildContext context, {
    required Professional professional,
    required List<BeautyService> services,
  }) {
    if (services.length == 1) {
      context.push(
        AppRoutes.newBooking,
        extra: BookingFlowArgs(
            service: services.first, professional: professional),
      );
      return;
    }
    showServicePicker(
      context,
      professional: professional,
      services: services,
    );
  }
}

/// Bottom sheet to pick a service before booking.
Future<void> showServicePicker(
  BuildContext context, {
  required Professional professional,
  required List<BeautyService> services,
}) async {
  BeautyService? selected;
  await showGlameaSheet<void>(
    context,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeader(title: 'Choose a service'),
          const SizedBox(height: AppSpacing.xs),
          for (final service in services) ...[
            ServiceTile(
              service: service,
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
              onTap: () {
                selected = service;
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    ),
  );
  if (selected != null && context.mounted) {
    await context.push(
      AppRoutes.newBooking,
      extra: BookingFlowArgs(service: selected!, professional: professional),
    );
  }
}

/// Professional + bookable services + portfolio + reviews.
class ProfessionalProfile {
  const ProfessionalProfile({
    required this.professional,
    required this.services,
    this.portfolio = const [],
    this.reviews = const [],
  });

  final Professional professional;
  final List<BeautyService> services;
  final List<PortfolioItem> portfolio;
  final List<Review> reviews;
}

final professionalProfileProvider =
    FutureProvider.family<ProfessionalProfile, String>(
  (ref, id) async {
    final api = ref.watch(discoveryApiProvider);
    final (professional, services, portfolio, reviews) = await (
      api.fetchProfessional(id),
      api.fetchServices(professionalId: id),
      api.fetchPortfolio(id),
      api.fetchReviews(id),
    ).wait;
    return ProfessionalProfile(
      professional: professional,
      services: services,
      portfolio: portfolio,
      reviews: reviews,
    );
  },
);

class _ProfessionalBody extends StatelessWidget {
  const _ProfessionalBody({required this.profile});

  final ProfessionalProfile profile;

  @override
  Widget build(BuildContext context) {
    final professional = profile.professional;
    final services = profile.services.where((s) => s.isActive).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _Header(professional: professional),
        const SizedBox(height: AppSpacing.sm),
        _StatsRow(professional: professional),
        const SizedBox(height: AppSpacing.md),
        if (professional.bio.isNotEmpty) ...[
          Text(
            'About',
            style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            professional.bio,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _PortfolioSection(
          professional: professional,
          items: profile.portfolio,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Services',
                style:
                    AppTextStyles.title.copyWith(color: AppColors.textPrimary),
              ),
            ),
            Text(
              '${services.length} available',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (services.isEmpty)
          const EmptyState(
            icon: Icons.spa_outlined,
            title: 'No services yet',
            message: 'This professional has not added services yet.',
          )
        else
          for (final service in services) ...[
            ServiceTile(
              service: service,
              onTap: () => context.push(
                AppRoutes.newBooking,
                extra: BookingFlowArgs(
                  service: service,
                  professional: professional,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        const SizedBox(height: AppSpacing.lg),
        _ReviewsSection(professional: professional, reviews: profile.reviews),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Portfolio "looks" grid. Tapping an item opens the full-screen look view.
class _PortfolioSection extends StatelessWidget {
  const _PortfolioSection({required this.professional, required this.items});

  final Professional professional;
  final List<PortfolioItem> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((i) => i.isVerification != true).toList();
    final featuredFirst = [...visible]..sort((a, b) {
        if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
        return a.displayOrder.compareTo(b.displayOrder);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Portfolio',
                style:
                    AppTextStyles.title.copyWith(color: AppColors.textPrimary),
              ),
            ),
            Text(
              '${featuredFirst.length} ${featuredFirst.length == 1 ? 'look' : 'looks'}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (featuredFirst.isEmpty)
          const EmptyState(
            icon: Icons.photo_library_outlined,
            title: 'No looks yet',
            message: 'This artist has not shared their portfolio yet.',
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 4 / 5,
            ),
            itemCount: featuredFirst.length,
            itemBuilder: (context, index) {
              final item = featuredFirst[index];
              return _PortfolioTile(
                item: item,
                professionalName: professional.name,
                onTap: () => context.push(
                  AppRoutes.lookFor(item.id),
                  extra: LookScreenData(
                    item: item,
                    professionalName: professional.name,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({
    required this.item,
    required this.professionalName,
    required this.onTap,
  });

  final PortfolioItem item;
  final String professionalName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'look-${item.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.cardRadiusMobile),
          child: Stack(
            fit: StackFit.expand,
            children: [
              item.hasImage
                  ? AppImage(
                      url: item.imageUrl,
                      fit: BoxFit.cover,
                      placeholderIcon: Icons.photo_outlined)
                  : Container(
                      color: AppColors.softGrey,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.brush_outlined,
                        size: 32,
                        color: AppColors.roseGold.withValues(alpha: 0.6),
                      ),
                    ),
              if (item.isFeatured)
                const Positioned(
                  top: AppSpacing.xs,
                  left: AppSpacing.xs,
                  child: _Badge(label: 'Featured'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Reviews list with rating summary.
class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.professional, required this.reviews});

  final Professional professional;
  final List<Review> reviews;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reviews',
                style:
                    AppTextStyles.title.copyWith(color: AppColors.textPrimary),
              ),
            ),
            Text(
              professional.reviewCount > 0
                  ? '${Formatters.compact(professional.reviewCount)} total'
                  : 'No reviews yet',
              style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (reviews.isEmpty)
          const EmptyState(
            icon: Icons.reviews_outlined,
            title: 'No reviews yet',
            message:
                'Be the first to review this professional after your booking.',
          )
        else
          for (final review in reviews) ...[
            ReviewTile(review: review),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.professional});

  final Professional professional;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAvatar(name: professional.name, radius: 34),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      professional.name,
                      style: AppTextStyles.headline2,
                    ),
                  ),
                  if (professional.verified) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.verified_rounded,
                        size: 22, color: AppColors.primary),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              RatingStars(
                  rating: professional.rating, size: 16, showValue: true),
              const SizedBox(height: 2),
              Text(
                '${Formatters.compact(professional.reviewCount)} reviews',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
              if (professional.location.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        professional.location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              if (professional.homeServiceEnabled) ...[
                const SizedBox(height: AppSpacing.xs),
                const StatusBadge(
                    label: 'Home service available', color: AppColors.success),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.professional});

  final Professional professional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stat(
          value: professional.rating.toStringAsFixed(1),
          label: 'Rating',
        ),
        _divider(),
        _stat(
          value: Formatters.compact(professional.bookingCount),
          label: 'Bookings',
        ),
        _divider(),
        _stat(
          value: '${(professional.completionRate * 100).round()}%',
          label: 'Completion',
        ),
        _divider(),
        _stat(
          value: professional.experienceYears != null
              ? '${professional.experienceYears} yrs'
              : 'New',
          label: 'Experience',
        ),
      ],
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 32, color: AppColors.borderSubtle);

  Widget _stat({required String value, required String label}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style:
                  AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// Shimmer placeholder matching the profile layout (Airbnb-style): header,
/// stats row, bio, portfolio grid and a services list.
class _ProfessionalSkeleton extends StatelessWidget {
  const _ProfessionalSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton(width: 68, height: 68, radius: 34),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 180, height: 22),
                  SizedBox(height: AppSpacing.xs),
                  AppSkeleton(width: 120, height: 14),
                  SizedBox(height: AppSpacing.xs),
                  AppSkeleton(width: 150, height: 12),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppSkeleton(width: 48, height: 18),
            AppSkeleton(width: 48, height: 18),
            AppSkeleton(width: 48, height: 18),
            AppSkeleton(width: 48, height: 18),
          ],
        ),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(width: 120, height: 18),
        SizedBox(height: AppSpacing.xs),
        AppSkeleton(height: 12),
        SizedBox(height: 4),
        AppSkeleton(height: 12),
        SizedBox(height: AppSpacing.lg),
        AppSkeleton(width: 120, height: 18),
        SizedBox(height: AppSpacing.sm),
        SkeletonGrid(count: 4),
        SizedBox(height: AppSpacing.lg),
        SkeletonList(count: 3),
      ],
    );
  }
}
