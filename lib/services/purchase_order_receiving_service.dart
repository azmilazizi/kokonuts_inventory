import 'dart:convert';

import 'package:http/http.dart' as http;

class PurchaseOrderReceivingService {
  PurchaseOrderReceivingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order';

  Future<PurchaseOrderReceivingDetail> fetchPurchaseOrder({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw PurchaseOrderReceivingException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderReceivingException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrderReceivingException(
        'Unable to parse response: $error',
      );
    }

    final orderMap = _extractPurchaseOrder(decoded);
    if (orderMap == null) {
      throw const PurchaseOrderReceivingException(
        'Purchase order details were not found in the response.',
      );
    }

    return PurchaseOrderReceivingDetail.fromJson(orderMap);
  }

  Map<String, dynamic>? _extractPurchaseOrder(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (_looksLikeOrder(data)) {
        return data;
      }

      final wrapped = _extractFromOrderWrapper(data);
      if (wrapped != null) {
        return wrapped;
      }

      for (final value in data.values) {
        final candidate = _extractPurchaseOrder(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    if (data is List) {
      for (final value in data) {
        final candidate = _extractPurchaseOrder(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _extractFromOrderWrapper(Map<String, dynamic> data) {
    const orderKeys = [
      'order',
      'purchase_order',
      'purchaseOrder',
    ];
    for (final key in orderKeys) {
      final orderValue = data[key];
      if (orderValue is Map<String, dynamic>) {
        final normalized = Map<String, dynamic>.from(orderValue);
        final items = data['items'] ??
            data['order_items'] ??
            data['purchase_order_items'];
        if (items != null) {
          normalized['items'] = items;
        }
        return normalized;
      }
    }
    return null;
  }

  bool _looksLikeOrder(Map<String, dynamic> data) {
    if (!data.containsKey('id')) {
      return false;
    }
    final items = data['items'];
    return items is List || items is Map<String, dynamic>;
  }
}

class PurchaseOrderReceivingDetail {
  PurchaseOrderReceivingDetail({
    required this.id,
    required this.items,
  });

  factory PurchaseOrderReceivingDetail.fromJson(Map<String, dynamic> json) {
    final items = _extractItems(json['items'])
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrderReceivingItem.fromJson)
        .toList(growable: false);

    return PurchaseOrderReceivingDetail(
      id: _stringValue(json['id']) ?? '',
      items: items,
    );
  }

  final String id;
  final List<PurchaseOrderReceivingItem> items;
}

class PurchaseOrderReceivingItem {
  PurchaseOrderReceivingItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.unitId,
  });

  factory PurchaseOrderReceivingItem.fromJson(Map<String, dynamic> json) {
    final unitId = _parseUnitId(json);
    return PurchaseOrderReceivingItem(
      name: _stringValue(json['item_name']) ??
          _stringValue(json['name']) ??
          '—',
      quantity: _parseDouble(json['quantity'] ?? json['qty']) ?? 0,
      unitPrice: _parseDouble(json['unit_price'] ?? json['rate'] ?? json['price']),
      total: _parseDouble(
        json['total'] ?? json['amount'] ?? json['line_total'] ?? json['subtotal'],
      ),
      unitId: unitId,
    );
  }

  final String name;
  final double quantity;
  final double? unitPrice;
  final double? total;
  final String? unitId;
}

class PurchaseOrderReceivingException implements Exception {
  const PurchaseOrderReceivingException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrderReceivingException: $message';
}

String? _stringValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return value.toString();
}

double? _parseDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }
  return null;
}

String? _parseUnitId(Map<String, dynamic> json) {
  final direct = _stringValue(json['unit_id']) ?? _stringValue(json['unitId']);
  if (direct != null) {
    return direct;
  }
  final unit = json['unit'];
  if (unit is Map<String, dynamic>) {
    return _stringValue(unit['id']) ?? _stringValue(unit['unit_id']);
  }
  return _stringValue(unit);
}

List<dynamic> _extractItems(dynamic source) {
  if (source is List) {
    return source;
  }
  if (source is Map<String, dynamic>) {
    const preferredKeys = [
      'items',
      'order_items',
      'purchase_order_items',
      'details',
      'data',
    ];
    for (final key in preferredKeys) {
      final value = source[key];
      final list = _extractItems(value);
      if (list.isNotEmpty) {
        return list;
      }
    }
    for (final value in source.values) {
      final list = _extractItems(value);
      if (list.isNotEmpty) {
        return list;
      }
    }
  }
  return const [];
}
