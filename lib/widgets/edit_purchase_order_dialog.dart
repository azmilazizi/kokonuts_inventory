import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/purchase_order_detail_service.dart';
import 'add_purchase_order_dialog.dart';

class EditPurchaseOrderDialog extends StatefulWidget {
  const EditPurchaseOrderDialog({super.key, required this.orderId});

  final String orderId;

  @override
  State<EditPurchaseOrderDialog> createState() => _EditPurchaseOrderDialogState();
}

class _EditPurchaseOrderDialogState extends State<EditPurchaseOrderDialog> {
  final _detailService = PurchaseOrderDetailService();
  late Future<PurchaseOrderDetail> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetail();
      _initialized = true;
    }
  }

  Future<PurchaseOrderDetail> _loadDetail() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      throw const PurchaseOrderDetailException('Dialog no longer mounted');
    }

    if (token == null || token.trim().isEmpty) {
      throw const PurchaseOrderDetailException('You are not logged in.');
    }

    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth = sanitizedToken.isNotEmpty
        ? 'Bearer $sanitizedToken'
        : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader =
        autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;

    return _detailService.fetchPurchaseOrder(
      id: widget.orderId,
      headers: {
        'Accept': 'application/json',
        'authtoken': authtokenHeader,
        'Authorization': normalizedAuth,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PurchaseOrderDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Dialog(
            child: SizedBox(
              width: 400,
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(
                  child: Text('Unable to load purchase order'),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: Text(snapshot.error.toString()),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _future = _loadDetail();
                  });
                },
                child: const Text('Retry'),
              ),
            ],
          );
        }

        if (!snapshot.hasData) {
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(
                  child: Text('Unable to load purchase order'),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: const Text('No purchase order data was returned.'),
          );
        }

        return AddPurchaseOrderDialog(
          initialDetail: snapshot.data,
          orderId: widget.orderId,
        );
      },
    );
  }
}
