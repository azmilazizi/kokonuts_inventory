import 'dart:convert';

import 'package:http/http.dart' as http;

class StocktakeService {
  StocktakeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _warehousesUri =
      Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/warehouses');
  static final Uri _itemsUri = Uri.parse(
    'https://crm.kokonuts.my/warehouse/api/v1/items'
    '?can_be_purchased=can_be_purchased&can_be_inventory=can_be_inventory',
  );

  Future<List<WarehouseOption>> fetchWarehouses({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(_warehousesUri, headers: headers);
    } catch (error) {
      throw StocktakeServiceException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw StocktakeServiceException(
        'Warehouses request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw StocktakeServiceException('Unable to parse warehouses response: $error');
    }

    final List<WarehouseOption> warehouses = [];
    _collectWarehouses(decoded, warehouses);
    final unique = <String, WarehouseOption>{};
    for (final warehouse in warehouses) {
      unique[warehouse.id] = warehouse;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return deduped;
  }

  Future<List<StocktakeItemOption>> fetchItems({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(_itemsUri, headers: headers);
    } catch (error) {
      throw StocktakeServiceException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw StocktakeServiceException(
        'Items request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw StocktakeServiceException('Unable to parse items response: $error');
    }

    final List<StocktakeItemOption> items = [];
    _collectItems(decoded, items);
    final unique = <String, StocktakeItemOption>{};
    for (final item in items) {
      unique[item.id] = item;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return deduped;
  }

  Future<List<StocktakeLotOption>> fetchLots({
    required String itemId,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(
      'https://crm.kokonuts.my/warehouse/api/v1/item/$itemId/lots',
    );

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw StocktakeServiceException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw StocktakeServiceException(
        'Lots request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw StocktakeServiceException('Unable to parse lots response: $error');
    }

    final List<StocktakeLotOption> lots = [];
    _collectLots(decoded, lots);
    final unique = <String, StocktakeLotOption>{};
    for (final lot in lots) {
      unique[lot.lotNumber] = lot;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.lotNumber.toLowerCase().compareTo(b.lotNumber.toLowerCase()));
    return deduped;
  }

  void _collectWarehouses(dynamic source, List<WarehouseOption> target) {
    if (source is Map<String, dynamic>) {
      final name = _readString(source, const ['warehouse_name', 'name', 'title']);
      final id = _readString(source, const ['warehouse_id', 'id']);
      if (name != null && id != null) {
        target.add(WarehouseOption(id: id, name: name));
      }
      for (final value in source.values) {
        _collectWarehouses(value, target);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectWarehouses(item, target);
      }
    }
  }

  void _collectItems(dynamic source, List<StocktakeItemOption> target) {
    if (source is Map<String, dynamic>) {
      final id = _readString(source, const ['item_id', 'id']);
      final skuCode = _readString(source, const ['sku_code', 'skuCode', 'sku']);
      final skuName = _readString(source, const ['sku_name', 'skuName', 'name']);
      final name = _readString(source, const ['name', 'item_name', 'title']);
      final total = _readString(source, const [
        'total',
        'inventory_total',
        'total_number',
        'total_quantity',
        'inventory_number',
      ]);

      if (id != null && (skuName != null || name != null)) {
        target.add(StocktakeItemOption(
          id: id,
          skuCode: skuCode,
          skuName: skuName ?? name ?? id,
          total: total,
        ));
      }
      for (final value in source.values) {
        _collectItems(value, target);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectItems(item, target);
      }
    }
  }

  void _collectLots(dynamic source, List<StocktakeLotOption> target) {
    if (source is Map<String, dynamic>) {
      final lotNumber = _readString(source, const ['lot_number', 'lotNumber', 'lot']);
      final inventory = _readString(source, const [
        'inventory_number',
        'inventory',
        'current_number',
        'quantity',
      ]);
      if (lotNumber != null && inventory != null) {
        target.add(StocktakeLotOption(
          lotNumber: lotNumber,
          inventoryNumber: inventory,
        ));
      }
      for (final value in source.values) {
        _collectLots(value, target);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectLots(item, target);
      }
    }
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

class WarehouseOption {
  const WarehouseOption({required this.id, required this.name});

  final String id;
  final String name;
}

class StocktakeItemOption {
  const StocktakeItemOption({
    required this.id,
    required this.skuCode,
    required this.skuName,
    required this.total,
  });

  final String id;
  final String? skuCode;
  final String skuName;
  final String? total;

  String get displayName {
    final code = skuCode?.trim();
    final totalValue = total?.trim();
    final label = code == null || code.isEmpty ? skuName : '${code}_$skuName';
    return totalValue == null || totalValue.isEmpty
        ? label
        : '$label ($totalValue)';
  }
}

class StocktakeLotOption {
  const StocktakeLotOption({
    required this.lotNumber,
    required this.inventoryNumber,
  });

  final String lotNumber;
  final String inventoryNumber;
}

class StocktakeServiceException implements Exception {
  StocktakeServiceException(this.message);

  final String message;

  @override
  String toString() => 'StocktakeServiceException: $message';
}
