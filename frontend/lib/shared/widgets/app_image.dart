import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.photo_outlined,
  });

  final String url;
  final BoxFit fit;
  final double? borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _FallbackState(icon: placeholderIcon);
    }

    Widget image;

    if (kIsWeb) {
      image = Image.network(
        url,
        fit: fit,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _FallbackState(icon: placeholderIcon);
        },
        errorBuilder: (context, error, stackTrace) {
          return _FallbackState(icon: placeholderIcon);
        },
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        memCacheWidth: 600,
        placeholder: (_, __) => _ShimmerPlaceholder(icon: placeholderIcon),
        errorWidget: (_, __, ___) => _FallbackState(icon: placeholderIcon),
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 100),
      );
    }

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius!),
        child: image,
      );
    }

    return image;
  }
}

class _ShimmerPlaceholder extends StatelessWidget {
  const _ShimmerPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        color: AppColors.softGrey,
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: AppColors.roseGold.withValues(alpha: 0.4),
          size: 28,
        ),
      ),
    );
  }
}

class _FallbackState extends StatelessWidget {
  const _FallbackState({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.softGrey,
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: AppColors.roseGold.withValues(alpha: 0.6),
        size: 28,
      ),
    );
  }
}

/// Circle avatar with initials fallback.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.url, required this.name, this.radius = 22});

  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.softGrey,
        backgroundImage: kIsWeb
            ? NetworkImage(url!)
            : CachedNetworkImageProvider(url!),
        onBackgroundImageError: (_, __) {},
      );
    }
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.roseGold.withValues(alpha: 0.25),
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

/// Star rating row (spec: half-star supported).
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, this.rating = 0, this.size = 16, this.showValue = false});

  final double rating;
  final double size;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++) ...[
          Icon(
            i <= rating.floor()
                ? Icons.star_rounded
                : (rating - i + 1 >= 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: AppColors.rating,
          ),
          if (i < 5) const SizedBox(width: 2),
        ],
        if (showValue) ...[
          const SizedBox(width: AppSpacing.xxs),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: size * 0.9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
