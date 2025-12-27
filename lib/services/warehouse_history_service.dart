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
          return;
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
    const requiredKeys = [
      'date_add',
      'old_quantity',
      'quantity',
      'lot_number',
      'lotNumber',
    ];

    if (!map.containsKey('status')) {
      return false;
    }

    if (!requiredKeys.any(map.containsKey)) {
      return false;
    }

    const optionalKeys = [
      'commodity',
      'warehouse',
      'goods_receipt',
      'goodsReceipt',
      'goods_delivery',
      'goodsDelivery',
      'internal_delivery_note',
      'internalDeliveryNote',
      'loss_adjustment',
      'lossAdjustment',
    ];

    return optionalKeys.any(map.containsKey) || requiredKeys.any(map.containsKey);
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
    required this.code,
    required this.type,
    required this.commodityName,
    required this.voucherDate,
    required this.warehouseCode,
    required this.warehouseName,
    required this.openingStock,
    required this.closingStock,
    required this.lotNumber,
  });

  factory WarehouseHistoryEntry.fromJson(Map<String, dynamic> json) {
    String readString(List<String> keys) => _readString(json, keys) ?? '';
    String readNumber(List<String> keys) => _readNumber(json, keys) ?? '';
    String readNestedString(String key, List<String> keys) =>
        _readNestedString(json, key, keys) ?? '';

    final status = readString(const ['status', 'state']);
    final normalizedStatus = status.trim().toLowerCase();
    final nestedCodes = [
      readNestedString('goods_receipt', const ['code']),
      readNestedString('goodsReceipt', const ['code']),
      readNestedString('goods_delivery', const ['code']),
      readNestedString('goodsDelivery', const ['code']),
      readNestedString('internal_delivery_note', const ['code']),
      readNestedString('internalDeliveryNote', const ['code']),
      readNestedString('loss_adjustment', const ['code']),
      readNestedString('lossAdjustment', const ['code']),
    ];

    String resolveCode() {
      switch (normalizedStatus) {
        case 'goods_receipt':
          return readNestedString('goods_receipt', const ['code']).isNotEmpty
              ? readNestedString('goods_receipt', const ['code'])
              : readNestedString('goodsReceipt', const ['code']);
        case 'goods_delivery':
          return readNestedString('goods_delivery', const ['code']).isNotEmpty
              ? readNestedString('goods_delivery', const ['code'])
              : readNestedString('goodsDelivery', const ['code']);
        case 'internal_delivery_note':
          return readNestedString('internal_delivery_note', const ['code']).isNotEmpty
              ? readNestedString('internal_delivery_note', const ['code'])
              : readNestedString('internalDeliveryNote', const ['code']);
        case 'loss_adjustment':
          return readNestedString('loss_adjustment', const ['code']).isNotEmpty
              ? readNestedString('loss_adjustment', const ['code'])
              : readNestedString('lossAdjustment', const ['code']);
      }
      for (final candidate in nestedCodes) {
        if (candidate.trim().isNotEmpty) {
          return candidate;
        }
      }
      return '';
    }

    final code = resolveCode();

    return WarehouseHistoryEntry(
      id: readString(const ['id', 'history_id', 'warehouse_history_id']),
      code: code.trim().isNotEmpty ? code : readString(const ['code']),
      type: status,
      commodityName: readNestedString(
        'commodity',
        const ['name', 'commodity_name', 'commodityName'],
      ).isNotEmpty
          ? readNestedString(
              'commodity',
              const ['name', 'commodity_name', 'commodityName'],
            )
          : readString(const ['commodity_name', 'commodityName']),
      warehouseCode: readNestedString(
        'warehouse',
        const ['code', 'warehouse_code', 'warehouseCode'],
      ).isNotEmpty
          ? readNestedString(
              'warehouse',
              const ['code', 'warehouse_code', 'warehouseCode'],
            )
          : readString(const ['warehouse_code', 'warehouseCode']),
      warehouseName: readNestedString(
        'warehouse',
        const ['name', 'warehouse_name', 'warehouseName'],
      ).isNotEmpty
          ? readNestedString(
              'warehouse',
              const ['name', 'warehouse_name', 'warehouseName'],
            )
          : readString(const ['warehouse_name', 'warehouseName']),
      voucherDate: readString(const ['date_add', 'voucher_date', 'voucherDate']),
      openingStock:
          readNumber(const ['old_quantity', 'opening_stock', 'openingStock']),
      closingStock:
          readNumber(const ['quantity', 'closing_stock', 'closingStock']),
      lotNumber: readString(const ['lot_number', 'lotNumber', 'batch_number']),
    );
  }

  final String id;
  final String code;
  final String type;
  final String commodityName;
  final String voucherDate;
  final String warehouseCode;
  final String warehouseName;
  final String openingStock;
  final String closingStock;
  final String lotNumber;

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

  static String? _readNestedString(
    Map<String, dynamic> map,
    String nestedKey,
    List<String> keys,
  ) {
    final value = map[nestedKey];
    if (value is Map<String, dynamic>) {
      return _readString(value, keys);
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
