import 'dart:convert';

import 'package:http/http.dart' as http;

class InventoryManageService {
  InventoryManageService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri _warehousesUri =
      Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/warehouses');
  static final Uri _inventoryUri =
      Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/inventory_manages');

  Future<List<InventoryWarehouseOption>> fetchWarehouses({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(_warehousesUri, headers: headers);
    } catch (error) {
      throw InventoryManageException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw InventoryManageException(
        'Warehouses request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw InventoryManageException(
        'Unable to parse warehouses response: $error',
      );
    }

    final List<InventoryWarehouseOption> warehouses = [];
    _collectWarehouses(decoded, warehouses);
    final unique = <String, InventoryWarehouseOption>{};
    for (final warehouse in warehouses) {
      unique[warehouse.id] = warehouse;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return deduped;
  }

  Future<List<InventoryManageItem>> fetchInventoryItems({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(_inventoryUri, headers: headers);
    } catch (error) {
      throw InventoryManageException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw InventoryManageException(
        'Inventory request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw InventoryManageException(
        'Unable to parse inventory response: $error',
      );
    }

    final items = <InventoryManageItem>[];
    _collectInventoryItems(decoded, items);
    return items;
  }

  void _collectWarehouses(
    dynamic source,
    List<InventoryWarehouseOption> target,
  ) {
    if (source is Map<String, dynamic>) {
      final name = _readString(source, const ['warehouse_name', 'name', 'title']);
      final code = _readString(source, const ['warehouse_code', 'code']);
      final id = _readString(source, const ['warehouse_id', 'id']);
      if (name != null && id != null) {
        target.add(InventoryWarehouseOption(id: id, code: code, name: name));
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

  void _collectInventoryItems(
    dynamic source,
    List<InventoryManageItem> target,
  ) {
    if (source is Map<String, dynamic>) {
      final skuCode = _readString(source, const ['sku_code', 'skuCode', 'sku']);
      final skuName = _readString(source, const ['sku_name', 'skuName', 'name']);
      if (skuCode != null || skuName != null) {
        target.add(InventoryManageItem.fromJson(source));
      }
      for (final value in source.values) {
        _collectInventoryItems(value, target);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectInventoryItems(item, target);
      }
    }
  }

  String? _readString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) {
        continue;
      }
      final stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) {
        return stringValue;
      }
    }
    return null;
  }
}

class InventoryWarehouseOption {
  const InventoryWarehouseOption({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String? code;
  final String name;

  String get label {
    final trimmedCode = code?.trim();
    if (trimmedCode != null && trimmedCode.isNotEmpty) {
      return '${trimmedCode}_$name';
    }
    return name;
  }
}

class InventoryManageItem {
  InventoryManageItem({
    required this.id,
    required this.skuCode,
    required this.skuName,
    required this.inventoryManage,
    required this.inventoryNumberMin,
    required this.inventoryNumberMax,
  });

  factory InventoryManageItem.fromJson(Map<String, dynamic> json) {
    final manage = <InventoryManageLot>[];
    final rawManage = json['inventory_manage'];
    if (rawManage is List) {
      for (final entry in rawManage) {
        if (entry is Map<String, dynamic>) {
          manage.add(InventoryManageLot.fromJson(entry));
        }
      }
    }

    double? min;
    double? max;
    final rawMin = json['inventory_commodity_min'];
    if (rawMin is Map<String, dynamic>) {
      min = _parseNumber(rawMin['inventory_number_min']);
      max = _parseNumber(rawMin['inventory_number_max']);
    }

    return InventoryManageItem(
      id: json['id']?.toString() ?? '',
      skuCode: json['sku_code']?.toString() ?? '',
      skuName: json['sku_name']?.toString() ?? '',
      inventoryManage: manage,
      inventoryNumberMin: min,
      inventoryNumberMax: max,
    );
  }

  final String id;
  final String skuCode;
  final String skuName;
  final List<InventoryManageLot> inventoryManage;
  final double? inventoryNumberMin;
  final double? inventoryNumberMax;

  static double? _parseNumber(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}

class InventoryManageLot {
  InventoryManageLot({
    required this.id,
    required this.warehouseId,
    required this.inventoryNumber,
    required this.lotNumber,
    required this.purchasePrice,
  });

  factory InventoryManageLot.fromJson(Map<String, dynamic> json) {
    return InventoryManageLot(
      id: json['id']?.toString() ?? '',
      warehouseId: json['warehouse_id']?.toString() ?? '',
      inventoryNumber: _parseNumber(json['inventory_number']) ?? 0,
      lotNumber: json['lot_number']?.toString() ?? '',
      purchasePrice: json['purchase_price']?.toString() ?? '',
    );
  }

  final String id;
  final String warehouseId;
  final double inventoryNumber;
  final String lotNumber;
  final String purchasePrice;

  static double? _parseNumber(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}

class InventoryManageException implements Exception {
  InventoryManageException(this.message);

  final String message;

  @override
  String toString() => 'InventoryManageException: $message';
}
