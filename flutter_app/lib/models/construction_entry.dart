import 'package:cloud_firestore/cloud_firestore.dart';

/// One line item inside a Material entry (from the materials catalog).
class ConstructionLineItem {
  final String item;
  final String hsn;
  final double qty;
  final String unit;
  final double rate;

  const ConstructionLineItem({
    required this.item,
    this.hsn  = '',
    this.qty  = 1,
    this.unit = '',
    this.rate = 0,
  });

  double get total => qty * rate;

  Map<String, dynamic> toMap() => {
        'item': item,
        'hsn':  hsn,
        'qty':  qty,
        'unit': unit,
        'rate': rate,
      };

  factory ConstructionLineItem.fromMap(Map<String, dynamic> m) =>
      ConstructionLineItem(
        item: m['item'] as String? ?? '',
        hsn:  m['hsn']  as String? ?? '',
        qty:  (m['qty']  as num?)?.toDouble() ?? 0,
        unit: m['unit'] as String? ?? '',
        rate: (m['rate'] as num?)?.toDouble() ?? 0,
      );
}

/// A construction ledger entry for a project. Type is one of:
/// client (income) | material | labour | contractor (expenses).
class ConstructionEntry {
  final String    id;
  final String    businessId;
  final String    projectId;
  final String    type;         // client | material | labour | contractor
  final List<ConstructionLineItem> items; // material line items (may be empty)
  final double    amount;       // total (bill total; income for 'client')
  final bool      gst;
  final double    gstAmount;
  final String    desc;
  final String    vendor;
  final bool      paidNow;      // true = paid, false = on credit
  final String    paymentMode;  // cash | upi | bank | cheque | rtgs
  final String    attachmentUrl;
  final DateTime  date;
  final DateTime? createdAt;

  const ConstructionEntry({
    required this.id,
    required this.businessId,
    required this.projectId,
    required this.type,
    this.items         = const [],
    this.amount        = 0,
    this.gst           = false,
    this.gstAmount     = 0,
    this.desc          = '',
    this.vendor        = '',
    this.paidNow       = true,
    this.paymentMode   = 'cash',
    this.attachmentUrl = '',
    required this.date,
    this.createdAt,
  });

  bool get isIncome => type == 'client';

  factory ConstructionEntry.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final rawItems = d['items'] as List? ?? [];
    return ConstructionEntry(
      id:            doc.id,
      businessId:    d['businessId'] as String? ?? '',
      projectId:     d['projectId']  as String? ?? '',
      type:          d['type']       as String? ?? 'material',
      items:         rawItems
          .map((e) => ConstructionLineItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      amount:        (d['amount']    as num?)?.toDouble() ?? 0,
      gst:           d['gst']        as bool?   ?? false,
      gstAmount:     (d['gstAmount'] as num?)?.toDouble() ?? 0,
      desc:          d['desc']       as String? ?? '',
      vendor:        d['vendor']     as String? ?? '',
      paidNow:       d['paidNow']    as bool?   ?? true,
      paymentMode:   d['paymentMode'] as String? ?? 'cash',
      attachmentUrl: d['attachmentUrl'] as String? ?? '',
      date:          _parseDate(d['date']),
      createdAt:     d['createdAt'] is Timestamp
          ? (d['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) {
      return DateTime.tryParse(v) ?? DateTime.now();
    }
    return DateTime.now();
  }

  Map<String, dynamic> toFirestore() => {
        'businessId':    businessId,
        'projectId':     projectId,
        'type':          type,
        'items':         items.map((e) => e.toMap()).toList(),
        'amount':        amount,
        'gst':           gst,
        'gstAmount':     gstAmount,
        'desc':          desc,
        'vendor':        vendor,
        'paidNow':       paidNow,
        'paymentMode':   paymentMode,
        'attachmentUrl': attachmentUrl,
        'date':          date.toIso8601String().split('T')[0],
        'createdAt':     createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}
