import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

class UserCoordinates {
  const UserCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Describes what happened after a location-permission request.
enum PermissionResult {
  /// Permission granted and position obtained.
  granted,

  /// User denied the permission request.
  denied,

  /// User chose "Don't ask again" (iOS: denied permanently).
  deniedForever,

  /// The device GPS / location service is off.
  serviceDisabled,

  /// An unexpected error occurred.
  error,
}

/// Wraps geolocator with a single entry-point that callers use instead of
/// calling `Geolocator.checkPermission` / `requestPermission` directly.
/// This keeps permission UX consistent across the app.
class LocationService {
  /// Requests location permission and, if granted, returns the current
  /// position. Callers should switch on the returned [PermissionResult] to
  /// show the appropriate UI (map, settings dialog, snackbar, etc.).
  Future<(PermissionResult, UserCoordinates?)> requestAndGet() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return (PermissionResult.serviceDisabled, null);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return (PermissionResult.denied, null);
      }
      if (permission == LocationPermission.deniedForever) {
        return (PermissionResult.deniedForever, null);
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return (
        PermissionResult.granted,
        UserCoordinates(latitude: pos.latitude, longitude: pos.longitude),
      );
    } catch (_) {
      return (PermissionResult.error, null);
    }
  }

  /// Checks whether we already have location permission without requesting it.
  Future<bool> hasPermission() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Gets the current position without requesting permission first.
  /// Returns `null` if permission is not granted or location is off.
  Future<UserCoordinates?> getCurrentLocation() async {
    if (!await hasPermission()) return null;
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return UserCoordinates(latitude: pos.latitude, longitude: pos.longitude);
  }

  double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  // ---------------------------------------------------------------------------
  // Static permission-dialog helpers
  // ---------------------------------------------------------------------------

  /// Shows a bottom-sheet dialog explaining why the permission is needed
  /// with a button to open app settings. Returns when the dialog is dismissed.
  static Future<void> showPermissionDialog(BuildContext context, {
    required String title,
    required String message,
  }) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Icon(Icons.location_off_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Geolocator.openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Not now',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convenience: requests location and handles the "denied forever" case
  /// by showing the settings dialog. Returns coordinates on success, null on
  /// failure (after showing appropriate UI).
  static Future<UserCoordinates?> requestWithUI(BuildContext context) async {
    final service = LocationService();
    final (result, coords) = await service.requestAndGet();
    if (result == PermissionResult.granted && coords != null) {
      return coords;
    }
    if (context.mounted) {
      switch (result) {
        case PermissionResult.deniedForever:
          await showPermissionDialog(
            context,
            title: 'Location access needed',
            message:
                'Glamea needs your location to show distances and help you find nearby professionals. Please enable location access in your device settings.',
          );
        case PermissionResult.serviceDisabled:
          await showPermissionDialog(
            context,
            title: 'Location services off',
            message:
                'Your device location services are turned off. Please enable them in settings to use location features.',
          );
        case PermissionResult.denied:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        default:
          break;
      }
    }
    return null;
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
