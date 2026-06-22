import 'package:cloud_firestore/cloud_firestore.dart';

/// A single credit/payment entry against a [Customer].
///
///   type == 'credit'   → goods given on credit; customer balance increases
///   type == 'payment'  → customer pays back;     customer balance decreases
class CustomerTxn {
  final String   id;
  final String   businessId;
  final String   customerId;
  final String   customerName;
  final DateTime date;
  final String   type;   // 'credit' or 'payment'
  final double   amount;
  final String   desc;

  const CustomerTxn({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.type,
    required this.amount,
    required this.desc,
  });

  factory CustomerTxn.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return CustomerTxn(
      id:           doc.id,
      businessId:   d['businessId']   as String? ?? '',
      customerId:   d['customerId']   as String? ?? '',
      customerName: d['customerName'] as String? ?? '',
      date:         (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type:         d['type']         as String? ?? 'payment',
      amount:       (d['amount']      as num?)?.toDouble() ?? 0,
      desc:         d['desc']         as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId':   businessId,
    'customerId':   customerId,
    'customerName': customerName,
    'date':         Timestamp.fromDate(date),
    'type':         type,
    'amount':       amount,
    'desc':         desc,
    'createdAt':    FieldValue.serverTimestamp(),
  };
}
