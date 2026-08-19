import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/location/location_service.dart';
import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/app_button.dart';

class LocationPickerResult {
  const LocationPickerResult({required this.latitude, required this.longitude, this.address = ''});
  final double latitude;
  final double longitude;
  final String address;
}

/// Full-screen map with a draggable pin that lets the user pick and adjust
/// their location before sharing it in chat.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  LatLng? _pinPosition;
  bool _loading = true;
  String? _error;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    setState(() { _loading = true; _error = null; _permanentlyDenied = false; });
    try {
      final (result, coords) = await LocationService().requestAndGet();
      if (!mounted) return;

      switch (result) {
        case PermissionResult.granted:
          setState(() {
            _pinPosition = LatLng(coords!.latitude, coords.longitude);
            _loading = false;
          });
        case PermissionResult.deniedForever:
          setState(() {
            _error = 'Location permission is required to share your location.';
            _permanentlyDenied = true;
            _loading = false;
          });
        case PermissionResult.serviceDisabled:
          setState(() {
            _error = 'Location services are disabled. Please enable them in settings.';
            _permanentlyDenied = true;
            _loading = false;
          });
        default:
          setState(() {
            _error = 'Location permission is required to share your location.';
            _loading = false;
          });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not get your location. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Pick location'),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: AppSpacing.md),
                  Text('Getting your location...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_rounded, size: 56, color: AppColors.error),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_permanentlyDenied)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await LocationService.showPermissionDialog(
                                  context,
                                  title: 'Location access needed',
                                  message:
                                      'Glamea needs your location to share it in chat. Please enable location access in your device settings.',
                                );
                                await _initLocation();
                              },
                              icon: const Icon(Icons.settings, size: 18),
                              label: const Text('Open settings'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          )
                        else
                          AppButton(
                            label: 'Try again',
                            icon: Icons.refresh_rounded,
                            onPressed: () {
                              setState(() { _loading = true; _error = null; });
                              _initLocation();
                            },
                          ),
                      ],
                    ),
                  ),
                )
              : _buildMap(),
    );
  }

  Widget _buildMap() {
    final pin = _pinPosition ?? const LatLng(6.5244, 3.3792); // Lagos fallback
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: pin,
            initialZoom: 15,
            onPositionChanged: (position, hasGesture) {
              if (hasGesture) {
                setState(() => _pinPosition = position.center);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.glamea.glamea',
            ),
          ],
        ),
        // Center pin indicator
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Icon(Icons.location_pin, size: 48, color: AppColors.primary),
          ),
        ),
        // Bottom bar with send button
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black12)],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Drag the map to adjust the pin location',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Share this location',
                    icon: Icons.send_rounded,
                    onPressed: _pinPosition != null
                        ? () => Navigator.of(context).pop(
                              LocationPickerResult(
                                latitude: _pinPosition!.latitude,
                                longitude: _pinPosition!.longitude,
                              ),
                            )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
