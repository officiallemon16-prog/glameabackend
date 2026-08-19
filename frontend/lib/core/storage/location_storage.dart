import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User's chosen location (manual city or GPS), stored locally.
/// Used to prefill search/discovery filters in Phase 3.
class SavedLocation {
  const SavedLocation({required this.city, this.latitude, this.longitude});

  final String city;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;
}

class LocationStorage {
  static const _kCity = 'location_city';
  static const _kLat = 'location_lat';
  static const _kLng = 'location_lng';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<SavedLocation?> read() async {
    final p = await _prefs;
    final city = p.getString(_kCity);
    if (city == null || city.isEmpty) return null;
    final lat = p.getDouble(_kLat);
    final lng = p.getDouble(_kLng);
    return SavedLocation(city: city, latitude: lat, longitude: lng);
  }

  Future<void> write(SavedLocation location) async {
    final p = await _prefs;
    await p.setString(_kCity, location.city);
    if (location.latitude != null) {
      await p.setDouble(_kLat, location.latitude!);
    }
    if (location.longitude != null) {
      await p.setDouble(_kLng, location.longitude!);
    }
  }
}

final locationStorageProvider = Provider<LocationStorage>((ref) => LocationStorage());
