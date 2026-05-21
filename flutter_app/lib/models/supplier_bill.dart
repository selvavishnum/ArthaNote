import 'package:cloud_firestore/cloud_firestore.dart';

class SupplierBill {
  final String   id;
  final String   businessId;
  final String   supplierId;
  final String   supplierName;
  final DateTime date;
  final String   type;    // 'bill' or 'payment'
  final double   amount;
  final String   desc;

  const SupplierBill({
    required this.id,
    required this.businessId,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    required this.type,
    required this.amount,
    required this.desc,
  });

  factory SupplierBill.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return SupplierBill(
      id:           doc.id,
      businessId:   d['businessId']   as String? ?? '',
      supplierId:   d['supplierId']   as String? ?? '',
      supplierName: d['supplierName'] as String? ?? '',
      date:         (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type:         d['type']         as String? ?? 'payment',
      amount:       (d['amount']      as num?)?.toDouble() ?? 0,
      desc:         d['desc']         as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId':   businessId,
    'supplierId':   supplierId,
    'supplierName': supplierName,
    'date':         Timestamp.fromDate(date),
    'type':         type,
    'amount':       amount,
    'desc':         desc,
    'createdAt':    FieldValue.serverTimestamp(),
  };
}
