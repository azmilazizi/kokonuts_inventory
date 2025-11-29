
class PurchaseOrder {
  final String id;
  final String poNumber;
  final String vendorName;
  final String status;
  final DateTime date;
  final DateTime? deliveryDate;
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

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['id']?.toString() ?? '',
      poNumber: json['po_number'] ?? '',
      vendorName: json['vendor_name'] ?? 'Unknown Vendor',
      status: json['status'] ?? 'Unknown',
      date: json['date'] != null
          ? DateTime.tryParse(json['date']) ?? DateTime.now()
          : DateTime.now(),
      deliveryDate: json['delivery_date'] != null
          ? DateTime.tryParse(json['delivery_date'])
          : null,
      description: json['description'],
      totalAmount: (json['total_amount'] is num)
          ? (json['total_amount'] as num).toDouble()
          : 0.0,
    );
  }
}
