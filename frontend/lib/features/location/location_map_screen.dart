import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/app_button.dart';

/// Arguments for the location map screen (a professional's pin).
class LocationMapArgs {
  const LocationMapArgs({
    required this.latitude,
    required this.longitude,
    this.title,
    this.subtitle,
  });

  final double latitude;
  final double longitude;
  final String? title;
  final String? subtitle;
}

/// Full-screen map with a pin at the professional's location plus a quick
/// "Get directions" action that opens the device's maps app (Uber-style).
class LocationMapScreen extends StatelessWidget {
  const LocationMapScreen({super.key, required this.args});

  final LocationMapArgs args;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(args.latitude, args.longitude);
    final showCard = args.subtitle?.isNotEmpty == true ||
        args.title?.isNotEmpty == true ||
        (args.latitude != 0 && args.longitude != 0);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlameaAppBar(title: args.title ?? 'Location'),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.glamea.glamea',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 46,
                      height: 46,
                      child: const Icon(
                        Icons.location_pin,
                        color: AppColors.primary,
                        size: 46,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showCard)
            Material(
              color: AppColors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined,
                              color: AppColors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (args.title?.isNotEmpty == true)
                                  Text(
                                    args.title!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                if (args.subtitle?.isNotEmpty == true) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    args.subtitle!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (args.latitude != 0 || args.longitude != 0) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: 'Get directions',
                          icon: Icons.navigation_outlined,
                          variant: AppButtonVariant.outline,
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _openDirections();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openDirections() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${args.latitude},${args.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
