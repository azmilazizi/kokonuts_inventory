import 'dart:convert';

import 'package:http/http.dart' as http;

class WarehouseUnitService {
  WarehouseUnitService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String?> fetchUnitLabel({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/unit/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw WarehouseUnitException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw WarehouseUnitException(
        'Unit request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw WarehouseUnitException('Unable to parse unit response: $error');
    }

    final label = _extractUnitLabel(decoded);
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }
    return null;
  }

  String? _extractUnitLabel(dynamic source) {
    if (source is Map<String, dynamic>) {
      final label = _readString(source, const [
        'unit_name',
        'name',
        'title',
        'label',
        'symbol',
        'unit',
      ]);
      if (label != null) {
        return label;
      }
      for (final value in source.values) {
        final result = _extractUnitLabel(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractUnitLabel(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      if (value is num || value is bool) {
        return value.toString();
      }
    }
    return null;
  }
}

class WarehouseUnitException implements Exception {
  WarehouseUnitException(this.message);

  final String message;

  @override
  String toString() => 'WarehouseUnitException: $message';
}
