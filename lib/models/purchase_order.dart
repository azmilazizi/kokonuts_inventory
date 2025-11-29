
class PurchaseOrder {
  final String id;
  final String poNumber;
  final String vendorName;
  final String status;
  final DateTime date;
  final DateTime? deliveryDate;
  // Add other fields that might be useful for details
  final String? description;
  final double totalAmount;

  PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.vendorName,
    required this.status,
    required this.date,
    this.deliveryDate,
    this.description,
    required this.totalAmount,
  });
}
