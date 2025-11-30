import 'dart:convert';

import 'package:http/http.dart' as http;

/// Represents a single purchase order entry returned from the API.
class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.orderName,
    required this.total,
    required this.currencySymbol,
    this.orderDate,
    this.rawOrderDate,
  });

  final int id;
  final String orderNumber;
  final String orderName;
  final double total;
  final String currencySymbol;
  final DateTime? orderDate;
  final String? rawOrderDate;

  /// Creates an instance of [PurchaseOrder] from a JSON map.
  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final currencySymbol = json['currency_symbol']?.toString();
    final currencyName = json['currency_name']?.toString();
    final resolvedCurrency = (currencySymbol == null || currencySymbol.isEmpty)
        ? (currencyName == null || currencyName.isEmpty ? '' : currencyName)
        : currencySymbol;
    return PurchaseOrder(
      id: _parseInt(json['id']) ?? 0,
      orderNumber: json['pur_order_number']?.toString() ?? '',
      orderName: json['pur_order_name']?.toString() ?? '',
      total: _parseDouble(json['total']) ?? 0,
      currencySymbol: resolvedCurrency,
      orderDate: _parseDate(json['order_date']),
      rawOrderDate: json['order_date']?.toString(),
    );
  }

  /// Formats the total amount using the provided currency symbol.
  String get formattedTotal {
    final formatted = total.toStringAsFixed(2);
    if (currencySymbol.isEmpty) {
      return formatted;
    }
    return '$currencySymbol $formatted';
  }

  /// A human-friendly label for grouping and displaying the order date.
  String? get dateLabel {
    if (orderDate != null) {
      final day = orderDate!.day.toString().padLeft(2, '0');
      final month = orderDate!.month.toString().padLeft(2, '0');
      final year = orderDate!.year.toString();
      return '$day-$month-$year';
    }

    final trimmed = rawOrderDate?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is double) {
      return value.round();
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        return DateTime.parse(trimmed);
      } catch (_) {
        final delimiterMatch = RegExp(r'[-/]').allMatches(trimmed).isNotEmpty;
        final parts = delimiterMatch ? trimmed.split(RegExp(r'[-/]')) : null;
        if (parts != null && parts.length == 3) {
          final first = int.tryParse(parts[0]);
          final second = int.tryParse(parts[1]);
          final third = int.tryParse(parts[2]);
          if (first != null && second != null && third != null) {
            if (parts[0].length == 4) {
              return DateTime(first, second, third);
            }
            return DateTime(third, second, first);
          }
        }
      }
    }
    return null;
  }
}

/// A container for paginated purchase orders.
class PurchaseOrderPage {
  PurchaseOrderPage({required this.orders, this.nextPage});

  final List<PurchaseOrder> orders;
  final int? nextPage;

  bool get hasMore => nextPage != null;
}

/// Thrown when the purchase orders request fails.
class PurchaseOrderException implements Exception {
  PurchaseOrderException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrderException: $message';
}

/// Handles retrieving purchase orders from the backend service with pagination.
class PurchaseOrderService {
  PurchaseOrderService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://crm.kokonuts.my/api/v1/purchase/orders';

  final http.Client _client;

  /// Fetches a page of purchase orders from the API.
  Future<PurchaseOrderPage> fetchPurchaseOrders({
    Map<String, String>? headers,
    int page = 1,
    int perPage = 20,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'page': '$page',
        'per_page': '$perPage',
      },
    );

    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      ...?headers,
    };

    late http.Response response;
    try {
      response = await _client.get(uri, headers: requestHeaders);
    } catch (e) {
      throw PurchaseOrderException('Unable to reach the server. Details: $e');
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderException(
        'We couldn\'t load purchase orders right now. Please try again in a moment.',
      );
    }

    final decoded = jsonDecode(response.body);
    final payload = _extractPayload(decoded);
    final orders = _parseOrders(payload.items);
    final nextPage = _parseNextPage(
      decoded,
      paginationSource: payload.pagination,
      currentPage: page,
      perPage: perPage,
      itemCount: orders.length,
    );

    return PurchaseOrderPage(orders: orders, nextPage: nextPage);
  }

  List<PurchaseOrder> _parseOrders(List<dynamic> items) {
    return items
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrder.fromJson)
        .toList(growable: false);
  }

  int? _parseNextPage(
    dynamic decoded, {
    Map<String, dynamic>? paginationSource,
    required int currentPage,
    required int perPage,
    required int itemCount,
  }) {
    int? nextPage;
    final pagination = paginationSource ?? _findPaginationMap(decoded);
    if (pagination != null) {
      nextPage ??= _resolveFromMeta(pagination);
    }

    nextPage ??= _resolveFromLinks(decoded);

    if (nextPage != null) {
      return nextPage;
    }

    if (itemCount >= perPage) {
      return currentPage + 1;
    }

    return null;
  }

  _Payload _extractPayload(dynamic decoded) {
    if (decoded is List) {
      return _Payload(items: decoded);
    }

    if (decoded is Map<String, dynamic>) {
      final prioritizedKeys = ['data', 'results', 'items'];

      for (final key in prioritizedKeys) {
        final value = decoded[key];
        if (value is List) {
          return _Payload(
            items: value,
            pagination: _firstNonNull([
              _looksLikePagination(decoded) ? decoded : null,
              _extractMetaMap(decoded),
            ]),
          );
        }
        if (value is Map<String, dynamic>) {
          final nested = _extractPayload(value);
          if (nested.items.isNotEmpty || nested.pagination != null) {
            return _Payload(
              items: nested.items,
              pagination: nested.pagination ??
                  _firstNonNull([
                    _looksLikePagination(value) ? value : null,
                    _looksLikePagination(decoded) ? decoded : null,
                    _extractMetaMap(decoded),
                  ]),
            );
          }
        }
      }

      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List) {
          return _Payload(
            items: value,
            pagination: _firstNonNull([
              _looksLikePagination(decoded) ? decoded : null,
              _extractMetaMap(decoded),
            ]),
          );
        }
        if (value is Map<String, dynamic>) {
          final nested = _extractPayload(value);
          if (nested.items.isNotEmpty || nested.pagination != null) {
            return _Payload(
              items: nested.items,
              pagination: nested.pagination ??
                  _firstNonNull([
                    _looksLikePagination(value) ? value : null,
                    _looksLikePagination(decoded) ? decoded : null,
                    _extractMetaMap(decoded),
                  ]),
            );
          }
        }
      }

      return _Payload(
        items: const [],
        pagination: _firstNonNull([
          _looksLikePagination(decoded) ? decoded : null,
          _extractMetaMap(decoded),
        ]),
      );
    }

    return const _Payload(items: []);
  }

  Map<String, dynamic>? _extractMetaMap(Map<String, dynamic> decoded) {
    final meta = decoded['meta'];
    if (meta is Map<String, dynamic>) {
      return meta;
    }
    return null;
  }

  Map<String, dynamic>? _findPaginationMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikePagination(decoded)) {
        return decoded;
      }

      final meta = decoded['meta'];
      if (meta is Map<String, dynamic> && _looksLikePagination(meta)) {
        return meta;
      }

      for (final value in decoded.values) {
        final candidate = _findPaginationMap(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }
    return null;
  }

  bool _looksLikePagination(Map<String, dynamic> map) {
    return map.containsKey('current_page') ||
        map.containsKey('last_page') ||
        map.containsKey('next_page') ||
        map.containsKey('next_page_url');
  }

  Map<String, dynamic>? _firstNonNull(List<Map<String, dynamic>?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  int? _resolveFromLinks(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final links = decoded['links'];
      if (links is Map<String, dynamic>) {
        final nextUrl = links['next'];
        if (nextUrl is String) {
          return _parsePageFromUrl(nextUrl);
        }
      }
      for (final value in decoded.values) {
        final nested = _resolveFromLinks(value);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  int? _resolveFromMeta(Map<String, dynamic> meta) {
    final current = meta['current_page'];
    final last = meta['last_page'];
    final next = meta['next_page'];

    if (next is int) {
      return next;
    }

    if (current is int && last is int) {
      if (current < last) {
        return current + 1;
      }
      return null;
    }

    if (next is String) {
      return int.tryParse(next);
    }

    final nextUrl = meta['next_page_url'];
    if (nextUrl is String) {
      return _parsePageFromUrl(nextUrl);
    }

    return null;
  }

  int? _parsePageFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final page = uri.queryParameters['page'];
      if (page != null) {
        return int.tryParse(page);
      }
    } catch (_) {
      // Ignore parsing errors and treat as no next page.
    }
    return null;
  }
}

class _Payload {
  const _Payload({required this.items, this.pagination});

  final List<dynamic> items;
  final Map<String, dynamic>? pagination;
}
