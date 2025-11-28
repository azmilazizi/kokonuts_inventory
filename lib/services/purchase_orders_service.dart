import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class PurchaseOrdersService {
  PurchaseOrdersService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_orders';
  static const _singleOrderBaseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order';
  static const _attachmentsBaseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order';
  static const _attachmentFieldName = 'file';

  Future<void> createPayments({
    required String id,
    required Map<String, String> headers,
    required List<CreatePurchaseOrderPayment> payments,
  }) async {
    if (payments.isEmpty) {
      return;
    }

    final uri = Uri.parse('$_baseUrl/$id/payments');
    final payload = {
      'payments': payments.map((payment) => payment.toJson()).toList(),
    };

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
      throw PurchaseOrdersException(
        'We couldn\'t save the payments right now. Please try again in a moment.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PurchaseOrdersException(
        'We couldn\'t save the payments. Please try again or contact support if this keeps happening.',
      );
    }
  }

  Future<void> deletePayments({
    required String id,
    required Map<String, String> headers,
    required List<String> paymentIds,
  }) async {
    if (paymentIds.isEmpty) {
      return;
    }

    final normalizedIds = paymentIds
        .map((value) => int.tryParse(value) ?? value)
        .toList(growable: false);

    final request = http.Request(
      'DELETE',
      Uri.parse('$_singleOrderBaseUrl/$id/payments'),
    )
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...headers,
      })
      ..body = jsonEncode({'ids': normalizedIds});

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t remove the selected payments. Please try again shortly.',
      );
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 && resolved.statusCode != 204) {
      throw PurchaseOrdersException(
        'We couldn\'t remove the selected payments right now. Please try again later.',
      );
    }
  }

  Future<PurchaseOrdersPage> fetchPurchaseOrders({
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
      throw PurchaseOrdersException(
        'We couldn\'t connect to load purchase orders. Check your connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw PurchaseOrdersException(
        'We couldn\'t load purchase orders right now. Please try again in a moment.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrdersException(
        'Something went wrong while loading purchase orders. Please try again.',
      );
    }

    final ordersList = _extractOrdersList(decoded);
    final orders = ordersList
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrder.fromJson)
        .toList();

    final pagination =
        _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return PurchaseOrdersPage(
      orders: orders,
      hasMore: pagination.hasMore,
    );
  }

  Future<PurchaseOrder> createPurchaseOrder({
    required Map<String, String> headers,
    required CreatePurchaseOrderRequest request,
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
        body: jsonEncode(request.toJson()),
      );
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t create the purchase order. Please check your connection and try again.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PurchaseOrdersException(
        'The purchase order couldn\'t be created right now. Please try again later.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t read the server response while creating the purchase order. Please try again.',
      );
    }

    final orderJson = _extractCreatedOrder(decoded);
    if (orderJson == null) {
      throw PurchaseOrdersException(
        'The server response was missing purchase order details. Please try again.',
      );
    }

    return PurchaseOrder.fromJson(orderJson);
  }

  Future<PurchaseOrder> updatePurchaseOrder({
    required String id,
    required Map<String, String> headers,
    required CreatePurchaseOrderRequest request,
  }) async {
    http.Response response;
    try {
      response = await _client.put(
        Uri.parse('$_baseUrl/$id'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(request.toJson()),
      );
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t update the purchase order. Please check your connection and try again.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw PurchaseOrdersException(
        'The purchase order couldn\'t be updated right now. Please try again later.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t read the server response while updating the purchase order. Please try again.',
      );
    }

    final orderJson = _extractCreatedOrder(decoded);
    if (orderJson == null) {
      throw PurchaseOrdersException(
        'The server response was missing purchase order details. Please try again.',
      );
    }

    return PurchaseOrder.fromJson(orderJson);
  }

  Future<void> deletePurchaseOrder({
    required String id,
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.delete(
        Uri.parse('$_singleOrderBaseUrl/$id'),
        headers: headers,
      );
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t delete the purchase order right now. Please try again.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw PurchaseOrdersException(
        'The purchase order couldn\'t be deleted. Please try again later.',
      );
    }
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

    final uploadFiles =
        files.whereType<http.MultipartFile>().toList(growable: false);
    if (uploadFiles.isEmpty) {
      return;
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_attachmentsBaseUrl/$id/attachments'),
    )
      ..headers.addAll({
        'Accept': 'application/json',
        ...headers,
      })
      ..files.addAll(uploadFiles);

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (error) {
      throw PurchaseOrdersException(
        'We couldn\'t upload the attachments. Please try again.',
      );
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 &&
        resolved.statusCode != 201 &&
        resolved.statusCode != 204) {
      throw PurchaseOrdersException(
        'The attachments couldn\'t be uploaded right now. Please try again later.',
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

    final request = http.Request(
      'DELETE',
      Uri.parse('$_attachmentsBaseUrl/$id/attachments'),
    )
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
      throw PurchaseOrdersException(
        'We couldn\'t delete the attachments right now. Please try again.',
      );
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 && resolved.statusCode != 204) {
      throw PurchaseOrdersException(
        'The attachments couldn\'t be deleted right now. Please try again later.',
      );
    }
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

  List<dynamic> _extractOrdersList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'orders', 'purchase_orders', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractOrdersList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }

      for (final value in decoded.values) {
        final list = _extractOrdersList(value);
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

  Map<String, dynamic>? _findMap(
      Map<String, dynamic> source, List<String> keys) {
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
    final list = _extractOrdersList(decoded);
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

  Map<String, dynamic>? _extractCreatedOrder(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikePurchaseOrder(decoded)) {
        return decoded;
      }
      const preferredKeys = [
        'data',
        'purchase_order',
        'purchaseOrder',
        'order',
        'purchase_orders',
        'items',
      ];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final candidate = _extractCreatedOrder(value);
        if (candidate != null) {
          return candidate;
        }
      }
      for (final value in decoded.values) {
        final candidate = _extractCreatedOrder(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    if (decoded is List) {
      for (final value in decoded) {
        final candidate = _extractCreatedOrder(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    return null;
  }

  bool _looksLikePurchaseOrder(Map<String, dynamic> map) {
    const keys = {
      'id',
      'pur_order_number',
      'pur_order_name',
      'order_date',
      'vendor_name',
    };
    return map.keys.any(keys.contains);
  }
}

class CreatePurchaseOrderRequest {
  const CreatePurchaseOrderRequest({
    required this.orderName,
    required this.orderNumber,
    required this.orderDate,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.totalDiscount,
    required this.shippingFee,
    required this.discountValue,
    required this.isDiscountPercentage,
    this.payments,
    this.vendorId,
    this.userId,
    this.nextPurchaseOrderNumber,
    this.isUpdate = false,
    this.removedLineItemIds,
    this.removedPaymentIds,
  });

  final String? vendorId;
  final String orderName;
  final String orderNumber;
  final DateTime orderDate;
  final List<CreatePurchaseOrderItem> items;
  final double subtotal;
  final double total;
  final double totalDiscount;
  final double shippingFee;
  final double discountValue;
  final bool isDiscountPercentage;
  final List<CreatePurchaseOrderPayment>? payments;
  final String? userId;
  final int? nextPurchaseOrderNumber;
  final bool isUpdate;
  final List<String>? removedLineItemIds;
  final List<String>? removedPaymentIds;

  Map<String, dynamic> toJson() {
    final discountPercent = 0;
    final discountAmount =
        isDiscountPercentage ? subtotal * (discountValue / 100) : discountValue;
    final payload = <String, dynamic>{
      'pur_order_name': orderName,
      'vendor': vendorId ?? '',
      'estimate': 0,
      'pur_order_number': orderNumber,
      'status': 1,
      'approve_status': 2,
      'date_owed': 0,
      'delivery_date': null,
      'subtotal': subtotal,
      'total_tax': 0,
      'total': total,
      'added_from': userId ?? '',
      'discount_percent': discountPercent,
      'discount_total': discountAmount,
      'discount_%': discountPercent,
      'discount_type': 'after_tax',
      'buyer': userId ?? '',
      'status_goods': 1,
      'delivery_status': 0,
      'project': 0,
      'pur_request': 0,
      'department': 0,
      'sale_invoice': 0,
      'currency': 1,
      'order_status': 'new',
      'currency_rate': 1,
      'from_currency': 1,
      'to_currency': 1,
      'number': nextPurchaseOrderNumber ?? 0,
      'expense_convert': 0,
      'order_date': _formatDate(orderDate),
      'shipping_fee': shippingFee,
      'shipping_country': 0,
      (isUpdate ? 'items' : 'newitems'): items
          .map((item) => item.toJson(purchaseOrderNumber: nextPurchaseOrderNumber))
          .toList(growable: false),
    };

    final removedIds = removedLineItemIds;
    if (isUpdate && removedIds != null && removedIds.isNotEmpty) {
      payload['removed_items'] = removedIds
          .map((value) => int.tryParse(value) ?? value)
          .toList(growable: false);
    }

    final removedPaymentEntries = removedPaymentIds;
    if (isUpdate &&
        removedPaymentEntries != null &&
        removedPaymentEntries.isNotEmpty) {
      payload['removed_payments'] = removedPaymentEntries
          .map((value) => int.tryParse(value) ?? value)
          .toList(growable: false);
    }

    final paymentEntries = payments;
    if (paymentEntries != null && paymentEntries.isNotEmpty) {
      payload['payments'] =
          paymentEntries.map((payment) => payment.toJson()).toList(growable: false);
    }

    return payload;
  }

}

class CreatePurchaseOrderPayment {
  const CreatePurchaseOrderPayment({
    required this.purchaseOrderNumber,
    required this.amount,
    required this.paymentMode,
    required this.date,
    required this.requester,
    this.approvalStatus = 2,
  });

  final int? purchaseOrderNumber;
  final double amount;
  final String paymentMode;
  final DateTime date;
  final String? requester;
  final int approvalStatus;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pur_invoice': purchaseOrderNumber ?? 0,
      'amount': amount,
      'payment_mode': paymentMode,
      'date': _formatDate(date),
      'approval_status': approvalStatus,
      'requester': requester ?? '',
    };
  }
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class CreatePurchaseOrderItem {
  const CreatePurchaseOrderItem({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.subtotal,
    required this.discount,
    required this.unitPrice,
    required this.total,
    this.unitId,
    this.description,
    this.lineItemId,
  });

  final String itemId;
  final String itemName;
  final double quantity;
  final double subtotal;
  final double discount;
  final double unitPrice;
  final double total;
  final String? unitId;
  final String? description;
  final String? lineItemId;

  Map<String, dynamic> toJson({required int? purchaseOrderNumber}) {
    final payload = <String, dynamic>{
      'pur_order': purchaseOrderNumber ?? 0,
      'item_code': itemId,
      'description': description,
      'unit_id': unitId ?? itemId,
      'unit_price': unitPrice,
      'quantity': quantity,
      'into_money': subtotal,
      'discount_%': 0,
      'discount_money': discount,
      'total_money': total,
      'total': total,
      'tax_value': 0,
      'tax_rate': null,
      'tax_name': null,
      'item_name': itemName,
      'wh_quantity_received': null,
    };

    final existingId = lineItemId?.trim();
    if (existingId != null && existingId.isNotEmpty) {
      final numericId = int.tryParse(existingId);
      payload['id'] = numericId ?? existingId;
    }

    return payload;
  }
}

class PurchaseOrdersPage {
  const PurchaseOrdersPage({required this.orders, required this.hasMore});

  final List<PurchaseOrder> orders;
  final bool hasMore;
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.name,
    required this.vendorName,
    required this.orderDate,
    required this.totalAmount,
    required this.totalLabel,
    required this.currencySymbol,
    required this.deliveryStatus,
    this.totalPaid,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final totalValue = json['total'];
    final totalAmount = _parseDouble(totalValue);
    final totalPaidAmount =
        _parseDouble(json['total_paid'] ?? json['paid'] ?? json['amount_paid']);
    final currency = json['currency_symbol'] ?? json['currency'];
    final vendorData = json['vendor'];
    String? resolvedVendor;
    if (vendorData is Map<String, dynamic>) {
      resolvedVendor = _stringValue(vendorData['name']);
    }
    return PurchaseOrder(
      id: _stringValue(json['id']) ?? '',
      number: _stringValue(json['pur_order_number']) ??
          _stringValue(json['number']) ??
          _stringValue(json['order_number']) ??
          '—',
      name: _stringValue(json['pur_order_name']) ??
          _stringValue(json['name']) ??
          '—',
      vendorName: resolvedVendor ??
          _stringValue(json['vendor_name']) ??
          '—',
      orderDate: _parseDateString(
        _stringValue(json['order_date']) ??
            _stringValue(json['created_at']) ??
            '',
      ),
      totalAmount: totalAmount,
      totalLabel:
          totalAmount != null ? totalAmount.toStringAsFixed(2) : _formatAmount(totalValue),
      currencySymbol: _stringValue(currency) ?? '',
      deliveryStatus: _parseDeliveryStatus(json),
      totalPaid: totalPaidAmount,
    );
  }

  final String id;
  final String number;
  final String name;
  final String vendorName;
  final DateTime? orderDate;
  final double? totalAmount;
  final String totalLabel;
  final String currencySymbol;
  final int deliveryStatus;
  final double? totalPaid;

  String get formattedDate {
    final date = orderDate;
    if (date == null) {
      return '—';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
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

int _parseDeliveryStatus(Map<String, dynamic> json) {
  final directValue = _parseInt(json['delivery_status']) ??
      _parseInt(json['delivery_status_id']) ??
      _parseInt(json['delivery_status_code']) ??
      _parseInt(json['delivery_status_value']);

  if (directValue != null) {
    return directValue;
  }

  final nestedValue = _parseNestedDeliveryStatus(json['delivery_status']);
  if (nestedValue != null) {
    return nestedValue;
  }

  final fallback = _parseInt(json['status']) ?? _parseInt(json['status_id']);
  if (fallback != null) {
    return fallback;
  }

  return 0;
}

int? _parseNestedDeliveryStatus(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _parseInt(value['id']) ??
        _parseInt(value['code']) ??
        _parseInt(value['value']) ??
        _parseInt(value['status']);
  }
  return _parseInt(value);
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class PurchaseOrdersException implements Exception {
  const PurchaseOrdersException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrdersException: $message';
}

DateTime? _parseDateString(String value) {
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
      final candidate =
          timePart != null && timePart.isNotEmpty ? '$isoDate $timePart' : isoDate;
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

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }
  return null;
}

List<int> _parseTimeComponents(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const [0, 0, 0];
  }
  final segments = value.trim().split(':');
  final result = <int>[];
  for (var i = 0; i < segments.length && i < 3; i++) {
    result.add(int.tryParse(segments[i]) ?? 0);
  }
  while (result.length < 3) {
    result.add(0);
  }
  return result;
}

String _formatAmount(dynamic value) {
  if (value is num) {
    return value.toStringAsFixed(2);
  }
  final stringValue = PurchaseOrder._stringValue(value);
  if (stringValue == null) {
    return '0.00';
  }
  final parsed = double.tryParse(stringValue);
  if (parsed != null) {
    return parsed.toStringAsFixed(2);
  }
  return stringValue;
}

double? _parseDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }
  return null;
}

