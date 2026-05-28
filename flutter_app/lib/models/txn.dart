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
  final String   contact;
  final String   enteredBy; // email of the person who saved this entry

  const Txn({
    required this.id,
    required this.businessId,
    required this.shop,
    required this.shopName,
    required this.date,
    required this.type,
    required this.amount,
    required this.desc,
    this.contact    = '',
    this.enteredBy  = '',
  });

  factory Txn.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Txn(
      id:         doc.id,
      businessId: d['businessId'] as String? ?? '',
      shop:       d['shop']       as String? ?? '',
      shopName:   d['shopName']   as String? ?? '',
      date:       _parseDate(d['date']),
      type:       _normType(d['type'] as String? ?? 'sale'),
      amount:     (d['amount']    as num?)?.toDouble() ?? 0,
      desc:       d['desc']       as String? ?? '',
      contact:    d['contact']    as String? ?? '',
      enteredBy:  d['enteredBy']  as String? ?? '',
    );
  }

  // Website stores 'sales'; Android uses 'sale'. Normalize on read.
  static String _normType(String t) => t == 'sales' ? 'sale' : t;

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v) ?? DateTime.now();
    if (v is Map) {
      // Firestore map-encoded timestamp from web: {seconds: ..., nanoseconds: ...}
      final secs = (v['seconds'] as num?)?.toInt() ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    }
    return DateTime.now();
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId,
    'shop':       shop,
    'shopName':   shopName,
    'date':       Timestamp.fromDate(date),
    'type':       type,
    'amount':     amount,
    'desc':       desc,
    'contact':    contact,
    'enteredBy':  enteredBy,
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
    'contact':    contact,
    'enteredBy':  enteredBy,
  };

  factory Txn.fromJson(Map<String, dynamic> m) => Txn(
    id:         m['id']         as String? ?? '',
    businessId: m['businessId'] as String? ?? '',
    shop:       m['shop']       as String? ?? '',
    shopName:   m['shopName']   as String? ?? '',
    date:       DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
    type:       _normType(m['type'] as String? ?? 'sale'),
    amount:     (m['amount']    as num?)?.toDouble() ?? 0,
    desc:       m['desc']       as String? ?? '',
    contact:    m['contact']    as String? ?? '',
    enteredBy:  m['enteredBy']  as String? ?? '',
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
    String?   contact,
    String?   enteredBy,
  }) => Txn(
    id:         id         ?? this.id,
    businessId: businessId ?? this.businessId,
    shop:       shop       ?? this.shop,
    shopName:   shopName   ?? this.shopName,
    date:       date       ?? this.date,
    type:       type       ?? this.type,
    amount:     amount     ?? this.amount,
    desc:       desc       ?? this.desc,
    contact:    contact    ?? this.contact,
    enteredBy:  enteredBy  ?? this.enteredBy,
  );
}
