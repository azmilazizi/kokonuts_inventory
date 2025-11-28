import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/authenticated_http_client.dart';
import '../services/session_manager.dart';

/// Stores global application state such as authentication status.
class AppState extends ChangeNotifier {
  AppState({
    required AuthService authService,
    required SessionManager sessionManager,
  }) : _authService = authService,
       _sessionManager = sessionManager;

  final AuthService _authService;
  final SessionManager _sessionManager;

  bool _isInitialized = false;
  bool _isLoggedIn = false;
  String? _authToken;
  String? _rawAuthToken;
  String? _username;
  String? _staffId;
  ThemeMode _themeMode = ThemeMode.system;

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _authToken;
  String? get username => _username;
  String? get rawAuthToken => _rawAuthToken;
  String? get staffId => _staffId;
  String? get currentUserId => _staffId ?? _username;
  ThemeMode get themeMode => _themeMode;

  /// Returns the active auth token, refreshing it from storage if needed.
  Future<String?> getValidAuthToken() async {
    if (_authToken != null && _authToken!.isNotEmpty) {
      return _authToken;
    }

    final storedToken = await _sessionManager.getAuthToken();
    if (storedToken != null && storedToken.isNotEmpty) {
      _applyToken(storedToken);
      return _authToken;
    }

    return null;
  }

  /// Loads persisted session information.
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final storedToken = await _sessionManager.getAuthToken();
    final storedUsername = await _sessionManager.getCurrentUsername();
    final storedStaffId = await _sessionManager.getCurrentStaffId();

    if (storedToken != null && storedToken.isNotEmpty) {
      _applyToken(storedToken);
      _isLoggedIn = true;
    }

    if (storedUsername != null && storedUsername.isNotEmpty) {
      _username = storedUsername;
      final storedTheme = await _sessionManager.getThemeModeForUser(storedUsername);
      if (storedTheme != null) {
        _themeMode = storedTheme;
      }
    }

    if (storedStaffId != null && storedStaffId.isNotEmpty) {
      _staffId = storedStaffId;
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Attempts to log the user in using the provided credentials.
  Future<void> login({required String username, required String password}) async {
    final session = await _authService.login(username: username, password: password);
    final token = session.token;
    _applyToken(token);
    unawaited(_sessionManager.saveAuthToken(token));
    _username = username.trim();
    if (_username != null && _username!.isNotEmpty) {
      await _sessionManager.saveCurrentUsername(_username!);
      final storedTheme = await _sessionManager.getThemeModeForUser(_username!);
      if (storedTheme != null) {
        _themeMode = storedTheme;
      } else {
        _themeMode = ThemeMode.system;
      }
    }
    final resolvedStaffId = session.staffId?.trim();
    if (resolvedStaffId != null && resolvedStaffId.isNotEmpty) {
      _staffId = resolvedStaffId;
      await _sessionManager.saveCurrentStaffId(resolvedStaffId);
    } else {
      _staffId = null;
      await _sessionManager.clearCurrentStaffId();
    }
    _isLoggedIn = true;
    notifyListeners();
  }

  /// Logs out the user and clears any persisted session information.
  Future<void> logout() async {
    await _authService.logout();
    _authToken = null;
    _rawAuthToken = null;
    _isLoggedIn = false;
    if (_username != null) {
      await _sessionManager.clearCurrentUsername();
    }
    await _sessionManager.clearAuthToken();
    _username = null;
    _staffId = null;
    await _sessionManager.clearCurrentStaffId();
    _themeMode = ThemeMode.system;
    notifyListeners();
  }

  /// Updates the preferred theme mode and persists it for the active user.
  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    final activeUser = _username;
    if (activeUser != null && activeUser.isNotEmpty) {
      await _sessionManager.saveThemeModeForUser(activeUser, mode);
    }
    notifyListeners();
  }

  void _applyToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      _authToken = null;
      _rawAuthToken = null;
      return;
    }

    _rawAuthToken = token;
    _authToken = trimmed;
  }
}
