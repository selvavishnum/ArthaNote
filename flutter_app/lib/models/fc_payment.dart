import 'package:cloud_firestore/cloud_firestore.dart';

class FCPayment {
  final String   id;
  final String   businessId;
  final String   memberId;
  final String   month;    // YYYY-MM (legacy / monthly)
  final String   period;   // YYYY-MM-DD (daily) | YYYY-MM-DD (week Monday) | YYYY-MM (monthly)
  final double   amount;
  final String   mode;     // 'cash' | 'gpay' | 'bank' | 'other'
  final String   note;
  final DateTime createdAt;

  const FCPayment({
    required this.id,
    required this.businessId,
    required this.memberId,
    required this.month,
    required this.period,
    required this.amount,
    required this.mode,
    required this.note,
    required this.createdAt,
  });

  factory FCPayment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final month = d['month'] as String? ?? '';
    return FCPayment(
      id:         doc.id,
      businessId: d['businessId'] as String? ?? '',
      memberId:   d['memberId']   as String? ?? '',
      month:      month,
      period:     d['period']     as String? ?? month,
      amount:     (d['amount']    as num?)?.toDouble() ?? 0,
      mode:       d['mode']       as String? ?? 'cash',
      note:       d['note']       as String? ?? '',
      createdAt:  (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId': businessId,
    'memberId':   memberId,
    'month':      month,
    'period':     period,
    'amount':     amount,
    'mode':       mode,
    'note':       note,
    'createdAt':  FieldValue.serverTimestamp(),
  };
}
