import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/txn.dart';
import '../models/supplier.dart';
import '../models/supplier_bill.dart';

class DbService {
  final _db = FirebaseFirestore.instance;

  // ── Local cache helpers ────────────────────────────────────────────────────

  static const int _maxCached = 1000; // keep last 1000 txns in local cache

  static String _txnCacheKey(String businessId) => 'kp_txs_cache_$businessId';

  /// Load all locally cached transactions (instant, no network).
  Future<List<Txn>> loadLocalCache(String businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_txnCacheKey(businessId));
      if (raw == null || raw.isEmpty) return [];
      final list  = (jsonDecode(raw) as List<dynamic>)
          .map((m) => Txn.fromJson(m as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Persist [txns] list to local cache (fire-and-forget).
  Future<void> _saveLocalCache(String businessId, List<Txn> txns) async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final limited  = txns.length > _maxCached ? txns.sublist(0, _maxCached) : txns;
      await prefs.setString(
        _txnCacheKey(businessId),
        jsonEncode(limited.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Append one txn to local cache without reloading everything.
  Future<void> _appendToLocalCache(String businessId, Txn txn) async {
    try {
      final existing = await loadLocalCache(businessId);
      existing.insert(0, txn);
      await _saveLocalCache(businessId, existing);
    } catch (_) {}
  }

  /// Remove one txn from local cache by id.
  Future<void> _removeFromLocalCache(String businessId, String txnId) async {
    try {
      final existing = await loadLocalCache(businessId);
      existing.removeWhere((t) => t.id == txnId);
      await _saveLocalCache(businessId, existing);
    } catch (_) {}
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Cache-first stream: emits local cache instantly, then live Firestore data.
  /// Filters by [shop] if provided. Also keeps local cache up-to-date.
  Stream<List<Txn>> txnStream(String businessId, {String? shop}) async* {
    // 1. Emit from local cache immediately (zero latency)
    final cached = await loadLocalCache(businessId);
    if (cached.isNotEmpty) {
      var filtered = shop != null && shop.isNotEmpty
          ? cached.where((t) => t.shop == shop).toList()
          : cached;
      yield filtered;
    }

    // 2. Live Firestore stream (updates cache + emits fresh data)
    Query<Map<String, dynamic>> q = _db
        .collection('transactions')
        .where('businessId', isEqualTo: businessId);

    if (shop != null && shop.isNotEmpty) {
      q = q.where('shop', isEqualTo: shop);
    }

    await for (final snapshot in q.snapshots()) {
      final list = snapshot.docs.map((doc) => Txn.fromFirestore(doc)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));

      // Update local cache with full (unfiltered) list
      if (shop == null || shop.isEmpty) {
        _saveLocalCache(businessId, list); // fire-and-forget
      }

      yield list;
    }
  }

  /// Save to Firestore AND local cache simultaneously.
  Future<void> addTxn(Txn txn) async {
    // Generate id if empty so we can cache it immediately
    final id  = txn.id.isNotEmpty ? txn.id : const Uuid().v4();
    final withId = txn.id.isNotEmpty ? txn : Txn(
      id:         id,
      businessId: txn.businessId,
      shop:       txn.shop,
      shopName:   txn.shopName,
      date:       txn.date,
      type:       txn.type,
      amount:     txn.amount,
      desc:       txn.desc,
    );

    // Save to Firestore (cloud)
    await _db.collection('transactions').doc(id).set(withId.toFirestore());

    // Save to local cache immediately (so dashboard shows it without re-fetch)
    await _appendToLocalCache(txn.businessId, withId);
  }

  Future<void> deleteTxn(String id, String businessId) async {
    await _db.collection('transactions').doc(id).delete();
    await _removeFromLocalCache(businessId, id);
  }

  // ── Suppliers ─────────────────────────────────────────────────────────────

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

  Future<void> updateSupplierInfo(String id, String name, String phone) =>
      _db.collection('suppliers').doc(id).update({
        'name':      name,
        'phone':     phone,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateSupplierBalance(String id, double delta) =>
      _db.collection('suppliers').doc(id).update({
        'balance':   FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteSupplier(String id) =>
      _db.collection('suppliers').doc(id).delete();

  // ── Supplier Bills ────────────────────────────────────────────────────────

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

  /// Update a bill/payment entry and atomically re-adjust the supplier balance.
  Future<void> updateSupplierBill(SupplierBill oldBill, SupplierBill newBill) async {
    final oldDelta = oldBill.type == 'bill' ?  oldBill.amount : -oldBill.amount;
    final newDelta = newBill.type == 'bill' ?  newBill.amount : -newBill.amount;
    final adjust   = newDelta - oldDelta;
    final batch = _db.batch();
    batch.update(
      _db.collection('supplier_bills').doc(oldBill.id),
      {
        'type':   newBill.type,
        'amount': newBill.amount,
        'desc':   newBill.desc,
        'date':   Timestamp.fromDate(newBill.date),
      },
    );
    batch.update(_db.collection('suppliers').doc(oldBill.supplierId), {
      'balance':   FieldValue.increment(adjust),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
