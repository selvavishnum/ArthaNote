import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/txn.dart';
import '../models/supplier.dart';

class DbService {
  final _db = FirebaseFirestore.instance;

  // ── Transactions ──────────────────────────────────────────
  Stream<List<Txn>> txnStream(String businessId, {String? shop}) {
    Query q = _db
        .collection('transactions')
        .where('businessId', isEqualTo: businessId)
        .orderBy('date', descending: true)
        .limit(500);
    if (shop != null) q = q.where('shop', isEqualTo: shop);
    return q.snapshots().map((s) => s.docs.map(Txn.fromFirestore).toList());
  }

  Future<void> addTxn(Txn txn) =>
      _db.collection('transactions').add(txn.toFirestore());

  Future<void> deleteTxn(String id) =>
      _db.collection('transactions').doc(id).delete();

  // ── Suppliers ─────────────────────────────────────────────
  Stream<List<Supplier>> supplierStream(String businessId) =>
      _db.collection('suppliers')
          .where('businessId', isEqualTo: businessId)
          .orderBy('name')
          .snapshots()
          .map((s) => s.docs.map(Supplier.fromFirestore).toList());

  Future<void> addSupplier(Supplier s) =>
      _db.collection('suppliers').add(s.toFirestore());

  Future<void> updateSupplierBalance(String id, double delta) =>
      _db.collection('suppliers').doc(id).update({
        'balance': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteSupplier(String id) =>
      _db.collection('suppliers').doc(id).delete();
}
