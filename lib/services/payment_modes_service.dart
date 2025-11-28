import 'dart:convert';

import 'package:http/http.dart' as http;

class PaymentModesService {
  PaymentModesService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _paymentModesUrl = 'https://crm.kokonuts.my/api/v1/payment_mode';

  Future<List<PaymentMode>> fetchPaymentModes({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response =
          await _client.get(Uri.parse(_paymentModesUrl), headers: headers);
    } catch (error) {
      throw PaymentModesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PaymentModesException(
        'Payment mode request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PaymentModesException('Unable to parse payment mode response: $error');
    }

    final Map<String, PaymentMode> modesById = {};
    _collectPaymentModes(decoded, modesById);

    final sorted = modesById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  void _collectPaymentModes(
    dynamic source,
    Map<String, PaymentMode> results,
  ) {
    if (source is Map<String, dynamic>) {
      final id = _extractPaymentModeId(source);
      final name = _extractPaymentModeName(source);
      if (id != null && name != null) {
        results[id] = PaymentMode(id: id, name: name);
      }
      for (final value in source.values) {
        _collectPaymentModes(value, results);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectPaymentModes(item, results);
      }
    }
  }

  String? _extractPaymentModeName(Map<String, dynamic> source) {
    const candidateKeys = [
      'name',
      'payment_mode',
      'paymentMode',
      'label',
      'title',
    ];

    for (final key in candidateKeys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _extractPaymentModeId(Map<String, dynamic> source) {
    const candidateKeys = [
      'id',
      'payment_mode_id',
      'paymentModeId',
    ];

    for (final key in candidateKeys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is int) {
        return value.toString();
      }
    }
    return null;
  }
}

class PaymentMode {
  const PaymentMode({required this.id, required this.name});

  final String id;
  final String name;
}

class PaymentModesException implements Exception {
  PaymentModesException(this.message);

  final String message;

  @override
  String toString() => 'PaymentModesException: $message';
}
