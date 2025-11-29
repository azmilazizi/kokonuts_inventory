import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokonuts_bookkeeping/services/overview_service.dart';

void main() {
  test('MoneyOutSummary parses the provided JSON correctly', () {
    final jsonResponse = """
{
    "status": true,
    "result": {
        "date_from": "2025-09-01",
        "date_to": "2025-09-30",
        "filters": {
            "vendor": null,
            "po_status": null,
            "bill_status": null
        },
        "totals": {
            "purchase_orders": {
                "count": 0,
                "amount": 0
            },
            "expenses": {
                "count": 0,
                "amount": 0
            },
            "bills": {
                "count": 3,
                "amount": 2218.71999999999979991116560995578765869140625
            }
        },
        "grand_total": 2218.71999999999979991116560995578765869140625
    }
}
""";

    final decoded = jsonDecode(jsonResponse);
    // Simulate what OverviewService.fetchMoneyOutSummary does: extract 'result'
    final data = decoded['result'];

    final summary = MoneyOutSummary.fromJson(data);

    // Verify Total Spent
    expect(summary.totalSpent, '2218.72');

    // Verify Purchase Orders
    expect(summary.purchaseOrders.count, 0);
    expect(summary.purchaseOrders.total, '0.00');

    // Verify Expenses
    expect(summary.expenses.count, 0);
    expect(summary.expenses.total, '0.00');

    // Verify Bills
    expect(summary.bills.count, 3);
    expect(summary.bills.total, '2218.72');
  });
}
