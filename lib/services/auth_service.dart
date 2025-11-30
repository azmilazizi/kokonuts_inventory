import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

/// Thrown when authentication fails.
class AuthException implements Exception {
  const AuthException(this.message, {this.fieldErrors = const <String, List<String>>{}});

  final String message;
  final Map<String, List<String>> fieldErrors;

  @override
  String toString() => 'AuthException: $message';
}

/// Handles authentication-related network requests.
class AuthService {
  AuthService({http.Client? client, required SessionManager sessionManager})
      : _client = client ?? http.Client(),
        _sessionManager = sessionManager;

  static const _loginUrl = 'https://crm.kokonuts.my/timesheets/api/login';

  final http.Client _client;
  final SessionManager _sessionManager;

  /// Attempts to log the user in and returns the auth token if successful.
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    late http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_loginUrl),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (e) {
      throw AuthException('Unable to reach the server. Details: $e');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final token = _extractToken(decoded);
      if (token == null || token.isEmpty) {
        throw const AuthException('The server response did not include a token.');
      }
      await _sessionManager.saveAuthToken(token);
      final staffId = _extractStaffId(decoded);
      if (staffId != null && staffId.isNotEmpty) {
        await _sessionManager.saveCurrentStaffId(staffId);
      } else {
        await _sessionManager.clearCurrentStaffId();
      }
      return AuthSession(token: token, staffId: staffId);
    }

    final fallbackMessage = 'Login failed with status code ${response.statusCode}.';
    String message = fallbackMessage;
    Map<String, List<String>>? fieldErrors;
    final generalMessages = <String>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final primaryMessage = _extractPrimaryMessage(decoded);
        if (primaryMessage != null && primaryMessage.isNotEmpty) {
          message = primaryMessage;
        }
        final parsedFieldErrors = _extractFieldErrors(decoded, generalMessages);
        if (parsedFieldErrors.isNotEmpty) {
          fieldErrors = parsedFieldErrors;
        }
        generalMessages.addAll(_normalizeMessages(decoded['error']));
      }
    } catch (_) {
      // Ignore parsing errors and fall back to default message.
    }

    if (generalMessages.isNotEmpty) {
      final combinedGeneral = generalMessages.join('\n');
      if (message == fallbackMessage || message.trim().isEmpty) {
        message = combinedGeneral;
      } else if (combinedGeneral != message) {
        message = '$message\n$combinedGeneral';
      }
    }

    throw AuthException(
      message,
      fieldErrors: fieldErrors ?? const <String, List<String>>{},
    );
  }

  /// Clears persisted authentication state.
  Future<void> logout() async {
    await _sessionManager.clearAuthToken();
    await _sessionManager.clearCurrentStaffId();
  }

  String? _extractToken(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return null;
    }

    final rawToken = decoded['token'];
    if (rawToken is String && rawToken.isNotEmpty) {
      return rawToken;
    }

    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty && entry.key.toLowerCase() == 'token') {
        return value;
      }
      if (value is Map<String, dynamic>) {
        final nestedToken = _extractToken(value);
        if (nestedToken != null && nestedToken.isNotEmpty) {
          return nestedToken;
        }
      }
      if (value is Iterable) {
        for (final element in value) {
          if (element is Map<String, dynamic>) {
            final nestedToken = _extractToken(element);
            if (nestedToken != null && nestedToken.isNotEmpty) {
              return nestedToken;
            }
          }
        }
      }
    }

    return null;
  }

  String? _extractStaffId(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return null;
    }

    const prioritizedKeys = <String>{
      'staff_id',
      'staffid',
      'staffId',
      'staff',
      'user_id',
      'userid',
      'userId',
      'user',
    };

    for (final key in prioritizedKeys) {
      final resolved = _resolveStaffId(decoded[key]);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }

    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        final nested = _extractStaffId(value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      } else if (value is Iterable) {
        for (final element in value) {
          if (element is Map<String, dynamic>) {
            final nested = _extractStaffId(element);
            if (nested != null && nested.isNotEmpty) {
              return nested;
            }
          } else {
            final resolved = _resolveStaffId(element);
            if (resolved != null && resolved.isNotEmpty) {
              return resolved;
            }
          }
        }
      } else {
        final resolved = _resolveStaffId(value);
        if (resolved != null && resolved.isNotEmpty) {
          return resolved;
        }
      }
    }

    return null;
  }

  String? _resolveStaffId(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    if (value is num) {
      return value.toString();
    }

    if (value is Map<String, dynamic>) {
      const potentialKeys = <String>{
        'id',
        'staff_id',
        'staffid',
        'staffId',
        'user_id',
        'userid',
        'userId',
      };
      for (final key in potentialKeys) {
        final nested = _resolveStaffId(value[key]);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }

    if (value is Iterable) {
      for (final element in value) {
        final resolved = _resolveStaffId(element);
        if (resolved != null && resolved.isNotEmpty) {
          return resolved;
        }
      }
    }

    return null;
  }

  String? _extractPrimaryMessage(Map<String, dynamic> decoded) {
    const keys = ['message', 'detail', 'error'];
    for (final key in keys) {
      final value = decoded[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }

  Map<String, List<String>> _extractFieldErrors(
    Map<String, dynamic> decoded,
    Set<String> generalMessages,
  ) {
    final fieldErrors = <String, List<String>>{};
    final rawErrors = decoded['errors'];
    if (rawErrors is Map) {
      rawErrors.forEach((key, value) {
        final messages = _normalizeMessages(value);
        if (messages.isEmpty) {
          return;
        }
        final normalizedKey = key.toString().toLowerCase();
        if (normalizedKey.contains('user') || normalizedKey.contains('email')) {
          _mergeFieldMessages(fieldErrors, 'username', messages);
        } else if (normalizedKey.contains('password')) {
          _mergeFieldMessages(fieldErrors, 'password', messages);
        } else if (normalizedKey == 'non_field_errors') {
          generalMessages.addAll(messages);
        } else {
          generalMessages.addAll(messages);
        }
      });
    }

    for (final field in ['username', 'password']) {
      final messages = _normalizeMessages(decoded[field]);
      if (messages.isNotEmpty) {
        _mergeFieldMessages(fieldErrors, field, messages);
      }
    }

    return fieldErrors;
  }

  List<String> _normalizeMessages(dynamic value) {
    if (value == null) {
      return const <String>[];
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const <String>[] : [trimmed];
    }
    if (value is Iterable) {
      return value
          .expand<String>((element) => _normalizeMessages(element))
          .toList();
    }
    if (value is Map) {
      return value.values
          .expand<String>((element) => _normalizeMessages(element))
          .toList();
    }
    return const <String>[];
  }

  void _mergeFieldMessages(
    Map<String, List<String>> fieldErrors,
    String field,
    List<String> messages,
  ) {
    if (messages.isEmpty) {
      return;
    }
    fieldErrors.update(
      field,
      (existing) => [...existing, ...messages],
      ifAbsent: () => List<String>.from(messages),
    );
  }
}

/// Represents an authenticated session returned from the login endpoint.
class AuthSession {
  const AuthSession({required this.token, this.staffId});

  final String token;
  final String? staffId;
}
