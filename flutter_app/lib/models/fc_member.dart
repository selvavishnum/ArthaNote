import 'package:cloud_firestore/cloud_firestore.dart';

class FCMember {
  final String   id;
  final String   businessId;
  final String   name;
  final String   phone;
  final double   amount;      // installment amount per cycle
  final double   loanAmount;  // total loan given (0 = no loan, just collection)
  final String   frequency;   // 'daily' | 'weekly' | 'monthly'
  final String   group;       // 'finance' | 'chit' | 'both'
  final String   joinMonth;   // YYYY-MM
  final DateTime createdAt;

  const FCMember({
    required this.id,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.amount,
    this.loanAmount = 0.0,
    this.frequency  = 'monthly',
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
      loanAmount: (d['loanAmount'] as num?)?.toDouble() ?? 0,
      frequency:  d['frequency']  as String? ?? 'monthly',
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
    'loanAmount': loanAmount,
    'frequency':  frequency,
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
    double?   loanAmount,
    String?   frequency,
    String?   group,
    String?   joinMonth,
    DateTime? createdAt,
  }) => FCMember(
    id:         id         ?? this.id,
    businessId: businessId ?? this.businessId,
    name:       name       ?? this.name,
    phone:      phone      ?? this.phone,
    amount:     amount     ?? this.amount,
    loanAmount: loanAmount ?? this.loanAmount,
    frequency:  frequency  ?? this.frequency,
    group:      group      ?? this.group,
    joinMonth:  joinMonth  ?? this.joinMonth,
    createdAt:  createdAt  ?? this.createdAt,
  );
}
