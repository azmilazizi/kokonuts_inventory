import 'dart:convert';

import 'package:http/http.dart' as http;

class InventoryItemsService {
  InventoryItemsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final _itemsUri = Uri.parse(
    'https://crm.kokonuts.my/warehouse/api/v1/items'
    '?can_be_inventory=can_be_inventory',
  );

  Future<List<InventoryItem>> fetchItems({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(_itemsUri, headers: headers);
    } catch (error) {
      throw InventoryItemsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw InventoryItemsException(
        'Items request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw InventoryItemsException('Unable to parse items response: $error');
    }

    final List<InventoryItem> items = [];
    _collectItems(decoded, items);
    final unique = <String, InventoryItem>{};
    for (final item in items) {
      unique[item.id] = item;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return deduped;
  }

  void _collectItems(dynamic source, List<InventoryItem> target) {
    if (source is Map<String, dynamic>) {
      final name = _readString(source, const [
        'name',
        'item_name',
        'itemName',
        'title',
        'sku_name',
        'skuName'
      ]);
      final id = _readString(source, const ['id', 'item_id', 'itemId', 'uid']);
      final skuCode = _readString(source, const ['sku_code', 'skuCode', 'sku']);
      final skuName =
          _readString(source, const ['sku_name', 'skuName', 'name']);
      if (name != null && id != null) {
        target.add(InventoryItem(
          id: id,
          name: name,
          skuCode: skuCode,
          skuName: skuName,
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

  String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    this.skuCode,
    this.skuName,
  });

  final String id;
  final String name;
  final String? skuCode;
  final String? skuName;
}

class InventoryItemsException implements Exception {
  InventoryItemsException(this.message);

  final String message;

  @override
  String toString() => 'InventoryItemsException: $message';
}
