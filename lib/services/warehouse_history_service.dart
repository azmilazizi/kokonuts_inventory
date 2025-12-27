import 'dart:convert';

import 'package:http/http.dart' as http;

class WarehouseHistoryService {
  WarehouseHistoryService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://crm.kokonuts.my/warehouse/api/v1/warehouse_history';

  Future<WarehouseHistoryPage> fetchHistory({
    required int page,
    required int perPage,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw WarehouseHistoryException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw WarehouseHistoryException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw WarehouseHistoryException('Unable to parse response: $error');
    }

    final rawEntries = _extractHistoryEntries(decoded);
    final entries = rawEntries.map(WarehouseHistoryEntry.fromJson).toList();

    final pagination = _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return WarehouseHistoryPage(
      entries: entries,
      hasMore: pagination.hasMore,
    );
  }

  List<Map<String, dynamic>> _extractHistoryEntries(dynamic decoded) {
    final entries = <Map<String, dynamic>>[];

    void collect(dynamic source) {
      if (source is List) {
        for (final item in source) {
          collect(item);
        }
        return;
      }
      if (source is Map<String, dynamic>) {
        if (_looksLikeHistoryEntry(source)) {
          entries.add(source);
        }
        for (final value in source.values) {
          collect(value);
        }
      }
    }

    collect(decoded);
    return entries;
  }

  bool _looksLikeHistoryEntry(Map<String, dynamic> map) {
    final id = _readString(map, const [
      'id',
      'history_id',
      'warehouse_history_id',
      'warehouseHistoryId',
    ]);
    if (id == null) {
      return false;
    }

    const keys = [
      'supplier_name',
      'supplierName',
      'purchase_order',
      'purchaseOrder',
      'voucher_date',
      'voucherDate',
      'goods_value',
      'goodsValue',
      'item_code',
      'itemCode',
      'warehouse_code',
      'warehouseCode',
      'opening_stock',
      'openingStock',
      'closing_stock',
      'closingStock',
      'lot_number',
      'lotNumber',
      'quantity_sold',
      'quantitySold',
      'status',
    ];

    return keys.any(map.containsKey);
  }

  PaginationInfo _resolvePagination(
    dynamic decoded, {
    required int currentPage,
    required int perPage,
  }) {
    if (decoded is Map<String, dynamic>) {
      final meta = _findMap(decoded, const ['meta', 'pagination']);
      if (meta != null) {
        final totalPages = _readInt(meta, ['last_page', 'total_pages']);
        final current = _readInt(meta, ['current_page', 'page']) ?? currentPage;
        if (totalPages != null) {
          return PaginationInfo(hasMore: current < totalPages);
        }
        final nextPage = _readInt(meta, ['next_page']);
        if (nextPage != null) {
          return PaginationInfo(hasMore: nextPage > current);
        }
      }

      final links = _findMap(decoded, const ['links']);
      if (links != null) {
        final nextUrl = _readString(links, ['next', 'next_page_url']);
        if (nextUrl != null && nextUrl.isNotEmpty) {
          return const PaginationInfo(hasMore: true);
        }
      }
    }

    return PaginationInfo(hasMore: _countItems(decoded) >= perPage);
  }

  Map<String, dynamic>? _findMap(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
    }
    for (final value in source.values) {
      if (value is Map<String, dynamic>) {
        final nested = _findMap(value, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  int _countItems(dynamic decoded) {
    if (decoded is List) {
      return decoded.length;
    }
    if (decoded is Map<String, dynamic>) {
      final results = _extractHistoryEntries(decoded);
      return results.length;
    }
    return 0;
  }

  int? _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      if (value is int) {
        return value;
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num || value is bool) {
        return value.toString();
      }
    }
    return null;
  }
}

class WarehouseHistoryPage {
  WarehouseHistoryPage({
    required this.entries,
    required this.hasMore,
  });

  final List<WarehouseHistoryEntry> entries;
  final bool hasMore;
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class WarehouseHistoryEntry {
  WarehouseHistoryEntry({
    required this.id,
    required this.supplierName,
    required this.purchaseOrder,
    required this.voucherDate,
    required this.goodsValue,
    required this.itemCode,
    required this.warehouseCode,
    required this.voucherDateSecondary,
    required this.openingStock,
    required this.closingStock,
    required this.lotNumber,
    required this.quantitySold,
    required this.status,
  });

  factory WarehouseHistoryEntry.fromJson(Map<String, dynamic> json) {
    String readString(List<String> keys) => _readString(json, keys) ?? '';
    String readNumber(List<String> keys) => _readNumber(json, keys) ?? '';

    return WarehouseHistoryEntry(
      id: readString(const ['id', 'history_id', 'warehouse_history_id']),
      supplierName: readString(const ['supplier_name', 'supplierName', 'supplier']),
      purchaseOrder: readString(const [
        'purchase_order',
        'purchaseOrder',
        'po_number',
        'poNumber',
      ]),
      voucherDate: readString(const [
        'voucher_date',
        'voucherDate',
        'transaction_date',
        'transactionDate',
      ]),
      goodsValue: readNumber(const ['goods_value', 'goodsValue', 'value']),
      itemCode: readString(const ['item_code', 'itemCode', 'sku_code', 'skuCode']),
      warehouseCode:
          readString(const ['warehouse_code', 'warehouseCode', 'warehouse']),
      voucherDateSecondary: readString(const [
        'voucher_date_secondary',
        'voucherDateSecondary',
        'stock_voucher_date',
        'stockVoucherDate',
        'warehouse_voucher_date',
        'warehouseVoucherDate',
      ]),
      openingStock:
          readNumber(const ['opening_stock', 'openingStock', 'opening_balance']),
      closingStock:
          readNumber(const ['closing_stock', 'closingStock', 'closing_balance']),
      lotNumber: readString(const ['lot_number', 'lotNumber', 'batch_number']),
      quantitySold:
          readNumber(const ['quantity_sold', 'quantitySold', 'quantity']),
      status: readString(const ['status', 'state']),
    );
  }

  final String id;
  final String supplierName;
  final String purchaseOrder;
  final String voucherDate;
  final String goodsValue;
  final String itemCode;
  final String warehouseCode;
  final String voucherDateSecondary;
  final String openingStock;
  final String closingStock;
  final String lotNumber;
  final String quantitySold;
  final String status;

  String get lotQuantityLabel {
    final hasLot = lotNumber.trim().isNotEmpty;
    final hasQuantity = quantitySold.trim().isNotEmpty;
    if (hasLot && hasQuantity) {
      return '${lotNumber.trim()} / ${quantitySold.trim()}';
    }
    if (hasLot) {
      return lotNumber.trim();
    }
    if (hasQuantity) {
      return quantitySold.trim();
    }
    return '';
  }

  static String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      } else if (value is num || value is bool) {
        return value.toString();
      }
    }
    return null;
  }

  static String? _readNumber(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) {
        return value.toString();
      }
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

class WarehouseHistoryException implements Exception {
  const WarehouseHistoryException(this.message);

  final String message;

  @override
  String toString() => 'WarehouseHistoryException: $message';
}
