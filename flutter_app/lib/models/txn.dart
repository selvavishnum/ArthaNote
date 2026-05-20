import 'package:cloud_firestore/cloud_firestore.dart';

class Txn {
  final String id;
  final String businessId;
  final String shop;
  final String shopName;
  final DateTime date;
  final String type; // sale | expense | payment
  final double amount;
  final String desc;

  const Txn({
    required this.id,
    required this.businessId,
    required this.shop,
    required this.shopName,
    required this.date,
    required this.type,
    required this.amount,
    required this.desc,
  });

  factory Txn.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Txn(
      id:         doc.id,
      businessId: d['businessId'] as String? ?? '',
      shop:       d['shop']       as String? ?? '',
      shopName:   d['shopName']   as String? ?? '',
      date:       (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type:       d['type']       as String? ?? 'sale',
      amount:     (d['amount']    as num?)?.toDouble() ?? 0,
      desc:       d['desc']       as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId,
    'shop':       shop,
    'shopName':   shopName,
    'date':       Timestamp.fromDate(date),
    'type':       type,
    'amount':     amount,
    'desc':       desc,
    'createdAt':  FieldValue.serverTimestamp(),
  };
}
