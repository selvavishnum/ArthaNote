import 'package:cloud_firestore/cloud_firestore.dart';

class FCChit {
  final String                   id;
  final String                   businessId;
  final String                   name;
  final int                      memberCount;
  final double                   amount;      // per member per month
  final int                      months;      // total duration
  final String                   startMonth;  // YYYY-MM
  final List<Map<String, dynamic>> prizes;    // [{month, winnerName, amount}]
  final DateTime                 createdAt;

  const FCChit({
    required this.id,
    required this.businessId,
    required this.name,
    required this.memberCount,
    required this.amount,
    required this.months,
    required this.startMonth,
    required this.prizes,
    required this.createdAt,
  });

  /// Total monthly collection for this chit group
  double get monthlyTotal => memberCount * amount;

  /// How many months have elapsed since startMonth (1-based, capped at months)
  int currentMonth(DateTime now) {
    if (startMonth.isEmpty) return 1;
    final parts = startMonth.split('-');
    if (parts.length < 2) return 1;
    final startYear  = int.tryParse(parts[0]) ?? now.year;
    final startMon   = int.tryParse(parts[1]) ?? now.month;
    final elapsed    = (now.year - startYear) * 12 + (now.month - startMon) + 1;
    return elapsed.clamp(1, months);
  }

  factory FCChit.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final rawPrizes = d['prizes'] as List<dynamic>? ?? [];
    return FCChit(
      id:          doc.id,
      businessId:  d['businessId']  as String? ?? '',
      name:        d['name']        as String? ?? '',
      memberCount: (d['memberCount'] as num?)?.toInt()  ?? 0,
      amount:      (d['amount']      as num?)?.toDouble() ?? 0,
      months:      (d['months']      as num?)?.toInt()  ?? 0,
      startMonth:  d['startMonth']  as String? ?? '',
      prizes:      rawPrizes
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      createdAt:   (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'businessId':  businessId,
    'name':        name,
    'memberCount': memberCount,
    'amount':      amount,
    'months':      months,
    'startMonth':  startMonth,
    'prizes':      prizes,
    'createdAt':   FieldValue.serverTimestamp(),
  };
}
