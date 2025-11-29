import 'dart:convert';
import 'package:http/http.dart' as http;

class OverviewService {
  OverviewService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/money_out_summary';
  static const _expensesByTypeUrl = 'https://crm.kokonuts.my/dashboard/expenses_percentage_by_type';

  Future<MoneyOutSummary> fetchMoneyOutSummary({
    required String startDate,
    required String endDate,
    required String type,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
      'type': type,
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw OverviewException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw OverviewException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw OverviewException('Unable to parse response: $error');
    }

    // Attempt to extract the data payload if wrapped
    dynamic data = decoded;
    // Check key existence on decoded if it's a map
    if (decoded is Map) {
      if (decoded.containsKey('data')) {
        data = decoded['data'];
      } else if (decoded.containsKey('summary')) {
        data = decoded['summary'];
      } else if (decoded.containsKey('result')) {
        data = decoded['result'];
      }
    }

    return MoneyOutSummary.fromJson(data);
  }

  Future<ExpensesPieChartData> fetchExpensesPercentageByType({
    required String startDate,
    required String endDate,
    required String type,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(_expensesByTypeUrl).replace(queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
      'type': type,
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw OverviewException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw OverviewException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw OverviewException('Unable to parse response: $error');
    }

    return ExpensesPieChartData.fromJson(decoded);
  }
}

class TransactionCategorySummary {
  final int count;
  final String total;

  const TransactionCategorySummary({
    required this.count,
    required this.total,
  });

  factory TransactionCategorySummary.empty() {
    return const TransactionCategorySummary(count: 0, total: '0.00');
  }
}

class MoneyOutSummary {
  final Map<String, dynamic> rawData;

  const MoneyOutSummary(this.rawData);

  factory MoneyOutSummary.fromJson(dynamic json) {
    if (json is Map) {
       // Convert to Map<String, dynamic> safely
       try {
         return MoneyOutSummary(Map<String, dynamic>.from(json));
       } catch (_) {
         // Fallback if conversion fails (e.g. keys are not strings, though unlikely for JSON)
         return const MoneyOutSummary({});
       }
    }
    return const MoneyOutSummary({});
  }

  String get totalSpent {
    double? val;
    if (rawData.containsKey('grand_total')) {
      val = _parseDouble(rawData['grand_total']);
    } else if (rawData.containsKey('total_spent')) {
      val = _parseDouble(rawData['total_spent']);
    } else if (rawData.containsKey('total')) {
      val = _parseDouble(rawData['total']);
    }

    return val != null ? val.toStringAsFixed(2) : '0.00';
  }

  TransactionCategorySummary get purchaseOrders => _parseCategory(['purchase_orders', 'purchase_order']);
  TransactionCategorySummary get expenses => _parseCategory(['expenses', 'expense']);
  TransactionCategorySummary get bills => _parseCategory(['bills', 'bill']);

  TransactionCategorySummary _parseCategory(List<String> keys) {
    // Check if 'totals' object exists and search inside it first
    Map<String, dynamic>? searchScope;
    if (rawData.containsKey('totals') && rawData['totals'] is Map) {
      try {
        searchScope = Map<String, dynamic>.from(rawData['totals']);
      } catch (_) {
        searchScope = rawData;
      }
    } else {
      searchScope = rawData;
    }

    dynamic categoryData;
    for (final key in keys) {
      if (searchScope!.containsKey(key)) {
        categoryData = searchScope[key];
        break;
      }
    }

    // If not found in 'totals', fallback to searching in root (backward compatibility)
    if (categoryData == null && searchScope != rawData) {
       for (final key in keys) {
        if (rawData.containsKey(key)) {
          categoryData = rawData[key];
          break;
        }
      }
    }

    if (categoryData is Map) {
      // Safely access keys on generic Map
      final count = _parseInt(categoryData['count']) ?? _parseInt(categoryData['number_of_transaction']) ?? 0;

      double? amount;
      if (categoryData.containsKey('amount')) {
        amount = _parseDouble(categoryData['amount']);
      } else if (categoryData.containsKey('total')) {
        amount = _parseDouble(categoryData['total']);
      } else if (categoryData.containsKey('total_spent')) {
        amount = _parseDouble(categoryData['total_spent']);
      }

      final totalStr = amount != null ? amount.toStringAsFixed(2) : '0.00';

      return TransactionCategorySummary(count: count, total: totalStr);
    }

    return TransactionCategorySummary.empty();
  }

  /// Returns a list of key-value pairs for display.
  /// This attempts to format keys and values into a readable format.
  List<MapEntry<String, String>> get displayItems {
    final entries = <MapEntry<String, String>>[];
    for (final key in rawData.keys) {
      // format key: replace underscores with spaces, capitalize
      final formattedKey = key.replaceAll('_', ' ').capitalize();
      final value = rawData[key];
      entries.add(MapEntry(formattedKey, value.toString()));
    }
    return entries;
  }
}

class ExpensesPieChartData {
  final List<ChartItem> purchaseOrderByItem;
  final List<ChartItem> expensesByCategory;
  final List<ChartItem> billByAccount;

  const ExpensesPieChartData({
    required this.purchaseOrderByItem,
    required this.expensesByCategory,
    required this.billByAccount,
  });

  factory ExpensesPieChartData.empty() {
    return const ExpensesPieChartData(
      purchaseOrderByItem: [],
      expensesByCategory: [],
      billByAccount: [],
    );
  }

  factory ExpensesPieChartData.fromJson(dynamic json) {
    if (json is! Map) return ExpensesPieChartData.empty();

    // Check for "data" wrapper as seen in the user provided example
    dynamic data = json;
    if (json.containsKey('data') && json['data'] is Map) {
      data = json['data'];
    }

    return ExpensesPieChartData(
      purchaseOrderByItem: _parseList(data['purchase_orders']),
      expensesByCategory: _parseList(data['expense_categories']),
      billByAccount: _parseList(data['bill_debit_accounts']),
    );
  }

  static List<ChartItem> _parseList(dynamic list) {
    if (list is! List) return [];

    final tempItems = list.map((e) {
      if (e is! Map) return const ChartItem(label: '', value: 0, percentage: 0);

      // Explicit mapping as per API response structure
      // e.g. { "name": "Coconut Juice", "value": "864.00" }
      String label = '';
      if (e.containsKey('name')) {
        label = e['name'].toString();
      } else {
        // Fallback to ChartItem logic if name is missing
        return ChartItem.fromJson(e);
      }

      double value = 0;
      if (e.containsKey('value')) {
        value = double.tryParse(e['value'].toString()) ?? 0;
      } else {
        // Fallback
        return ChartItem.fromJson(e);
      }

      return ChartItem(label: label, value: value, percentage: 0);
    }).toList();

    final totalValue = tempItems.fold(0.0, (sum, item) => sum + item.value);

    if (totalValue == 0) return tempItems;

    return tempItems.map((item) {
      final percentage = (item.value / totalValue) * 100;
      return ChartItem(
        label: item.label,
        value: item.value,
        percentage: percentage,
      );
    }).toList();
  }
}

class ChartItem {
  final String label;
  final double value;
  final double percentage;

  const ChartItem({
    required this.label,
    required this.value,
    required this.percentage,
  });

  factory ChartItem.fromJson(dynamic json) {
    if (json is! Map) return const ChartItem(label: '', value: 0, percentage: 0);

    // Try various keys for label
    String label = '';
    if (json.containsKey('name')) label = json['name'].toString();
    else if (json.containsKey('label')) label = json['label'].toString();
    else if (json.containsKey('category')) label = json['category'].toString();
    else if (json.containsKey('account')) label = json['account'].toString();
    else if (json.containsKey('item_name')) label = json['item_name'].toString();

    // Try various keys for value/amount
    double value = 0;
    if (json.containsKey('amount')) value = _parseDouble(json['amount']) ?? 0;
    else if (json.containsKey('value')) value = _parseDouble(json['value']) ?? 0;
    else if (json.containsKey('total')) value = _parseDouble(json['total']) ?? 0;

    // Try various keys for percentage
    double percentage = 0;
    if (json.containsKey('percentage')) percentage = _parseDouble(json['percentage']) ?? 0;
    else if (json.containsKey('percent')) percentage = _parseDouble(json['percent']) ?? 0;

    return ChartItem(label: label, value: value, percentage: percentage);
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

double? _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

class OverviewException implements Exception {
  const OverviewException(this.message);
  final String message;
  @override
  String toString() => 'OverviewException: $message';
}
