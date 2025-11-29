import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/purchase_order.dart';

class PurchaseOrderService {
  final http.Client _httpClient;
  final String _baseUrl = 'https://crm.kokonuts.my/purchase/api/v1';

  PurchaseOrderService(this._httpClient);

  Future<PurchaseOrderResponse> getPurchaseOrders({
    int page = 1,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/purchase_orders').replace(
      queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final response = await _httpClient.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Assuming the API returns a structure like { "data": [...], "meta": { ... } } or similar
      // Since I don't know the exact structure, I'll try to handle a direct list or a paginated object.

      List<dynamic> list = [];
      int total = 0;

      if (data is List) {
        list = data;
        total = list.length;
      } else if (data is Map<String, dynamic>) {
        if (data.containsKey('data') && data['data'] is List) {
          list = data['data'];
        }
         // Try to find total count in meta or pagination fields
        if (data.containsKey('meta') && data['meta'] is Map) {
             total = data['meta']['total'] ?? list.length;
        } else if (data.containsKey('total')) {
             total = data['total'];
        } else {
             total = list.length;
        }
      }

      final orders = list
          .map((item) => PurchaseOrder.fromJson(item))
          .toList();

      return PurchaseOrderResponse(orders: orders, total: total);
    } else {
      throw Exception('Failed to load purchase orders: ${response.statusCode}');
    }
  }
}

class PurchaseOrderResponse {
  final List<PurchaseOrder> orders;
  final int total;

  PurchaseOrderResponse({required this.orders, required this.total});
}
