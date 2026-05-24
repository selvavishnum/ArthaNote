import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fc_member.dart';
import '../models/fc_payment.dart';
import '../models/fc_chit.dart';

class FcService {
  final _db = FirebaseFirestore.instance;

  // ── Members ────────────────────────────────────────────────────────────────

  Stream<List<FCMember>> memberStream(String businessId) {
    return _db
        .collection('fc_members')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((doc) => FCMember.fromFirestore(doc))
          .toList();
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

  /// Stream payments for a specific month (YYYY-MM).
  Stream<List<FCPayment>> paymentStream(String businessId, String month) {
    return _db
        .collection('fc_payments')
        .where('businessId', isEqualTo: businessId)
        .where('month', isEqualTo: month)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => FCPayment.fromFirestore(doc))
            .toList());
  }

  /// Stream ALL payments for a member across all months.
  Stream<List<FCPayment>> memberPaymentStream(
      String businessId, String memberId) {
    return _db
        .collection('fc_payments')
        .where('businessId', isEqualTo: businessId)
        .where('memberId', isEqualTo: memberId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((doc) => FCPayment.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.month.compareTo(a.month));
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
      final list = snap.docs
          .map((doc) => FCChit.fromFirestore(doc))
          .toList();
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

  /// Append a prize record using arrayUnion so it's safe to call concurrently.
  Future<void> recordChitPrize(String chitId, Map<String, dynamic> prize) async {
    await _db.collection('fc_chits').doc(chitId).update({
      'prizes': FieldValue.arrayUnion([prize]),
    });
  }
}
