import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountsService {
  AccountsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/accounts';
  static const _singleAccountBaseUrl =
      'https://crm.kokonuts.my/accounting/api/v1/account/';

  Future<Account> fetchAccountById({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_singleAccountBaseUrl$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw AccountsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw AccountsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw AccountsException('Unable to parse response: $error');
    }

    final data = _findMap(decoded, const ['data', 'account']) ??
        (decoded is Map<String, dynamic> ? decoded : null);

    if (data == null) {
      throw const AccountsException('Response did not include account data.');
    }

    return Account.fromJson(data);
  }

  Future<AccountsPage> fetchAccounts({
    required int page,
    required int perPage,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
      'with_balances': '1',
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw AccountsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw AccountsException(
          'Request failed with status ${response.statusCode}: ${response.body}');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw AccountsException('Unable to parse response: $error');
    }

    final rawList = _extractAccountsList(decoded);
    final allAccounts = rawList
        .whereType<Map<String, dynamic>>()
        .map(Account.fromJson)
        .toList();

    final accounts = allAccounts.where((account) => account.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final pagination = _resolvePagination(decoded, currentPage: page, perPage: perPage);

    final namesById = <String, String>{
      for (final account in allAccounts)
        if (account.id.trim().isNotEmpty) account.id.trim(): account.name,
    };

    return AccountsPage(
      accounts: accounts,
      hasMore: pagination.hasMore,
      namesById: namesById,
    );
  }

  List<dynamic> _extractAccountsList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'accounts', 'results', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractAccountsList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }
      for (final value in decoded.values) {
        final list = _extractAccountsList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }
    }
    return const [];
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
    final list = _extractAccountsList(decoded);
    return list.length;
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
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class AccountsPage {
  AccountsPage({
    required this.accounts,
    required this.hasMore,
    required this.namesById,
  });

  final List<Account> accounts;
  final bool hasMore;
  final Map<String, String> namesById;
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.parentAccountId,
    required this.typeName,
    required this.detailTypeName,
    required this.balance,
    required this.primaryBalance,
    required this.isActive,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    final balance = json['balance'];
    final activeValue = _stringValue(json['active']);
    return Account(
      id: (_stringValue(json['id']) ?? '').trim(),
      name: _stringValue(json['name']) ?? _stringValue(json['id']) ?? '',
      parentAccountId: _stringValue(json['parent_account']),
      typeName: _stringValue(json['account_type_name']) ?? _stringValue(json['account_type']),
      detailTypeName:
          _stringValue(json['detail_type_name']) ?? _stringValue(json['account_detail_type_name']),
      balance: _formatBalance(balance),
      primaryBalance: _formatBalance(json['primary_balance'] ?? balance),
      isActive: activeValue == '1',
    );
  }

  final String id;
  final String name;
  final String? parentAccountId;
  final String? typeName;
  final String? detailTypeName;
  final String balance;
  final String primaryBalance;
  final bool isActive;

  bool get hasParent {
    if (parentAccountId == null) {
      return false;
    }
    final trimmed = parentAccountId!.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return trimmed != '0';
  }

  static String? _stringValue(dynamic value) {
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
}

String _formatBalance(dynamic value) {
  if (value is num) {
    return value.toStringAsFixed(2);
  }
  final stringValue = Account._stringValue(value);
  if (stringValue == null) {
    return '0.00';
  }
  final parsed = double.tryParse(stringValue);
  if (parsed != null) {
    return parsed.toStringAsFixed(2);
  }
  return stringValue;
}

class AccountsException implements Exception {
  const AccountsException(this.message);

  final String message;

  @override
  String toString() => 'AccountsException: $message';
}
