import 'dart:convert';

import 'package:http/http.dart' as http;

class LossAdjustmentsService {
  LossAdjustmentsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/warehouse/api/v1/loss_adjustments';

  Future<LossAdjustmentsPage> fetchLossAdjustments({
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
      throw LossAdjustmentsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw LossAdjustmentsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw LossAdjustmentsException('Unable to parse response: $error');
    }

    final rawEntries = _extractLossAdjustments(decoded);
    final entries = rawEntries.map(LossAdjustmentEntry.fromJson).toList();

    final pagination = _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return LossAdjustmentsPage(entries: entries, hasMore: pagination.hasMore);
  }

  List<Map<String, dynamic>> _extractLossAdjustments(dynamic decoded) {
    final entries = <Map<String, dynamic>>[];

    void collect(dynamic source) {
      if (source is List) {
        for (final item in source) {
          collect(item);
        }
        return;
      }
      if (source is Map<String, dynamic>) {
        if (_looksLikeLossAdjustment(source)) {
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

  bool _looksLikeLossAdjustment(Map<String, dynamic> map) {
    final hasDate = map.containsKey('date_create') ||
        map.containsKey('date_created') ||
        map.containsKey('created_at');
    final hasTime = map.containsKey('time') || map.containsKey('updated_at');
    final hasStatus = map.containsKey('status') || map.containsKey('state');
    final hasType = map.containsKey('type') || map.containsKey('adjustment_type');

    return hasDate && (hasStatus || hasType || hasTime);
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
      return _extractLossAdjustments(decoded).length;
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

class LossAdjustmentsPage {
  LossAdjustmentsPage({
    required this.entries,
    required this.hasMore,
  });

  final List<LossAdjustmentEntry> entries;
  final bool hasMore;
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class LossAdjustmentEntry {
  LossAdjustmentEntry({
    required this.id,
    required this.type,
    required this.dateCreated,
    required this.lastUpdated,
    required this.status,
    required this.creator,
  });

  factory LossAdjustmentEntry.fromJson(Map<String, dynamic> json) {
    String readString(List<String> keys) => _readString(json, keys) ?? '';
    String readNestedString(String key, List<String> keys) =>
        _readNestedString(json, key, keys) ?? '';

    final creator = readNestedString(
      'creator',
      const ['name', 'full_name', 'username', 'email'],
    );

    final createdBy = readNestedString(
      'created_by',
      const ['name', 'full_name', 'username', 'email'],
    );

    return LossAdjustmentEntry(
      id: readString(const ['id', 'loss_adjustment_id']),
      type: readString(const ['type', 'adjustment_type', 'loss_type']),
      dateCreated:
          readString(const ['date_create', 'date_created', 'created_at']),
      lastUpdated: readString(const ['time', 'updated_at', 'date_update']),
      status: readString(const ['status', 'state']),
      creator: creator.isNotEmpty
          ? creator
          : createdBy.isNotEmpty
              ? createdBy
              : readString(const [
                  'creator',
                  'creator_name',
                  'created_by',
                  'created_by_name',
                  'createdBy',
                  'user_name',
                  'username',
                ]),
    );
  }

  final String id;
  final String type;
  final String dateCreated;
  final String lastUpdated;
  final String status;
  final String creator;

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

class LossAdjustmentsException implements Exception {
  const LossAdjustmentsException(this.message);

  final String message;

  @override
  String toString() => 'LossAdjustmentsException: $message';
}
