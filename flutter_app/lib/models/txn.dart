import 'package:cloud_firestore/cloud_firestore.dart';

class Txn {
  final String   id;
  final String   businessId;
  final String   shop;
  final String   shopName;
  final DateTime date;
  final String   type;   // sale | expense | payment
  final double   amount;
  final String   desc;

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

  Map<String, dynamic> toJson() => {
    'id':         id,
    'businessId': businessId,
    'shop':       shop,
    'shopName':   shopName,
    'date':       date.toIso8601String(),
    'type':       type,
    'amount':     amount,
    'desc':       desc,
  };

  factory Txn.fromJson(Map<String, dynamic> m) => Txn(
    id:         m['id']         as String? ?? '',
    businessId: m['businessId'] as String? ?? '',
    shop:       m['shop']       as String? ?? '',
    shopName:   m['shopName']   as String? ?? '',
    date:       DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
    type:       m['type']       as String? ?? 'sale',
    amount:     (m['amount']    as num?)?.toDouble() ?? 0,
    desc:       m['desc']       as String? ?? '',
  );

  Txn copyWith({
    String?   id,
    String?   businessId,
    String?   shop,
    String?   shopName,
    DateTime? date,
    String?   type,
    double?   amount,
    String?   desc,
  }) => Txn(
    id:         id         ?? this.id,
    businessId: businessId ?? this.businessId,
    shop:       shop       ?? this.shop,
    shopName:   shopName   ?? this.shopName,
    date:       date       ?? this.date,
    type:       type       ?? this.type,
    amount:     amount     ?? this.amount,
    desc:       desc       ?? this.desc,
  );
}
