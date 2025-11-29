import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app_state.dart';
import '../../app/app_state_scope.dart';
import '../../models/purchase_order.dart';
import '../../services/purchase_order_service.dart';
import '../../services/authenticated_http_client.dart';
import 'purchase_order_detail.dart';

class PurchaseOrderList extends StatefulWidget {
  const PurchaseOrderList({super.key});

  @override
  State<PurchaseOrderList> createState() => _PurchaseOrderListState();
}

class _PurchaseOrderListState extends State<PurchaseOrderList> {
  final List<PurchaseOrder> _orders = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalOrders = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    // Fetch data after the first frame to have access to context if needed (though we use AppStateScope)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchOrders();
    });
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final appState = AppStateScope.of(context);

      final client = AuthenticatedHttpClient(
        tokenProvider: () async {
          final token = await appState.getValidAuthToken();
          if (token == null) return null;
          return AuthTokenPayload(
            authorizationToken: token,
            authtoken: token,
            rawAuthtoken: token,
          );
        },
      );

      final service = PurchaseOrderService(client);
      final response = await service.getPurchaseOrders(page: _currentPage, limit: _limit);

      if (mounted) {
        setState(() {
          _orders.clear();
          _orders.addAll(response.orders);
          _totalOrders = response.total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    _fetchOrders();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_errorMessage', style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchOrders,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return const Center(child: Text('No purchase orders found.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('PO #')),
                  DataColumn(label: Text('Vendor')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Delivery Date')),
                ],
                rows: _orders.map((order) {
                  return DataRow(
                    onSelectChanged: (_) {
                      showDialog(
                        context: context,
                        builder: (context) => PurchaseOrderDetail(order: order),
                      );
                    },
                    cells: [
                      DataCell(Text(order.poNumber)),
                      DataCell(Text(order.vendorName)),
                      DataCell(Text(dateFormat.format(order.date))),
                      DataCell(Text(order.status)),
                      DataCell(Text(order.deliveryDate != null
                          ? dateFormat.format(order.deliveryDate!)
                          : '-')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        // Simple Pagination Controls
        if (_totalOrders > _limit)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 1
                      ? () => _onPageChanged(_currentPage - 1)
                      : null,
                ),
                Text('Page $_currentPage of ${(_totalOrders / _limit).ceil()}'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < (_totalOrders / _limit).ceil()
                      ? () => _onPageChanged(_currentPage + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
