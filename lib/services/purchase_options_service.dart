import 'dart:convert';

import 'package:http/http.dart' as http;

class PurchaseOptionsService {
  PurchaseOptionsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _optionsUrl = 'https://crm.kokonuts.my/purchase/api/v1/options';

  Future<PurchaseOptions> fetchPurchaseOptions({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(_optionsUrl), headers: headers);
    } catch (error) {
      throw PurchaseOptionsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PurchaseOptionsException(
        'Options request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOptionsException('Unable to parse options response: $error');
    }

    return PurchaseOptions(
      purchaseOrderPrefix: _extractPurchaseOrderPrefix(decoded),
      nextPurchaseOrderNumber: _extractNextPurchaseOrderNumber(decoded),
    );
  }

  String? _extractPurchaseOrderPrefix(dynamic source) {
    if (source is Map<String, dynamic>) {
      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'pur_order_prefix' ||
            key == 'purchase_order_prefix' ||
            key == 'po_prefix' ||
            key == 'prefix') {
          return _asString(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractPurchaseOrderPrefix(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractPurchaseOrderPrefix(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  int? _extractNextPurchaseOrderNumber(dynamic source) {
    if (source is Map<String, dynamic>) {
      if (source['name'] == 'next_po_number' && source.containsKey('value')) {
        return _asInt(source['value']);
      }

      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'next_po_number' ||
            key == 'nextponumber' ||
            key == 'next_po' ||
            key == 'nextpo') {
          return _asInt(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractNextPurchaseOrderNumber(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractNextPurchaseOrderNumber(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed;
    }
    return null;
  }

  String? _asString(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    return value?.toString();
  }
}

class PurchaseOptions {
  const PurchaseOptions({
    required this.purchaseOrderPrefix,
    required this.nextPurchaseOrderNumber,
  });

  final String? purchaseOrderPrefix;
  final int? nextPurchaseOrderNumber;
}

class PurchaseOptionsException implements Exception {
  PurchaseOptionsException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOptionsException: $message';
}
