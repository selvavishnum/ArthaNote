class PaymentReminder {
  final String   id;
  final String   name;        // "HDFC Credit Card", "Manappuram Gold Loan"
  final String   type;        // credit_card / gold_loan / loan / rent / chit / other
  double         amount;      // last known amount (mutable for updates)
  final int      dueDay;      // 1–28, day of month
  final String   frequency;   // monthly / yearly
  final bool     isActive;
  final DateTime createdAt;
  DateTime?      lastPaidAt;
  final List<double> amountHistory;  // up to 6 recent amounts for average

  PaymentReminder({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.dueDay,
    this.frequency = 'monthly',
    this.isActive  = true,
    required this.createdAt,
    this.lastPaidAt,
    List<double>? amountHistory,
  }) : amountHistory = amountHistory ?? [];

  bool get isPaidThisMonth {
    if (lastPaidAt == null) return false;
    final now = DateTime.now();
    return lastPaidAt!.year == now.year && lastPaidAt!.month == now.month;
  }

  int get daysUntilDue {
    final now  = DateTime.now();
    var   next = DateTime(now.year, now.month, dueDay);
    if (next.isBefore(now)) next = DateTime(now.year, now.month + 1, dueDay);
    return next.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  double get averageAmount {
    if (amountHistory.isEmpty) return amount;
    return amountHistory.reduce((a, b) => a + b) / amountHistory.length;
  }

  factory PaymentReminder.fromJson(Map<String, dynamic> m) => PaymentReminder(
    id:        m['id']        as String,
    name:      m['name']      as String,
    type:      m['type']      as String,
    amount:    (m['amount']   as num).toDouble(),
    dueDay:    m['dueDay']    as int,
    frequency: m['frequency'] as String? ?? 'monthly',
    isActive:  m['isActive']  as bool?   ?? true,
    createdAt: DateTime.parse(m['createdAt'] as String),
    lastPaidAt: m['lastPaidAt'] != null ? DateTime.tryParse(m['lastPaidAt'] as String) : null,
    amountHistory: (m['amountHistory'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toDouble()).toList(),
  );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'name':      name,
    'type':      type,
    'amount':    amount,
    'dueDay':    dueDay,
    'frequency': frequency,
    'isActive':  isActive,
    'createdAt': createdAt.toIso8601String(),
    'lastPaidAt': lastPaidAt?.toIso8601String(),
    'amountHistory': amountHistory,
  };
}
