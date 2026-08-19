import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/location/location_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/feed_post.dart';
import '../../../shared/widgets/app_image.dart';
import '../../location/location_map_screen.dart';

/// One Instagram-style feed card: author header with a tappable location pin
/// (opens a map), swipeable image carousel, a like/save action row, then the
/// caption and category. Used by both the Home feed and My favorites.
class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    this.onToggleLike,
    this.onToggleSave,
    this.onOpenProfessional,
  });

  final FeedPost post;
  final VoidCallback? onToggleLike;
  final VoidCallback? onToggleSave;
  final VoidCallback? onOpenProfessional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PostHeader(
          post: post,
          onOpenProfessional: onOpenProfessional,
        ),
        _PostMedia(post: post),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LikeButton(
                    liked: post.likedByMe,
                    count: post.likeCount,
                    onTap: onToggleLike,
                  ),
                  _SaveButton(
                    saved: post.savedByMe,
                    onTap: onToggleSave,
                  ),
                ],
              ),
              if (post.caption.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  post.caption,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary, height: 1.45),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  if (post.categoryName.isNotEmpty)
                    _CategoryLabel(
                      label: post.categoryName,
                      onTap: () => _openCategory(context),
                    ),
                  const Spacer(),
                  Text(
                    _timeAgo(post.createdAt),
                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openCategory(BuildContext context) {
    final slug = post.categorySlug;
    if (slug.isEmpty) return;
    context.push(AppRoutes.categoryFor(slug));
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post, this.onOpenProfessional});

  final FeedPost post;
  final VoidCallback? onOpenProfessional;

  @override
  Widget build(BuildContext context) {
    final author = post.professional;
    final location = post.location.isNotEmpty ? post.location : author.city;
    final hasRating = author.rating > 0;
    final canOpenMap = author.hasCoordinates;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: InkWell(
        onTap: onOpenProfessional ??
            () => context.push(AppRoutes.professionalFor(post.professionalId)),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: Row(
          children: [
            AppAvatar(url: author.avatarUrl, name: author.name, radius: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          author.name.isEmpty ? 'Glamea professional' : author.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (author.verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 15, color: AppColors.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (canOpenMap)
                        GestureDetector(
                          onTap: () => _openMap(context),
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.only(right: 2),
                            child: Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      if (location.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        if (hasRating) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: AppColors.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                      if (hasRating) ...[
                        const Icon(Icons.star_rounded, size: 13, color: AppColors.rating),
                        const SizedBox(width: 2),
                        Text(
                          '${author.rating.toStringAsFixed(1)} (${Formatters.compact(author.reviewCount)})',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (post.sponsored)
              Container(
                margin: const EdgeInsets.only(left: AppSpacing.xs),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.roseGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Sponsored',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openMap(BuildContext context) {
    final author = post.professional;
    final location = post.location.isNotEmpty ? post.location : author.city;
    _showLocationModal(
      context,
      professionalName: author.name,
      professionalLat: author.latitude!,
      professionalLng: author.longitude!,
      address: location,
    );
  }

  static void _showLocationModal(
    BuildContext context, {
    required String professionalName,
    required double professionalLat,
    required double professionalLng,
    required String address,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LocationModal(
        professionalName: professionalName,
        professionalLat: professionalLat,
        professionalLng: professionalLng,
        address: address,
      ),
    );
  }
}

class _LocationModal extends StatefulWidget {
  const _LocationModal({
    required this.professionalName,
    required this.professionalLat,
    required this.professionalLng,
    required this.address,
  });

  final String professionalName;
  final double professionalLat;
  final double professionalLng;
  final String address;

  @override
  State<_LocationModal> createState() => _LocationModalState();
}

class _LocationModalState extends State<_LocationModal> {
  double? _distanceKm;
  bool _loading = true;

  // Average city speeds in km/h
  static const _carSpeed = 30.0;
  static const _bikeSpeed = 15.0;

  @override
  void initState() {
    super.initState();
    _calcDistance();
  }

  Future<void> _calcDistance() async {
    try {
      final service = LocationService();
      final coords = await service.getCurrentLocation();
      if (coords == null) {
        if (mounted) setState(() { _loading = false; });
        return;
      }
      final dist = service.distanceKm(
        coords.latitude, coords.longitude,
        widget.professionalLat, widget.professionalLng,
      );
      if (mounted) setState(() { _distanceKm = dist; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _eta(double speed) {
    if (_distanceKm == null) return '--';
    final hours = _distanceKm! / speed;
    final mins = (hours * 60).round();
    if (mins < 1) return '<1 min';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.professionalName.isEmpty
                            ? 'Professional location'
                            : widget.professionalName,
                        style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
                      ),
                      if (widget.address.isNotEmpty)
                        Text(
                          widget.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              )
            else if (_distanceKm != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.straighten_rounded, size: 18, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${_distanceKm!.toStringAsFixed(1)} km away',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1, color: AppColors.borderSubtle),
                    const SizedBox(height: AppSpacing.sm),
                    _EtaRow(icon: '🚗', label: 'By car', eta: _eta(_carSpeed)),
                    const SizedBox(height: AppSpacing.xs),
                    _EtaRow(icon: '🏍️', label: 'By bike', eta: _eta(_bikeSpeed)),
                  ],
                ),
              ),
            ] else
              Text(
                'Could not calculate distance.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(
                        AppRoutes.location,
                        extra: LocationMapArgs(
                          latitude: widget.professionalLat,
                          longitude: widget.professionalLng,
                          title: widget.professionalName,
                          subtitle: widget.address,
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('View on map'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(
                        'https://www.google.com/maps/dir/?api=1&destination=${widget.professionalLat},${widget.professionalLng}',
                      );
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    icon: const Icon(Icons.navigation_outlined, size: 18, color: Colors.white),
                    label: const Text('Directions', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EtaRow extends StatelessWidget {
  const _EtaRow({required this.icon, required this.label, required this.eta});

  final String icon;
  final String label;
  final String eta;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ),
        Text(
          eta,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Like/save heart with the live count. Tapping toggles the favorite; the
/// icon springs in with a pop so the state change feels alive.
class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.liked, required this.count, this.onTap});

  final bool liked;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = liked ? AppColors.primary : AppColors.textSecondary;
    final label = count > 0
        ? Formatters.compact(count)
        : (liked ? 'Liked' : 'Like');
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(20),
      child: Semantics(
        button: true,
        toggled: liked,
        label: liked ? 'Unlike' : 'Like',
        child: TweenAnimationBuilder<double>(
          key: ValueKey('like-$liked'),
          tween: Tween(begin: liked ? 0.6 : 1.0, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.elasticOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
        ),
      ),
    );
  }
}

/// Bookmark toggle on the far right of the action row. Saving a look lets the
/// user find it again later under Favorites -> Saved.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, this.onTap});

  final bool saved;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = saved ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(20),
      child: Semantics(
        button: true,
        toggled: saved,
        label: saved ? 'Remove from saved' : 'Save',
        child: TweenAnimationBuilder<double>(
          key: ValueKey('save-$saved'),
          tween: Tween(begin: saved ? 0.6 : 1.0, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.elasticOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  saved ? 'Saved' : 'Save',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
        ),
      ),
    );
  }
}

/// Swipeable image carousel with page dots (1:1, like a reels card).
class _PostMedia extends StatefulWidget {
  const _PostMedia({required this.post});

  final FeedPost post;

  @override
  State<_PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<_PostMedia> {
  int _page = 0;
  Timer? _autoTimer;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _startAutoTimer();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    if (widget.post.images.length > 1) {
      _autoTimer = Timer.periodic(const Duration(seconds: 7), (_) {
        if (!mounted || !_pageController.hasClients) return;
        final next = (_page + 1) % widget.post.images.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  void _pauseAutoTimer() {
    _autoTimer?.cancel();
  }

  void _resumeAutoTimer() {
    _startAutoTimer();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.post.images;
    if (images.isEmpty) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          color: AppColors.softGrey,
          alignment: Alignment.center,
          child: Icon(
            Icons.brush_outlined,
            size: 48,
            color: AppColors.roseGold.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (i) => setState(() {
              _page = i;
              _pauseAutoTimer();
              _resumeAutoTimer();
            }),
            itemBuilder: (context, i) => AppImage(
              url: images[i].url,
              fit: BoxFit.cover,
              placeholderIcon: Icons.photo_outlined,
            ),
          ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.primary : Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime? value) {
  if (value == null) return '';
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return Formatters.relativeDate(value);
}
