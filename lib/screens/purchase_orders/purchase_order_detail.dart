import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/purchase_order.dart';

class PurchaseOrderDetail extends StatelessWidget {
  final PurchaseOrder order;

  const PurchaseOrderDetail({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Purchase Order Details',
                  style: theme.textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),
            // Removed Tabs for Payments and Attachments. Only displaying Details.
            // Details Section
            _buildDetailRow(context, 'PO Number', order.poNumber),
            _buildDetailRow(context, 'Vendor', order.vendorName),
            _buildDetailRow(context, 'Date', dateFormat.format(order.date)),
            _buildDetailRow(context, 'Status', order.status),
            _buildDetailRow(
              context,
              'Delivery Date',
              order.deliveryDate != null ? dateFormat.format(order.deliveryDate!) : '-',
            ),
             _buildDetailRow(context, 'Total Amount', '\$${order.totalAmount.toStringAsFixed(2)}'),
            if (order.description != null)
              _buildDetailRow(context, 'Description', order.description!),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
