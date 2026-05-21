import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/txn.dart';
import '../models/supplier.dart';
import '../models/supplier_bill.dart';

class DbService {
  final _db = FirebaseFirestore.instance;

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Stream of transactions for [businessId]. Optionally filtered by [shop].
  /// Sorted client-side to avoid requiring a composite Firestore index.
  Stream<List<Txn>> txnStream(String businessId, {String? shop}) {
    Query<Map<String, dynamic>> q = _db
        .collection('transactions')
        .where('businessId', isEqualTo: businessId);

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

  // ── Supplier Bills ────────────────────────────────────────────────────────

  /// Stream all supplier_bills for [businessId], sorted by date descending.
  Stream<List<SupplierBill>> allSupplierBillStream(String businessId) {
    return _db
        .collection('supplier_bills')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => SupplierBill.fromFirestore(d)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  /// Add a bill/payment and atomically adjust supplier balance.
  /// 'bill' → balance increases (we owe more); 'payment' → balance decreases.
  Future<void> addSupplierBill(SupplierBill bill) async {
    final batch = _db.batch();
    batch.set(_db.collection('supplier_bills').doc(), bill.toFirestore());
    final delta = bill.type == 'bill' ? bill.amount : -bill.amount;
    batch.update(_db.collection('suppliers').doc(bill.supplierId), {
      'balance':   FieldValue.increment(delta),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Delete a bill and reverse its balance effect on the supplier.
  Future<void> deleteSupplierBill(SupplierBill bill) async {
    final batch = _db.batch();
    batch.delete(_db.collection('supplier_bills').doc(bill.id));
    final delta = bill.type == 'bill' ? -bill.amount : bill.amount;
    batch.update(_db.collection('suppliers').doc(bill.supplierId), {
      'balance':   FieldValue.increment(delta),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
