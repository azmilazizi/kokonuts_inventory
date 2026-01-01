import 'dart:convert';

import 'package:http/http.dart' as http;

class InventoryReceivingService {
  InventoryReceivingService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/warehouse/api/v1/goods_receipt';

  Future<void> createGoodsReceipt({
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
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
        body: jsonEncode(payload),
      );
    } catch (error) {
      throw InventoryReceivingException('Failed to reach server: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InventoryReceivingException(
        'Goods receipt request failed with status '
        '${response.statusCode}: ${response.body}',
      );
    }
  }
}

class InventoryReceivingException implements Exception {
  InventoryReceivingException(this.message);

  final String message;

  @override
  String toString() => 'InventoryReceivingException: $message';
}
