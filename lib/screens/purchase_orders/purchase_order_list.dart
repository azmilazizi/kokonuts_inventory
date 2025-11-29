import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/purchase_order.dart';
import 'purchase_order_detail.dart';

class PurchaseOrderList extends StatelessWidget {
  const PurchaseOrderList({super.key});

  // Dummy data
  static final List<PurchaseOrder> _dummyOrders = [
    PurchaseOrder(
      id: '1',
      poNumber: 'PO-2023-001',
      vendorName: 'Acme Corp',
      status: 'Ordered',
      date: DateTime(2023, 10, 25),
      deliveryDate: DateTime(2023, 11, 01),
      totalAmount: 1500.00,
      description: 'Office Supplies',
    ),
    PurchaseOrder(
      id: '2',
      poNumber: 'PO-2023-002',
      vendorName: 'Global Tech',
      status: 'Received',
      date: DateTime(2023, 10, 20),
      deliveryDate: DateTime(2023, 10, 28),
      totalAmount: 5400.50,
      description: 'New Laptops',
    ),
    PurchaseOrder(
      id: '3',
      poNumber: 'PO-2023-003',
      vendorName: 'Stationery World',
      status: 'Pending',
      date: DateTime(2023, 10, 28),
      deliveryDate: null,
      totalAmount: 200.00,
      description: 'Paper and Pens',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');

    return SingleChildScrollView(
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
          rows: _dummyOrders.map((order) {
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
    );
  }
}
