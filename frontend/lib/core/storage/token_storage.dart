import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAccessToken = 'access_token';
const _kRefreshToken = 'refresh_token';
const _kCurrentUser = 'current_user';

/// Token/session storage. Uses SharedPreferences (web-friendly). Secret values
/// should be moved to flutter_secure_storage on mobile builds.
class TokenStorage {
  SharedPreferences? _cachedPrefs;
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  bool _initialised = false;

  Future<SharedPreferences> get _prefs async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  Future<void> _ensureInit() async {
    if (_initialised) return;
    final p = await _prefs;
    _cachedAccessToken = p.getString(_kAccessToken);
    _cachedRefreshToken = p.getString(_kRefreshToken);
    _initialised = true;
  }

  Future<String?> readAccessToken() async {
    await _ensureInit();
    return _cachedAccessToken;
  }

  Future<String?> readRefreshToken() async {
    await _ensureInit();
    return _cachedRefreshToken;
  }

  Future<void> writeTokens({String? accessToken, String? refreshToken}) async {
    final p = await _prefs;
    if (accessToken != null) {
      _cachedAccessToken = accessToken;
      await p.setString(_kAccessToken, accessToken);
    }
    if (refreshToken != null) {
      _cachedRefreshToken = refreshToken;
      await p.setString(_kRefreshToken, refreshToken);
    }
  }

  Future<void> clear() async {
    final p = await _prefs;
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await p.remove(_kAccessToken);
    await p.remove(_kRefreshToken);
  }

  Future<void> saveCurrentUser(String json) async {
    await (await _prefs).setString(_kCurrentUser, json);
  }

  Future<String?> readCurrentUser() async => (await _prefs).getString(_kCurrentUser);
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
