import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/txn.dart';
import '../models/supplier.dart';

class DbService {
  final _db = FirebaseFirestore.instance;

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Stream of transactions for [businessId]. Optionally filtered by [shop].
  /// Sorted client-side to avoid requiring a composite Firestore index.
  Stream<List<Txn>> txnStream(String businessId, {String? shop}) {
    Query<Map<String, dynamic>> q = _db
        .collection('transactions')
        .where('businessId', isEqualTo: businessId)
        .limit(500);

    if (shop != null && shop.isNotEmpty) {
      q = q.where('shop', isEqualTo: shop);
    }

    return q.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => Txn.fromFirestore(doc)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Future<void> addTxn(Txn txn) =>
      _db.collection('transactions').add(txn.toFirestore());

  Future<void> deleteTxn(String id) =>
      _db.collection('transactions').doc(id).delete();

  // ── Suppliers ─────────────────────────────────────────────────────────────

  /// Stream of all suppliers for [businessId], sorted client-side by name.
  Stream<List<Supplier>> supplierStream(String businessId) {
    return _db
        .collection('suppliers')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => Supplier.fromFirestore(doc))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> addSupplier(Supplier supplier) =>
      _db.collection('suppliers').add(supplier.toFirestore());

  /// Applies [delta] to the supplier's balance (negative = payment made).
  Future<void> updateSupplierBalance(String id, double delta) =>
      _db.collection('suppliers').doc(id).update({
        'balance':   FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteSupplier(String id) =>
      _db.collection('suppliers').doc(id).delete();
}
