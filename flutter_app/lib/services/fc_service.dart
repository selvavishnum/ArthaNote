import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/fc_member.dart';
import '../models/fc_payment.dart';
import '../models/fc_chit.dart';

// ── Period key helpers ────────────────────────────────────────────────────────

/// Returns the canonical period key for [dt] given [frequency].
/// daily   → 'YYYY-MM-DD'
/// weekly  → 'YYYY-MM-DD' of the Monday of that week
/// monthly → 'YYYY-MM'
String periodKey(DateTime dt, String frequency) {
  switch (frequency) {
    case 'daily':
      return DateFormat('yyyy-MM-dd').format(dt);
    case 'weekly':
      final monday = dt.subtract(Duration(days: dt.weekday - 1));
      return DateFormat('yyyy-MM-dd').format(monday);
    case 'monthly':
    default:
      return DateFormat('yyyy-MM').format(dt);
  }
}

String prevPeriod(String current, String frequency) {
  switch (frequency) {
    case 'daily':
      final dt = DateFormat('yyyy-MM-dd').parse(current);
      return DateFormat('yyyy-MM-dd').format(dt.subtract(const Duration(days: 1)));
    case 'weekly':
      final dt = DateFormat('yyyy-MM-dd').parse(current);
      return DateFormat('yyyy-MM-dd').format(dt.subtract(const Duration(days: 7)));
    case 'monthly':
    default:
      final parts = current.split('-');
      var y = int.parse(parts[0]);
      var m = int.parse(parts[1]);
      if (--m == 0) { m = 12; y--; }
      return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
  }
}

String nextPeriod(String current, String frequency) {
  switch (frequency) {
    case 'daily':
      final dt = DateFormat('yyyy-MM-dd').parse(current);
      return DateFormat('yyyy-MM-dd').format(dt.add(const Duration(days: 1)));
    case 'weekly':
      final dt = DateFormat('yyyy-MM-dd').parse(current);
      return DateFormat('yyyy-MM-dd').format(dt.add(const Duration(days: 7)));
    case 'monthly':
    default:
      final parts = current.split('-');
      var y = int.parse(parts[0]);
      var m = int.parse(parts[1]);
      if (++m == 13) { m = 1; y++; }
      return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
  }
}

String formatPeriodLabel(String period, String frequency) {
  try {
    switch (frequency) {
      case 'daily':
        final dt = DateFormat('yyyy-MM-dd').parse(period);
        return DateFormat('dd MMM yyyy (EEE)').format(dt);
      case 'weekly':
        final monday = DateFormat('yyyy-MM-dd').parse(period);
        final sunday = monday.add(const Duration(days: 6));
        return '${DateFormat('dd MMM').format(monday)} – ${DateFormat('dd MMM yyyy').format(sunday)}';
      case 'monthly':
      default:
        final dt = DateFormat('yyyy-MM').parse(period);
        return DateFormat('MMMM yyyy').format(dt);
    }
  } catch (_) {
    return period;
  }
}

// ── FcService ─────────────────────────────────────────────────────────────────

class FcService {
  final _db = FirebaseFirestore.instance;

  // ── Members ────────────────────────────────────────────────────────────────

  Stream<List<FCMember>> memberStream(String businessId) {
    return _db
        .collection('fc_members')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((doc) => FCMember.fromFirestore(doc)).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> addMember(FCMember m) async {
    await _db.collection('fc_members').add(m.toFirestore());
  }

  Future<void> deleteMember(String id) async {
    await _db.collection('fc_members').doc(id).delete();
  }

  // ── Payments ───────────────────────────────────────────────────────────────

  /// Stream payments for a specific period key.
  /// Period key format depends on frequency (see [periodKey]).
  Stream<List<FCPayment>> paymentStream(String businessId, String period) {
    return _db
        .collection('fc_payments')
        .where('businessId', isEqualTo: businessId)
        .where('period', isEqualTo: period)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FCPayment.fromFirestore(d)).toList());
  }

  /// Stream ALL payments for a member across all periods.
  Stream<List<FCPayment>> memberPaymentStream(String businessId, String memberId) {
    return _db
        .collection('fc_payments')
        .where('businessId', isEqualTo: businessId)
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => FCPayment.fromFirestore(d)).toList();
      list.sort((a, b) => b.period.compareTo(a.period));
      return list;
    });
  }

  Future<void> recordPayment(FCPayment p) async {
    await _db.collection('fc_payments').add(p.toFirestore());
  }

  Future<void> deletePayment(String id) async {
    await _db.collection('fc_payments').doc(id).delete();
  }

  // ── Chits ──────────────────────────────────────────────────────────────────

  Stream<List<FCChit>> chitStream(String businessId) {
    return _db
        .collection('fc_chits')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => FCChit.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> addChit(FCChit c) async {
    await _db.collection('fc_chits').add(c.toFirestore());
  }

  Future<void> deleteChit(String id) async {
    await _db.collection('fc_chits').doc(id).delete();
  }

  Future<void> recordChitPrize(String chitId, Map<String, dynamic> prize) async {
    await _db.collection('fc_chits').doc(chitId).update({
      'prizes': FieldValue.arrayUnion([prize]),
    });
  }
}
