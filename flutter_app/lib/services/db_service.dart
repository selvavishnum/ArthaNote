import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/txn.dart';
import '../models/supplier.dart';
import '../models/supplier_bill.dart';

class DbService {
  final _db = FirebaseFirestore.instance;

  // Serialises concurrent file-cache writes so two rapid addTxn calls
  // cannot both read the same stale cache and produce a duplicate.
  Future<void>? _cacheLock;

  // ── File cache helpers ────────────────────────────────────────────────────

  /// File cache location: <AppDocumentsDir>/txns_<businessId>.json
  Future<File> _cacheFile(String businessId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/txns_$businessId.json');
  }

  /// Load from file (instant, no network)
  Future<List<Txn>> loadAllTxns(String businessId) async {
    try {
      final file = await _cacheFile(businessId);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final raw = (jsonDecode(content) as List)
          .map((e) => Txn.fromJson(e as Map<String, dynamic>))
          .toList();
      // Deduplicate by ID — guards against race-condition duplicates in cache file
      final seen = <String>{};
      final list = raw.where((t) => t.id.isNotEmpty && seen.add(t.id)).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Save all txns to file
  Future<void> saveTxnsToCache(String businessId, List<Txn> txns) async {
    try {
      final file = await _cacheFile(businessId);
      await file.writeAsString(
        jsonEncode(txns.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Check if sync needed (>23h since last sync or never synced)
  Future<bool> needsSync(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('kp_sync_ts_$businessId') ?? 0;
    return DateTime.now().millisecondsSinceEpoch - ts > 23 * 3600 * 1000;
  }

  Future<void> markSynced(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('kp_sync_ts_$businessId', DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastSyncTime(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('kp_sync_ts_$businessId');
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  // ── Local cache (SharedPreferences) ─────────────────────────────────────
  // Kept for backward compat with entry_tab.dart's _loadPatterns call

  static String _txnCacheKey(String businessId) => 'kp_txs_cache_$businessId';

  /// Load all locally cached transactions (instant, no network).
  /// Delegates to file cache; falls back to SharedPreferences for legacy data.
  Future<List<Txn>> loadLocalCache(String businessId) async {
    // First try file cache (new path)
    final fromFile = await loadAllTxns(businessId);
    if (fromFile.isNotEmpty) return fromFile;

    // Fall back to old SharedPreferences cache
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

  // ── One-time Firestore fetch ───────────────────────────────────────────────
  // Full sync first time, incremental after.
  // Uses paginated get() (NOT snapshots). Full sync: 500-at-a-time pagination.
  // Incremental: query date >= (lastCursor - 2 days) for safety, merge with cache.
  Future<List<Txn>> syncFromFirebase(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final cursorMs = prefs.getInt('kp_sync_cursor_$businessId');

    if (cursorMs != null) {
      // Incremental: fetch entries with date >= (lastSync - 2 days)
      // 'date' is stored as "YYYY-MM-DD" string — use string comparison not Timestamp
      final sinceStr = DateTime.fromMillisecondsSinceEpoch(cursorMs)
          .subtract(const Duration(days: 2))
          .toIso8601String()
          .split('T')[0];
      final snap = await _db
          .collection('transactions')
          .where('businessId', isEqualTo: businessId)
          .where('date', isGreaterThanOrEqualTo: sinceStr)
          .get();

      final newTxns = snap.docs.map((d) => Txn.fromFirestore(d)).toList();
      final existing = await loadAllTxns(businessId);
      final existingIds = {for (final t in existing) t.id};
      for (final t in newTxns) {
        if (!existingIds.contains(t.id)) existing.add(t);
      }
      existing.sort((a, b) => b.date.compareTo(a.date));
      await prefs.setInt('kp_sync_cursor_$businessId', DateTime.now().millisecondsSinceEpoch);
      return existing;
    } else {
      // Full sync: paginated 500 at a time by documentId
      final allTxns = <Txn>[];
      QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;
      while (true) {
        Query<Map<String, dynamic>> q = _db
            .collection('transactions')
            .where('businessId', isEqualTo: businessId)
            .orderBy(FieldPath.documentId)
            .limit(500);
        if (lastDoc != null) q = q.startAfterDocument(lastDoc);
        final snap = await q.get();
        allTxns.addAll(snap.docs.map((d) => Txn.fromFirestore(d)));
        if (snap.docs.length < 500) break;
        lastDoc = snap.docs.last;
      }
      allTxns.sort((a, b) => b.date.compareTo(a.date));
      await prefs.setInt('kp_sync_cursor_$businessId', DateTime.now().millisecondsSinceEpoch);
      return allTxns;
    }
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Save to Firestore AND local file cache simultaneously.
  // ── Offline pending queue ─────────────────────────────────────────────────
  static const _pendingKey = 'kp_pending_queue';

  Future<void> _addToPending(Txn txn) async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_pendingKey) ?? [];
      existing.add(jsonEncode(txn.toJson()));
      await prefs.setStringList(_pendingKey, existing);
    } catch (_) {}
  }

  Future<void> _removeFromPending(String txnId) async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_pendingKey) ?? [];
      existing.removeWhere((s) {
        try { return (jsonDecode(s) as Map)['id'] == txnId; }
        catch (_) { return false; }
      });
      await prefs.setStringList(_pendingKey, existing);
    } catch (_) {}
  }

  /// Sync all pending offline entries to Firestore in parallel. Returns count synced.
  Future<int> syncPending() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingKey) ?? [];
      if (pending.isEmpty) return 0;

      // Fan out writes in parallel — 10x faster than sequential awaits.
      final results = await Future.wait(pending.map((json) async {
        try {
          final txn = Txn.fromJson(jsonDecode(json) as Map<String, dynamic>);
          await _db.collection('transactions').doc(txn.id).set(txn.toFirestore());
          return null; // success
        } catch (_) {
          return json; // still pending
        }
      }));

      final stillPending = results.whereType<String>().toList();
      await prefs.setStringList(_pendingKey, stillPending);
      return pending.length - stillPending.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> addTxn(Txn txn) async {
    final id     = txn.id.isNotEmpty ? txn.id : const Uuid().v4();
    final withId = txn.copyWith(id: id);

    // 1. Fire-and-forget Firestore write
    _db.collection('transactions').doc(id).set(withId.toFirestore())
        .then((_) => _removeFromPending(id))
        .catchError((_) => _addToPending(withId));

    // 2. Update file cache under a serial lock so two rapid addTxn calls
    //    cannot both read the same stale cache and produce a duplicate.
    _cacheLock = (_cacheLock ?? Future.value()).then((_) async {
      final existing = await loadAllTxns(txn.businessId);
      final idx = existing.indexWhere((t) => t.id == withId.id);
      if (idx != -1) {
        existing[idx] = withId;
      } else {
        existing.insert(0, withId);
      }
      await saveTxnsToCache(txn.businessId, existing);
    });
    await _cacheLock;
  }

  Future<void> deleteTxn(String id, String businessId) async {
    await _db.collection('transactions').doc(id).delete();
    final existing = await loadAllTxns(businessId);
    existing.removeWhere((t) => t.id == id);
    await saveTxnsToCache(businessId, existing);
  }

  Future<void> updateTxn(Txn txn) async {
    final data = txn.toFirestore()
      ..remove('createdAt')
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('transactions').doc(txn.id).update(data);
    final existing = await loadAllTxns(txn.businessId);
    final idx = existing.indexWhere((t) => t.id == txn.id);
    if (idx != -1) existing[idx] = txn;
    await saveTxnsToCache(txn.businessId, existing);
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
