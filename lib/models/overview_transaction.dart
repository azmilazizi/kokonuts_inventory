import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import '../services/expenses_service.dart';
import '../services/purchase_orders_service.dart';

class OverviewTransaction {
  final String id;
  final DateTime date;
  final String number;
  final String vendor;
  final String type;
  final double amount;
  final String status;
  final String? paymentMode;

  OverviewTransaction({
    required this.id,
    required this.date,
    required this.number,
    required this.vendor,
    required this.type,
    required this.amount,
    required this.status,
    this.paymentMode,
  });

  String get formattedDate {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String get formattedAmount {
    return NumberFormat.simpleCurrency(name: '').format(amount);
  }

  factory OverviewTransaction.fromExpense(Expense expense) {
    return OverviewTransaction(
      id: expense.id,
      date: expense.date ?? DateTime.now(),
      number: expense.name,
      vendor: expense.vendor,
      type: 'Expense',
      amount: expense.amount ?? 0.0,
      status: 'Paid',
      paymentMode: expense.paymentMode,
    );
  }

  factory OverviewTransaction.fromBill(Bill bill) {
    return OverviewTransaction(
      id: bill.id,
      date: bill.billDate ?? DateTime.now(),
      number: 'Bill #${bill.id}',
      vendor: bill.vendorName ?? 'Unknown',
      type: 'Bill',
      amount: bill.totalAmount ?? 0.0,
      status: bill.status.label,
    );
  }

  factory OverviewTransaction.fromBillPayment(BillPayment payment, String vendorName) {
    return OverviewTransaction(
      id: payment.id,
      date: payment.date ?? DateTime.now(),
      number: payment.referenceNo ?? payment.id,
      vendor: vendorName,
      type: 'Bill Payment',
      amount: payment.amount ?? 0.0,
      status: 'Paid',
      paymentMode: payment.paymentAccount,
    );
  }

  factory OverviewTransaction.fromPurchaseOrder(PurchaseOrder po) {
    return OverviewTransaction(
      id: po.id,
      date: po.orderDate ?? DateTime.now(),
      number: po.number,
      vendor: po.vendorName,
      type: 'Purchase Order',
      amount: po.totalAmount ?? 0.0,
      status: _mapDeliveryStatus(po.deliveryStatus),
    );
  }

  static String _mapDeliveryStatus(int status) {
    switch (status) {
      case 0:
        return 'Undelivered';
      case 1:
        return 'Delivered';
      case 2:
        return 'Shipping';
      default:
        return 'Status $status';
    }
  }
}
