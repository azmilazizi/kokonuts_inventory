import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class ExpensesService {
  ExpensesService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://crm.kokonuts.my/api/v1/expenses';
  static const _baseUrlWithoutV1 =
      'https://crm.kokonuts.my/api/expenses'; // Fallback or specific endpoint if needed
  static const _attachmentFieldName = 'file';

  Future<ExpensesPage> fetchExpenses({
    required int page,
    required int perPage,
    required Map<String, String> headers,
    String? fromDate,
    String? toDate,
  }) async {
    final params = {'page': '$page', 'per_page': '$perPage'};
    if (fromDate != null) params['from'] = fromDate;
    if (toDate != null) params['to'] = toDate;

    final uri = Uri.parse(
      _baseUrl,
    ).replace(queryParameters: params);

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw ExpensesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw ExpensesException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ExpensesException('Unable to parse response: $error');
    }

    final expensesList = _extractExpensesList(decoded);
    final expenses = expensesList
        .whereType<Map<String, dynamic>>()
        .map(Expense.fromJson)
        .toList();

    final pagination = _resolvePagination(
      decoded,
      currentPage: page,
      perPage: perPage,
    );

    return ExpensesPage(expenses: expenses, hasMore: pagination.hasMore);
  }

  Future<Expense> getExpense({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw ExpensesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw ExpensesException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ExpensesException('Unable to parse response: $error');
    }

    final expenseJson = _extractExpense(decoded);
    if (expenseJson == null) {
      throw ExpensesException('Response did not include an expense payload.');
    }

    return Expense.fromJson(expenseJson);
  }

  Future<Expense> updateExpense({
    required String id,
    required Map<String, String> headers,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.put(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(data),
      );
    } catch (error) {
      throw ExpensesException('Failed to update expense: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ExpensesException(
        'Update failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ExpensesException('Unable to parse update response: $error');
    }

    // The response structure might be { "status": true, "message": "...", "data": { ... } }
    // or directly the object or wrapped in 'expense'
    final expenseJson = _extractExpense(decoded);
    if (expenseJson == null) {
      throw ExpensesException(
        'Update response did not include an expense payload.',
      );
    }

    return Expense.fromJson(expenseJson);
  }

  Future<Expense> createExpense({
    required Map<String, String> headers,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse(_baseUrl);

    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(data),
      );
    } catch (error) {
      throw ExpensesException('Failed to create expense: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ExpensesException(
        'Create failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ExpensesException('Unable to parse create response: $error');
    }

    final expenseJson = _extractExpense(decoded);
    if (expenseJson == null) {
      throw ExpensesException(
        'Create response did not include an expense payload.',
      );
    }

    return Expense.fromJson(expenseJson);
  }

  Future<void> uploadAttachments({
    required String id,
    required Map<String, String> headers,
    required List<PlatformFile> attachments,
  }) async {
    if (attachments.isEmpty) {
      return;
    }

    final files = await Future.wait(
      attachments.map(_buildMultipartFile),
      eagerError: false,
    );

    final uploadFiles = files.whereType<http.MultipartFile>().toList(
      growable: false,
    );
    if (uploadFiles.isEmpty) {
      return;
    }

    // Assumption: Expense attachment endpoint follows similar pattern
    // POST /api/expenses/{id}/attachment
    // Note: The base URL for expenses is /api/v1/expenses.
    // Adjust if necessary based on backend knowledge.
    final uri = Uri.parse('$_baseUrl/$id/attachment');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'Accept': 'application/json', ...headers})
      ..files.addAll(uploadFiles);

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw ExpensesException('Failed to upload attachments: $error');
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 &&
        resolved.statusCode != 201 &&
        resolved.statusCode != 204) {
      throw ExpensesException(
        'Attachment upload failed with status ${resolved.statusCode}: ${resolved.body}',
      );
    }
  }

  Future<void> deleteAttachments({
    required String id,
    required Map<String, String> headers,
    required List<String> attachmentIds,
  }) async {
    if (attachmentIds.isEmpty) {
      return;
    }

    final uri = Uri.parse('$_baseUrl/$id/attachments');

    final request = http.Request('DELETE', uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...headers,
      })
      ..body = jsonEncode({'ids': attachmentIds});

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw ExpensesException('Failed to delete attachments: $error');
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 && resolved.statusCode != 204) {
      throw ExpensesException(
        'Attachment delete failed with status ${resolved.statusCode}: ${resolved.body}',
      );
    }
  }

  Future<void> deleteExpense({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.delete(
        uri,
        headers: {
          'Accept': 'application/json',
          ...headers,
        },
      );
    } catch (error) {
      throw ExpensesException('Failed to delete expense: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ExpensesException(
        'Delete failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<List<ExpenseCategory>> fetchCategories({
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/categories');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw ExpensesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw ExpensesException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ExpensesException('Unable to parse response: $error');
    }

    final list = _extractItems(decoded);
    return list
        .whereType<Map<String, dynamic>>()
        .map(ExpenseCategory.fromJson)
        .toList();
  }

  Future<http.MultipartFile?> _buildMultipartFile(PlatformFile file) async {
    final sanitizedName = file.name.trim();
    if (sanitizedName.isEmpty) {
      return null;
    }

    if (file.readStream != null) {
      return http.MultipartFile(
        _attachmentFieldName,
        file.readStream!,
        file.size,
        filename: sanitizedName,
      );
    }

    if (file.bytes != null) {
      return http.MultipartFile.fromBytes(
        _attachmentFieldName,
        file.bytes!,
        filename: sanitizedName,
      );
    }

    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      return http.MultipartFile.fromPath(
        _attachmentFieldName,
        path,
        filename: sanitizedName,
      );
    }

    return null;
  }

  List<dynamic> _extractExpensesList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'expenses', 'results', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractExpensesList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }

      for (final value in decoded.values) {
        final list = _extractExpensesList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }
    }

    return const [];
  }

  Map<String, dynamic>? _extractExpense(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikeExpense(decoded)) {
        return decoded;
      }
      const preferredKeys = ['data', 'expense', 'result', 'item'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final candidate = _extractExpense(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }
    return null;
  }

  bool _looksLikeExpense(Map<String, dynamic> map) {
    return map.containsKey('id') &&
        (map.containsKey('expense_name') || map.containsKey('amount'));
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

  Map<String, dynamic>? _findMap(dynamic source, List<String> keys) {
    if (source is Map<String, dynamic>) {
      for (final key in keys) {
        final value = source[key];
        if (value is Map<String, dynamic>) {
          return value;
        }
      }
      for (final value in source.values) {
        final nested = _findMap(value, keys);
        if (nested != null) {
          return nested;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final nested = _findMap(item, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  int _countItems(dynamic source) {
    if (source is List) {
      return source.length;
    }
    if (source is Map<String, dynamic>) {
      return source.values.fold<int>(
        0,
        (count, value) => count + _countItems(value),
      );
    }
    return 0;
  }

  int? _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
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
      final resolved = Expense._stringValue(value);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }
}

class ExpensesPage {
  const ExpensesPage({required this.expenses, required this.hasMore});

  final List<Expense> expenses;
  final bool hasMore;
}

class Expense {
  const Expense({
    required this.id,
    required this.vendor,
    required this.name,
    required this.categoryName,
    required this.amount,
    required this.amountLabel,
    required this.currencySymbol,
    required this.date,
    required this.receipt,
    required this.paymentMode,
    required this.createdBy,
    this.attachments = const [],
  });

  static const _baseUrl = 'https://crm.kokonuts.my/api/v1/expenses';

  factory Expense.fromJson(Map<String, dynamic> json) {
    final vendorData = json['vendor'];
    String? vendorName;
    if (vendorData is Map<String, dynamic>) {
      vendorName =
          _stringValue(vendorData['name']) ??
          _stringValue(vendorData['vendor_name']) ??
          _stringValue(vendorData['company_name']);
    }

    final amountValue = json['amount'] ?? json['total'] ?? json['value'];
    final amount = _parseDouble(amountValue);
    final amountLabel =
        _stringValue(amountValue) ?? amount?.toStringAsFixed(2) ?? '—';

    // Check for 'attachment' filename and construct URL if needed
    String? resolvedReceipt;
    final attachmentName = _stringValue(json['attachment']);
    final expenseId =
        _stringValue(json['id']) ?? _stringValue(json['expenseid']);

    if (attachmentName != null &&
        expenseId != null &&
        attachmentName.isNotEmpty) {
      // Construct standard Perfex CRM attachment URL
      // Format: base_url/uploads/expenses/{id}/{filename}
      // We must encode the filename to handle spaces and special characters.
      final encodedName = Uri.encodeComponent(attachmentName);
      // Parse the base URL to get the scheme and authority
      final baseUri = Uri.parse(_baseUrl);
      final origin = '${baseUri.scheme}://${baseUri.host}';
      resolvedReceipt = '$origin/uploads/expenses/$expenseId/$encodedName';
    }

    final receipt =
        resolvedReceipt ??
        _resolveReceipt(json['receipt']) ??
        _resolveReceipt(json['receipt_url']) ??
        _resolveReceipt(json['receipt_link']) ??
        _resolveReceipt(json['attachments']) ??
        _stringValue(json['receipt']) ??
        _stringValue(json['receipt_url']) ??
        _stringValue(json['receipt_link']);

    final dateString =
        _stringValue(json['expense_date']) ??
        _stringValue(json['date']) ??
        _stringValue(json['created_at']) ??
        _stringValue(json['updated_at']) ??
        '';

    final paymentMode =
        _stringValue(json['payment_mode_name']) ??
        _stringValue(json['payment_mode']) ??
        _stringValue(json['paymentMode']) ??
        _stringValue(json['mode']) ??
        _stringValue(json['payment_method']) ??
        '—';

    final createdBy =
        _resolveCreatedBy(json['created_by']) ??
        _resolveCreatedBy(json['createdBy']) ??
        _resolveCreatedBy(json['staff']) ??
        _resolveCreatedBy(json['user']) ??
        _resolveCreatedBy(json['author']) ??
        _stringValue(json['created_by']) ??
        _stringValue(json['createdBy']) ??
        _stringValue(json['created_by_name']) ??
        _stringValue(json['staff_name']) ??
        _stringValue(json['user_name']) ??
        '—';

    final attachments =
        _extractRelatedCollection(json, const [
              'attachments',
              'files',
              'documents',
            ])
            .whereType<Map<String, dynamic>>()
            .map(ExpenseAttachment.fromJson)
            .toList(growable: false);

    return Expense(
      id: _stringValue(json['id']) ?? '',
      vendor:
          vendorName ??
          _stringValue(json['vendor_name']) ??
          _stringValue(json['vendor']) ??
          '—',
      name:
          _stringValue(json['expense_name']) ??
          _stringValue(json['name']) ??
          _stringValue(json['description']) ??
          _stringValue(json['title']) ??
          '—',
      categoryName:
          _stringValue(json['category_name']) ??
          _stringValue(json['category']) ??
          '—',
      amount: amount,
      amountLabel: amountLabel,
      currencySymbol:
          _stringValue(json['currency_symbol']) ??
          _stringValue(json['currency']) ??
          _stringValue(json['currency_code']) ??
          '',
      date: _parseDateString(dateString),
      receipt: receipt,
      paymentMode: paymentMode,
      createdBy: createdBy,
      attachments: attachments,
    );
  }

  final String id;
  final String vendor;
  final String name;
  final String categoryName;
  final double? amount;
  final String amountLabel;
  final String currencySymbol;
  final DateTime? date;
  final String? receipt;
  final String paymentMode;
  final String createdBy;
  final List<ExpenseAttachment> attachments;

  String get formattedDate {
    final value = date;
    if (value == null) {
      return '—';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
  }

  String get formattedAmount {
    if (amount != null) {
      final formatted = amount!.toStringAsFixed(2);
      if (currencySymbol.isNotEmpty) {
        return '$currencySymbol$formatted';
      }
      return formatted;
    }
    if (currencySymbol.isNotEmpty && amountLabel != '—') {
      return '$currencySymbol$amountLabel';
    }
    return amountLabel;
  }

  /// Returns the amount without any currency symbol attached.
  String get formattedAmountWithoutCurrency {
    if (amount != null) {
      return amount!.toStringAsFixed(2);
    }
    return amountLabel;
  }

  String get receiptLabel {
    final receiptValue = receipt;
    if (receiptValue == null || receiptValue.isEmpty) {
      return '—';
    }
    return 'Available';
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

class ExpenseAttachment {
  const ExpenseAttachment({
    required this.fileName,
    this.description,
    this.downloadUrl,
    this.uploadedBy,
    this.uploadedAt,
    this.sizeLabel,
    this.id,
  });

  factory ExpenseAttachment.fromJson(Map<String, dynamic> json) {
    final fileName =
        Expense._stringValue(json['file_name']) ??
        Expense._stringValue(json['filename']) ??
        Expense._stringValue(json['name']) ??
        Expense._stringValue(json['title']) ??
        'Attachment';

    final id =
        Expense._stringValue(json['id']) ??
        Expense._stringValue(json['attachment_id']) ??
        Expense._stringValue(json['file_id']);

    final description =
        Expense._stringValue(json['description']) ??
        Expense._stringValue(json['note']) ??
        Expense._stringValue(json['remarks']);

    final downloadUrl =
        Expense._stringValue(json['download_url']) ??
        Expense._stringValue(json['url']) ??
        Expense._stringValue(json['file_url']) ??
        Expense._stringValue(json['link']) ??
        Expense._stringValue(json['file_path']) ??
        Expense._stringValue(json['path']);

    final uploadedBy =
        Expense._stringValue(json['uploaded_by']) ??
        Expense._stringValue(json['created_by']) ??
        Expense._stringValue(json['owner']);

    final uploadedAt = _parseDateString(
      Expense._stringValue(json['uploaded_at']) ??
          Expense._stringValue(json['created_at']) ??
          Expense._stringValue(json['date']),
    );

    final sizeLabel =
        Expense._stringValue(json['file_size_formatted']) ??
        Expense._stringValue(json['size_formatted']) ??
        Expense._stringValue(json['file_size']) ??
        Expense._stringValue(json['size']);

    return ExpenseAttachment(
      fileName: fileName,
      description: description,
      downloadUrl: downloadUrl,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt,
      sizeLabel: sizeLabel,
      id: id,
    );
  }

  final String fileName;
  final String? description;
  final String? downloadUrl;
  final String? uploadedBy;
  final DateTime? uploadedAt;
  final String? sizeLabel;
  final String? id;
}

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name});

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: Expense._stringValue(json['id']) ?? '',
      name:
          Expense._stringValue(json['name']) ??
          Expense._stringValue(json['category_name']) ??
          '—',
    );
  }

  final String id;
  final String name;
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class ExpensesException implements Exception {
  const ExpensesException(this.message);

  final String message;

  @override
  String toString() => 'ExpensesException: $message';
}

double? _parseDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final sanitized = value.replaceAll(RegExp(r'[^0-9.,-]'), '');
    final normalized = sanitized.replaceAll(',', '');
    return double.tryParse(normalized);
  }
  return null;
}

DateTime? _parseDateString(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final normalized = trimmed.replaceAll('/', '-');
  final direct = _tryParseDate(normalized);
  if (direct != null) {
    return direct;
  }

  final parts = normalized.split(RegExp(r'\s+'));
  final datePart = parts.first;
  final timePart = parts.length > 1 ? parts.sublist(1).join(' ') : null;

  final segments = datePart.split('-');
  if (segments.length == 3) {
    if (segments[0].length == 4) {
      final isoDate =
          '${segments[0]}-${segments[1].padLeft(2, '0')}-${segments[2].padLeft(2, '0')}';
      final candidate = timePart != null && timePart.isNotEmpty
          ? '$isoDate $timePart'
          : isoDate;
      final parsed = _tryParseDate(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    if (segments[2].length == 4) {
      final day = int.tryParse(segments[0]);
      final month = int.tryParse(segments[1]);
      final year = int.tryParse(segments[2]);
      if (day != null && month != null && year != null) {
        final time = _parseTimeComponents(timePart);
        return DateTime(year, month, day, time[0], time[1], time[2]);
      }
    }
  }

  return null;
}

DateTime? _tryParseDate(String value) {
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}

List<int> _parseTimeComponents(String? value) {
  if (value == null || value.isEmpty) {
    return const [0, 0, 0];
  }
  final cleaned = value.trim();
  final timePart = cleaned.split(RegExp(r'\s+')).first;
  final segments = timePart.split(':');
  final hours = segments.isNotEmpty ? int.tryParse(segments[0]) ?? 0 : 0;
  final minutes = segments.length > 1 ? int.tryParse(segments[1]) ?? 0 : 0;
  final seconds = segments.length > 2 ? int.tryParse(segments[2]) ?? 0 : 0;
  return [hours, minutes, seconds];
}

String? _resolveCreatedBy(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is Map<String, dynamic>) {
    return Expense._stringValue(
          value['name'] ??
              value['full_name'] ??
              value['username'] ??
              value['staff_name'],
        ) ??
        _resolveCreatedBy(value['data']);
  }
  if (value is List) {
    for (final item in value) {
      final resolved = _resolveCreatedBy(item);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
  }
  return Expense._stringValue(value);
}

String? _resolveReceipt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is Map<String, dynamic>) {
    return Expense._stringValue(
          value['url'] ?? value['link'] ?? value['file'] ?? value['path'],
        ) ??
        _resolveReceipt(value['data']);
  }
  if (value is List) {
    for (final item in value) {
      final resolved = _resolveReceipt(item);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
  }
  return null;
}

List<dynamic> _extractRelatedCollection(
  dynamic source,
  List<String> candidateKeys,
) {
  if (source is Map<String, dynamic>) {
    for (final key in candidateKeys) {
      if (source.containsKey(key)) {
        final extracted = _extractItems(source[key]);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
    }

    for (final value in source.values) {
      final extracted = _extractRelatedCollection(value, candidateKeys);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }
  } else if (source is List) {
    for (final element in source) {
      final extracted = _extractRelatedCollection(element, candidateKeys);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }
  }

  return const [];
}

List<dynamic> _extractItems(dynamic source) {
  if (source is List) {
    return source;
  }
  if (source is Map<String, dynamic>) {
    if (source.containsKey('data')) {
      return _extractItems(source['data']);
    }
    if (source.containsKey('items')) {
      return _extractItems(source['items']);
    }
    return source.values
        .map(_extractItems)
        .expand((element) => element)
        .toList();
  }
  return const [];
}
