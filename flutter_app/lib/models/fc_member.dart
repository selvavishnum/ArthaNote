import 'package:cloud_firestore/cloud_firestore.dart';

class FCMember {
  final String   id;
  final String   businessId;
  final String   name;
  final String   phone;
  final double   amount;     // monthly due amount
  final String   group;      // 'finance' | 'chit' | 'both'
  final String   joinMonth;  // YYYY-MM
  final DateTime createdAt;

  const FCMember({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.amount,
    required this.group,
    required this.joinMonth,
    required this.createdAt,
  });

  factory FCMember.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return FCMember(
      id:         doc.id,
      businessId: d['businessId'] as String? ?? '',
      name:       d['name']       as String? ?? '',
      phone:      d['phone']      as String? ?? '',
      amount:     (d['amount']    as num?)?.toDouble() ?? 0,
      group:      d['group']      as String? ?? 'finance',
      joinMonth:  d['joinMonth']  as String? ?? '',
      createdAt:  (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId,
    'name':       name,
    'phone':      phone,
    'amount':     amount,
    'group':      group,
    'joinMonth':  joinMonth,
    'createdAt':  FieldValue.serverTimestamp(),
  };

  FCMember copyWith({
    String?   id,
    String?   businessId,
    String?   name,
    String?   phone,
    double?   amount,
    String?   group,
    String?   joinMonth,
    DateTime? createdAt,
  }) => FCMember(
    id:         id         ?? this.id,
    businessId: businessId ?? this.businessId,
    name:       name       ?? this.name,
    phone:      phone      ?? this.phone,
    amount:     amount     ?? this.amount,
    group:      group      ?? this.group,
    joinMonth:  joinMonth  ?? this.joinMonth,
    createdAt:  createdAt  ?? this.createdAt,
  );
}
