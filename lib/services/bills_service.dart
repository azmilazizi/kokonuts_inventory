import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class BillsService {
  BillsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/bills';
  static const _vendorBaseUrl = 'https://crm.kokonuts.my/purchase/api/v1/vendors';
  static const _billBaseUrl = 'https://crm.kokonuts.my/accounting/api/v1/bill';
  static const _attachmentFieldName = 'file';

  final Map<String, String?> _vendorCache = {};

  Future<BillsPage> fetchBills({
    required int page,
    required int perPage,
    required Map<String, String> headers,
    String? fromDate,
    String? toDate,
  }) async {
    final params = {'page': '$page', 'per_page': '$perPage'};
    if (fromDate != null) params['from'] = fromDate;
    if (toDate != null) params['to'] = toDate;

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse response: $error');
    }

    final billsList = _extractBillsList(decoded);
    final bills = billsList
        .whereType<Map<String, dynamic>>()
        .map(Bill.fromJson)
        .toList();

    final pagination = _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return BillsPage(bills: bills, hasMore: pagination.hasMore);
  }

  Future<Bill> getBill({
    required String id,
    required Map<String, String> headers,
  }) async {
    // The base URL is /api/v1/bills (plural).
    // The single resource endpoint is /accounting/api/v1/bill/{id} (singular).
    // We construct the URL directly as requested.
    final uri = Uri.parse('https://crm.kokonuts.my/accounting/api/v1/bill/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse response: $error');
    }

    // Usually single resource response is wrapped in `data` or just the object
    // or `{ "status": true, "data": ... }`
    final billJson = _extractBill(decoded);
    if (billJson == null) {
      throw BillsException('Response did not include a bill payload.');
    }

    return Bill.fromJson(billJson);
  }

  Future<Bill> createBill({
    required Map<String, String> headers,
    required Map<String, dynamic> data,
  }) async {
    http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_baseUrl),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(data),
      );
    } catch (error) {
      throw BillsException('Failed to create bill: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BillsException(
        'Create failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse create response: $error');
    }

    final billJson = _extractBill(decoded);
    if (billJson == null) {
      throw BillsException('Create response did not include a bill payload.');
    }

    return Bill.fromJson(billJson);
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

    final uri = Uri.parse('$_billBaseUrl/$id/attachment');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'Accept': 'application/json', ...headers})
      ..files.addAll(uploadFiles);

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw BillsException('Failed to upload attachments: $error');
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 &&
        resolved.statusCode != 201 &&
        resolved.statusCode != 204) {
      throw BillsException(
        'Attachment upload failed with status ${resolved.statusCode}: ${resolved.body}',
      );
    }
  }

  Future<List<BillPayment>> fetchBillPayments({
    required String billId,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_billBaseUrl/$billId/payments');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse response: $error');
    }

    final paymentsJson = _extractItems(decoded)
        .whereType<Map<String, dynamic>>()
        .map(BillPayment.fromJson)
        .toList();

    if (paymentsJson.isEmpty && decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return _extractItems(data)
            .whereType<Map<String, dynamic>>()
            .map(BillPayment.fromJson)
            .toList();
      }
    }

    return paymentsJson;
  }

  Future<BillAttachment> fetchPaymentAttachment({
    required String billId,
    required String paymentId,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(
      '$_billBaseUrl/$billId/payment/${paymentId.trim()}/attachment',
    );

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/json',
          ...headers,
        },
      );
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse response: $error');
    }

    Map<String, dynamic>? attachmentJson;
    if (decoded is Map<String, dynamic>) {
      attachmentJson = _findMap(decoded, const ['data', 'attachment', 'file']);
      attachmentJson ??=
          decoded['data'] is Map<String, dynamic> ? decoded['data'] : decoded;
    }

    if (attachmentJson == null) {
      final extracted =
          _extractItems(decoded).whereType<Map<String, dynamic>>().toList();
      if (extracted.isNotEmpty) {
        attachmentJson = extracted.first;
      }
    }

    if (attachmentJson == null) {
      throw BillsException('Response did not include an attachment payload.');
    }

    return BillAttachment.fromJson(attachmentJson);
  }

  Future<BillAttachment?> _uploadPaymentAttachment({
    required String billId,
    required String paymentId,
    required Map<String, String> headers,
    required PlatformFile attachment,
    String? description,
  }) async {
    final file = await _buildMultipartFile(attachment);
    if (file == null) {
      return null;
    }

    final uri = Uri.parse('$_billBaseUrl/$billId/payment/$paymentId/attachment');

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({'Accept': 'application/json', ...headers})
      ..files.add(file);

    final sanitizedDescription = description?.trim();
    if (sanitizedDescription != null && sanitizedDescription.isNotEmpty) {
      request.fields['description'] = sanitizedDescription;
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw BillsException('Failed to upload payment attachment: $error');
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 &&
        resolved.statusCode != 201 &&
        resolved.statusCode != 204) {
      throw BillsException(
        'Payment attachment upload failed with status ${resolved.statusCode}: ${resolved.body}',
      );
    }

    if (resolved.body.isEmpty) {
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(resolved.body);
    } catch (_) {
      return null;
    }

    Map<String, dynamic>? attachmentJson;
    if (decoded is Map<String, dynamic>) {
      attachmentJson = _findMap(decoded, const ['data', 'attachment', 'file']);
      attachmentJson ??=
          decoded['data'] is Map<String, dynamic> ? decoded['data'] : decoded;
    }

    if (attachmentJson == null) {
      final extracted =
          _extractItems(decoded).whereType<Map<String, dynamic>>().toList();
      if (extracted.isNotEmpty) {
        attachmentJson = extracted.first;
      }
    }

    return attachmentJson == null
        ? null
        : BillAttachment.fromJson(attachmentJson);
  }

  Future<BillPayment> createBillPayment({
    required String billId,
    required Map<String, String> headers,
    required String vendor,
    required DateTime paymentDate,
    List<Map<String, dynamic>> paymentLines = const [],
    String? paymentAccountId,
    String? depositAccountId,
    String? referenceNo,
    PlatformFile? attachment,
    String? attachmentDescription,
  }) async {
    final uri = Uri.parse('$_billBaseUrl/$billId/payment');

    final payload = <String, dynamic>{
      'date': DateFormat('yyyy-MM-dd').format(paymentDate),
    };

    final sanitizedVendorId = vendor.trim();
    if (sanitizedVendorId.isNotEmpty) {
      payload['vendor'] = sanitizedVendorId;
    }

    if (paymentLines.isNotEmpty) {
      payload['payment_lines'] = paymentLines;
    }

    final sanitizedReference = referenceNo?.trim();
    if (sanitizedReference != null && sanitizedReference.isNotEmpty) {
      payload['reference_no'] = sanitizedReference;
    }

    final sanitizedPaymentAccount = paymentAccountId?.trim();
    if (sanitizedPaymentAccount != null && sanitizedPaymentAccount.isNotEmpty) {
      payload['account_credit'] = sanitizedPaymentAccount;
    }

    final sanitizedDepositAccount = depositAccountId?.trim();
    if (sanitizedDepositAccount != null && sanitizedDepositAccount.isNotEmpty) {
      payload['account_debit'] = sanitizedDepositAccount;
    }

    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(payload),
      );
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BillsException(
        'Payment request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse payment response: $error');
    }

    final paymentJson = _extractPayment(decoded);
    if (paymentJson == null) {
      throw BillsException('Payment response did not include a payment payload.');
    }

    var payment = BillPayment.fromJson(paymentJson);

    if (attachment != null) {
      final paymentId = payment.payBillId?.trim().isNotEmpty == true
          ? payment.payBillId!.trim()
          : payment.id.trim();

      if (paymentId.isEmpty) {
        throw BillsException(
          'Payment response did not include a payment identifier for attachment upload.',
        );
      }

      final uploadedAttachment = await _uploadPaymentAttachment(
        billId: billId,
        paymentId: paymentId,
        headers: headers,
        attachment: attachment,
        description: attachmentDescription,
      );

      if (uploadedAttachment != null) {
        payment = payment.copyWith(attachment: uploadedAttachment);
      }
    }

    return payment;
  }

  Future<void> deleteBillPayment({
    required String billId,
    required String paymentId,
    required Map<String, String> headers,
  }) async {
    final normalizedPaymentId = paymentId.trim();

    final request = http.Request(
      'DELETE',
      Uri.parse('$_billBaseUrl/$billId/payment/$normalizedPaymentId'),
    )
      ..headers.addAll({
        'Accept': 'application/json',
        ...headers,
      });

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 && resolved.statusCode != 204) {
      throw BillsException(
        'Payment delete failed with status ${resolved.statusCode}: ${resolved.body}',
      );
    }
  }

  Future<void> deleteBill({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.delete(uri, headers: headers);
    } catch (error) {
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw BillsException(
        'Delete request failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<String?> resolveVendorName({
    required String vendorId,
    required Map<String, String> headers,
  }) async {
    if (vendorId.isEmpty) {
      return null;
    }

    if (_vendorCache.containsKey(vendorId)) {
      return _vendorCache[vendorId];
    }

    final uri = Uri.parse('$_vendorBaseUrl/$vendorId');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw BillsException('Failed to load vendor: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Vendor request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse vendor response: $error');
    }

    String? vendorName;
    if (decoded is Map<String, dynamic>) {
      vendorName = _stringValue(decoded['vendor_name']) ??
          _stringValue(decoded['company']) ??
          _stringValue(decoded['company_name']) ??
          _stringValue(decoded['name']);
      if (vendorName == null) {
        final candidate = _findMap(decoded, const ['data', 'vendor']);
        if (candidate != null) {
          vendorName = _stringValue(candidate['vendor_name']) ??
              _stringValue(candidate['company']) ??
              _stringValue(candidate['company_name']) ??
              _stringValue(candidate['name']);
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          vendorName = _stringValue(item['vendor_name']) ??
              _stringValue(item['company']) ??
              _stringValue(item['company_name']) ??
              _stringValue(item['name']);
          if (vendorName != null && vendorName.isNotEmpty) {
            break;
          }
        }
      }
    }

    _vendorCache[vendorId] = vendorName;
    return vendorName;
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

  List<dynamic> _extractBillsList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'bills', 'results', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractBillsList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }

      for (final value in decoded.values) {
        final list = _extractBillsList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }
    }

    return const [];
  }

  Map<String, dynamic>? _extractPayment(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikePayment(decoded)) {
        return decoded;
      }

      const preferredKeys = [
        'data',
        'payment',
        'result',
        'item',
        'bill_payment',
        'payment_data',
      ];
      for (final key in preferredKeys) {
        final candidate = _extractPayment(decoded[key]);
        if (candidate != null) {
          return candidate;
        }
      }

      for (final value in decoded.values) {
        final nested = _extractPayment(value);
        if (nested != null) {
          return nested;
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        final candidate = _extractPayment(item);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _extractBill(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikeBill(decoded)) {
        return decoded;
      }
      const preferredKeys = ['data', 'bill', 'result', 'item'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final candidate = _extractBill(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }
    return null;
  }

  bool _looksLikeBill(Map<String, dynamic> map) {
    return map.containsKey('id') &&
        (map.containsKey('bill_date') || map.containsKey('date') || map.containsKey('amount'));
  }

  bool _looksLikePayment(Map<String, dynamic> map) {
    return map.containsKey('payment_id') ||
        map.containsKey('paymentId') ||
        map.containsKey('payment_no') ||
        (map.containsKey('id') &&
            (map.containsKey('payment_amount') ||
                map.containsKey('paymentAmount') ||
                map.containsKey('amount') ||
                map.containsKey('amount_paid') ||
                map.containsKey('amountPaid')));
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

  int _countItems(dynamic decoded) {
    final list = _extractBillsList(decoded);
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

class BillsPage {
  const BillsPage({required this.bills, required this.hasMore});

  final List<Bill> bills;
  final bool hasMore;
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class BillsException implements Exception {
  BillsException(this.message);

  final String message;

  @override
  String toString() => 'BillsException: $message';
}

class Bill {
  const Bill({
    required this.id,
    required this.vendorId,
    this.vendorName,
    required this.billDate,
    required this.dueDate,
    required this.status,
    required this.totalAmount,
    required this.currencySymbol,
    this.attachments = const [],
    this.creditAccountId,
    this.debitAccountId,
    this.creditAccount,
    this.debitAccount,
    this.datePaid,
    this.totalPaid,
    this.totalDue,
    this.payments = const [],
    this.debitAccounts = const [],
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    final totalValue = json['amount'] ?? json['total'];
    final statusValue = json['status'];

    final attachments = _extractRelatedCollection(json, const [
          'attachments',
          'files',
          'documents',
        ])
        .whereType<Map<String, dynamic>>()
        .map(BillAttachment.fromJson)
        .toList();

    final attachmentUrl = _stringValue(json['attachment']);
    if (attachmentUrl != null && attachmentUrl.trim().isNotEmpty) {
      attachments.add(
        BillAttachment(
          fileName: _fileNameFromPath(attachmentUrl),
          downloadUrl: attachmentUrl,
        ),
      );
    }

    final payments = _extractRelatedCollection(json, const [
          'payments',
          'payment_history',
          'paymentHistory',
          'payment_logs',
          'paymentRecords',
          'payment_details',
        ])
        .whereType<Map<String, dynamic>>()
        .map(BillPayment.fromJson)
        .toList(growable: false);

    final creditAccountRaw = json['credit_account'] ?? json['creditAccount'];
    final debitAccountRaw = json['debit_account'] ?? json['debitAccount'];

    final creditAccountId = _accountIdFromValue(creditAccountRaw) ??
        _stringValue(json['credit_account_id']) ??
        _stringValue(json['creditAccountId']);
    final debitAccountId = _accountIdFromValue(debitAccountRaw) ??
        _stringValue(json['debit_account_id']) ??
        _stringValue(json['debitAccountId']);
    final hasStructuredCreditAccount =
        creditAccountRaw is Iterable || creditAccountRaw is Map<String, dynamic>;
    final hasStructuredDebitAccount =
        debitAccountRaw is Iterable || debitAccountRaw is Map<String, dynamic>;

    final debitAccounts = <BillAccountLine>[];
    if (debitAccountRaw is Iterable) {
      for (final entry in debitAccountRaw) {
        if (entry is Map<String, dynamic>) {
          debitAccounts.add(BillAccountLine.fromJson(entry));
        }
      }
    }

    return Bill(
      id: _stringValue(json['id']) ?? '',
      vendorId: _stringValue(json['vendor_id']) ??
          _stringValue(json['vendor']) ??
          '',
      vendorName: _stringValue(json['vendor_name']),
      billDate: _parseDate(_stringValue(json['date'])),
      dueDate: _parseDate(_stringValue(json['due_date'])) ??
          _parseDate(_stringValue(json['date'])),
      status: BillStatus.fromCode(_parseInt(statusValue)),
      totalAmount: _parseDouble(totalValue),
      currencySymbol: _stringValue(json['currency_symbol']) ??
          _stringValue(json['currency']) ??
          '',
      attachments: attachments,
      creditAccountId: creditAccountId,
      debitAccountId: debitAccountId,
      creditAccount: _accountNameFromValue(creditAccountRaw) ??
          _stringValue(json['credit_account_name']) ??
          _stringValue(json['creditAccountName']) ??
          (hasStructuredCreditAccount
              ? null
              : _stringValue(json['credit_account']) ??
                  _stringValue(json['creditAccount'])),
      debitAccount: _accountNameFromValue(debitAccountRaw) ??
          _stringValue(json['debit_account_name']) ??
          _stringValue(json['debitAccountName']) ??
          (hasStructuredDebitAccount
              ? null
              : _stringValue(json['debit_account']) ??
                  _stringValue(json['debitAccount'])),
      datePaid: _parseDate(_stringValue(json['date_paid'])),
      totalPaid: _parseDouble(json['total_paid'] ?? json['paid']),
      totalDue: _parseDouble(json['total_due'] ?? json['due']),
      payments: payments,
      debitAccounts: debitAccounts,
    );
  }

  final String id;
  final String vendorId;
  final String? vendorName;
  final DateTime? billDate;
  final DateTime? dueDate;
  final BillStatus status;
  final double? totalAmount;
  final String currencySymbol;
  final List<BillAttachment> attachments;
  final String? creditAccountId;
  final String? debitAccountId;
  final String? creditAccount;
  final String? debitAccount;
  final DateTime? datePaid;
  final double? totalPaid;
  final double? totalDue;
  final List<BillPayment> payments;
  final List<BillAccountLine> debitAccounts;

  String get formattedDate {
    final date = billDate;
    if (date == null) {
      return '-';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
  }

  String get formattedDueDate {
    final date = dueDate;
    if (date == null) {
      return '-';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
  }

  String get totalLabel {
    final amount = totalAmount;
    return _formatCurrency(amount);
  }

  double get resolvedTotalPaid => totalPaid ?? 0.0;

  double? get resolvedTotalDue {
    if (totalDue != null) {
      return totalDue;
    }

    final amount = totalAmount;
    if (amount == null) {
      return null;
    }

    return amount - resolvedTotalPaid;
  }

  String get totalPaidLabel => _formatCurrency(resolvedTotalPaid);

  String get totalDueLabel => _formatCurrency(resolvedTotalDue);

  String formatCurrency(double? amount) => _formatCurrency(amount);

  String _formatCurrency(double? amount) {
    if (amount == null) {
      return '-';
    }
    final formatted = amount.toStringAsFixed(2);
    if (currencySymbol.isNotEmpty && currencySymbol.toLowerCase() != '0') {
      return '$currencySymbol $formatted';
    }
    return formatted;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is double) {
      return value.toInt();
    }
    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  static String? _accountIdFromValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Iterable) {
      for (final entry in value) {
        final id = _accountIdFromValue(entry);
        if (id != null) {
          return id;
        }
      }
      return null;
    }
    if (value is Map<String, dynamic>) {
      return _stringValue(value['account']) ??
          _stringValue(value['id']) ??
          _stringValue(value['account_id']);
    }
    if (value is num || value is String) {
      return _stringValue(value);
    }
    return null;
  }

  static String? _accountNameFromValue(dynamic value) {
    if (value is Iterable) {
      for (final entry in value) {
        final name = _accountNameFromValue(entry);
        if (name != null) {
          return name;
        }
      }
      return null;
    }
    if (value is Map<String, dynamic>) {
      return _stringValue(value['name']) ??
          _stringValue(value['account_name']) ??
          _stringValue(value['label']);
    }
    return _stringValue(value);
  }
}

class BillAccountLine {
  const BillAccountLine({
    required this.id,
    this.billId,
    this.type,
    this.account,
    this.amount,
    this.itemId,
    this.qty,
    this.cost,
    this.description,
  });

  factory BillAccountLine.fromJson(Map<String, dynamic> json) {
    return BillAccountLine(
      id: _stringValue(json['id']) ?? '',
      billId: _stringValue(json['bill_id']) ?? _stringValue(json['billId']),
      type: _stringValue(json['type']),
      account: _stringValue(json['account']),
      amount: Bill._parseDouble(json['amount']),
      itemId: _stringValue(json['item_id']) ?? _stringValue(json['itemId']),
      qty: _stringValue(json['qty']),
      cost: _stringValue(json['cost']),
      description: _stringValue(json['description']),
    );
  }

  final String id;
  final String? billId;
  final String? type;
  final String? account;
  final double? amount;
  final String? itemId;
  final String? qty;
  final String? cost;
  final String? description;
}

class BillAttachment {
  const BillAttachment({
    required this.fileName,
    this.description,
    this.downloadUrl,
    this.uploadedBy,
    this.uploadedAt,
    this.sizeLabel,
    this.id,
    this.paymentId,
    this.paymentDate,
    this.amount,
  });

  factory BillAttachment.fromJson(Map<String, dynamic> json) {
    final fileName =
        _stringValue(json['file_name']) ??
        _stringValue(json['filename']) ??
        _stringValue(json['name']) ??
        _stringValue(json['title']) ??
        'Attachment';

    final id =
        _stringValue(json['id']) ??
        _stringValue(json['attachment_id']) ??
        _stringValue(json['file_id']);

    final description =
        _stringValue(json['description']) ??
        _stringValue(json['note']) ??
        _stringValue(json['remarks']);

    final downloadUrl =
        _stringValue(json['download_url']) ??
        _stringValue(json['url']) ??
        _stringValue(json['file_url']) ??
        _stringValue(json['link']) ??
        _stringValue(json['file_path']) ??
        _stringValue(json['path']);

    final uploadedBy =
        _stringValue(json['uploaded_by']) ??
        _stringValue(json['created_by']) ??
        _stringValue(json['owner']);

    final uploadedAt = Bill._parseDate(
      _stringValue(json['uploaded_at']) ??
          _stringValue(json['created_at']) ??
          _stringValue(json['date']),
    );

    final sizeLabel =
        _stringValue(json['file_size_formatted']) ??
        _stringValue(json['size_formatted']) ??
        _stringValue(json['file_size']) ??
        _stringValue(json['size']);

    final paymentDate = Bill._parseDate(
      _stringValue(json['payment_date']) ??
          _stringValue(json['date']) ??
          _stringValue(json['uploaded_at']),
    );

    final amount = Bill._parseDouble(
      json['payment_amount'] ??
          json['amount'] ??
          json['total_amount'] ??
          json['total'],
    );

    return BillAttachment(
      fileName: fileName,
      description: description,
      downloadUrl: downloadUrl,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt,
      sizeLabel: sizeLabel,
      id: id,
      paymentId: _stringValue(json['payment_id']) ??
          _stringValue(json['paymentId']) ??
          _stringValue(json['id']),
      paymentDate: paymentDate,
      amount: amount,
    );
  }

  final String fileName;
  final String? description;
  final String? downloadUrl;
  final String? uploadedBy;
  final DateTime? uploadedAt;
  final String? sizeLabel;
  final String? id;
  final String? paymentId;
  final DateTime? paymentDate;
  final double? amount;
}

class BillPayment {
  const BillPayment({
    required this.id,
    this.payBillId,
    this.payBillItemPaidId,
    this.date,
    this.paymentAccount,
    this.paymentAccountId,
    this.depositAccountId,
    this.referenceNo,
    this.amount,
    this.attachment,
    this.attachmentFileName,
    this.hasEmptyAttachment = false,
    this.hasAttachmentString = false,
  });

  factory BillPayment.fromJson(Map<String, dynamic> json) {
    final rawAttachment = json['attachment'];
    final attachment = _findMap(json, const ['attachment', 'file', 'document']);
    final hasAttachmentString =
        rawAttachment is String && rawAttachment.trim().isNotEmpty;
    final hasEmptyAttachment =
        rawAttachment is String && rawAttachment.trim().isEmpty;

    final payBillItemPaid = _extractItems(json['pay_bill_item_paid'])
        .whereType<Map<String, dynamic>>()
        .toList();

    String? attachmentFileName;
    if (rawAttachment is String && rawAttachment.trim().isNotEmpty) {
      attachmentFileName = rawAttachment.trim();
    } else if (attachment is Map<String, dynamic>) {
      attachmentFileName =
          _stringValue(attachment['file_name']) ??
              _stringValue(attachment['filename']) ??
              _stringValue(attachment['name']) ??
              _stringValue(attachment['title']);
    }

    return BillPayment(
      id: _stringValue(json['id']) ??
          _stringValue(json['payment_id']) ??
          _stringValue(json['payment_no']) ??
          _stringValue(json['paymentId']) ??
          '',
      payBillId:
          _stringValue(json['pay_bill_id']) ?? _stringValue(json['payBillId']),
      payBillItemPaidId: payBillItemPaid.isNotEmpty
          ? _stringValue(payBillItemPaid.first['pay_bill_id'])
          : null,
      date: Bill._parseDate(
        _stringValue(json['payment_date']) ??
            _stringValue(json['date']) ??
            _stringValue(json['created_at']),
      ),
      paymentAccountId:
          _stringValue(json['account_credit']) ?? _stringValue(json['accountCredit']),
      depositAccountId:
          _stringValue(json['account_debit']) ?? _stringValue(json['accountDebit']),
      referenceNo: _stringValue(json['reference_no']) ??
          _stringValue(json['referenceNo']) ??
          _stringValue(json['reference']),
      paymentAccount: _stringValue(json['payment_account']) ??
          _stringValue(json['paymentAccount']) ??
          _stringValue(json['account_name']) ??
          _stringValue(json['accountName']) ??
          _stringValue(json['account']),
      amount: Bill._parseDouble(json['payment_amount'] ?? json['amount']),
      attachment:
          attachment == null ? null : BillAttachment.fromJson(attachment),
      attachmentFileName: attachmentFileName,
      hasEmptyAttachment: hasEmptyAttachment,
      hasAttachmentString: hasAttachmentString,
    );
  }

  final String id;
  final String? payBillId;
  final String? payBillItemPaidId;
  final DateTime? date;
  final String? paymentAccount;
  final String? paymentAccountId;
  final String? depositAccountId;
  final String? referenceNo;
  final double? amount;
  final BillAttachment? attachment;
  final String? attachmentFileName;
  final bool hasEmptyAttachment;
  final bool hasAttachmentString;

  BillPayment copyWith({
    String? id,
    String? payBillId,
    String? payBillItemPaidId,
    DateTime? date,
    String? paymentAccount,
    String? paymentAccountId,
    String? depositAccountId,
    String? referenceNo,
    double? amount,
    BillAttachment? attachment,
    String? attachmentFileName,
    bool? hasEmptyAttachment,
    bool? hasAttachmentString,
  }) {
    return BillPayment(
      id: id ?? this.id,
      payBillId: payBillId ?? this.payBillId,
      payBillItemPaidId: payBillItemPaidId ?? this.payBillItemPaidId,
      date: date ?? this.date,
      paymentAccount: paymentAccount ?? this.paymentAccount,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      depositAccountId: depositAccountId ?? this.depositAccountId,
      referenceNo: referenceNo ?? this.referenceNo,
      amount: amount ?? this.amount,
      attachment: attachment ?? this.attachment,
      attachmentFileName: attachmentFileName ?? this.attachmentFileName,
      hasEmptyAttachment: hasEmptyAttachment ?? this.hasEmptyAttachment,
      hasAttachmentString: hasAttachmentString ?? this.hasAttachmentString,
    );
  }
}

String? _stringValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

String _fileNameFromPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'Attachment';
  }

  final parsed = Uri.tryParse(trimmed);
  final segments =
      parsed?.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments != null && segments.isNotEmpty) {
    return segments.last;
  }

  final parts = trimmed.split(RegExp(r'[\\/]'));
  if (parts.isNotEmpty) {
    final candidate = parts.last.trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
  }

  return 'Attachment';
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

class BillStatus {
  const BillStatus._(this.code, this.label);

  final int code;
  final String label;

  static const unpaid = BillStatus._(0, 'Unpaid');
  static const notApproved = BillStatus._(1, 'Not Approved');
  static const paid = BillStatus._(2, 'Paid');

  static const _all = [unpaid, notApproved, paid];

  static BillStatus fromCode(int? code) {
    if (code == null) {
      return unpaid;
    }
    return _all.firstWhere((status) => status.code == code, orElse: () => unpaid);
  }
}
