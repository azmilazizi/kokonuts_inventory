import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles reading and writing authentication state to persistent storage.
class SessionManager {
  static const _authTokenKey = 'auth_token';
  static const _currentUsernameKey = 'current_username';
  static const _themeModePrefix = 'theme_mode_';
  static const _currentStaffIdKey = 'current_staff_id';

  Future<String?> getAuthToken() async {
    final prefs = await _tryGetPreferences();
    return prefs?.getString(_authTokenKey);
  }

  Future<void> saveAuthToken(String token) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(_authTokenKey, token);
  }

  Future<void> clearAuthToken() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.remove(_authTokenKey);
  }

  Future<void> saveCurrentUsername(String username) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(_currentUsernameKey, username);
  }

  Future<String?> getCurrentUsername() async {
    final prefs = await _tryGetPreferences();
    return prefs?.getString(_currentUsernameKey);
  }

  Future<void> clearCurrentUsername() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.remove(_currentUsernameKey);
  }

  Future<void> saveCurrentStaffId(String staffId) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(_currentStaffIdKey, staffId);
  }

  Future<String?> getCurrentStaffId() async {
    final prefs = await _tryGetPreferences();
    return prefs?.getString(_currentStaffIdKey);
  }

  Future<void> clearCurrentStaffId() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.remove(_currentStaffIdKey);
  }

  Future<void> saveThemeModeForUser(String username, ThemeMode mode) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(_themeModeKeyForUser(username), mode.name);
  }

  Future<ThemeMode?> getThemeModeForUser(String username) async {
    final prefs = await _tryGetPreferences();
    final storedValue = prefs?.getString(_themeModeKeyForUser(username));
    return _decodeThemeMode(storedValue);
  }

  Future<SharedPreferences?> _tryGetPreferences() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException catch (error, stackTrace) {
      // During hot restart on the web the shared_preferences plugin may not yet
      // be registered. Rather than crashing the app we gracefully fall back to
      // an in-memory session by returning null.
      debugPrint('SharedPreferences unavailable: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  String _themeModeKeyForUser(String username) => '$_themeModePrefix$username';

  ThemeMode? _decodeThemeMode(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    for (final mode in ThemeMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }

    return null;
  }
}
