import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/construction_project.dart';
import '../models/construction_entry.dart';

/// Firestore CRUD for the construction module: projects (fc_projects) and their
/// ledger entries (construction_entries). Kept separate from the main ledger
/// because construction is project-scoped, not shop-scoped.
class ConstructionService {
  final _db = FirebaseFirestore.instance;

  // ── Projects ────────────────────────────────────────────────────────────
  Stream<List<ConstructionProject>> projectsStream(String businessId) {
    return _db
        .collection('construction_projects')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((s) => s.docs.map(ConstructionProject.fromFirestore).toList());
  }

  Future<String> addProject(ConstructionProject p) async {
    final id = p.id.isNotEmpty ? p.id : const Uuid().v4();
    await _db.collection('construction_projects').doc(id).set(p.toFirestore());
    return id;
  }

  Future<void> updateProject(ConstructionProject p) =>
      _db.collection('construction_projects').doc(p.id).update(p.toFirestore());

  /// Deletes a project AND all of its ledger entries (batched).
  Future<void> deleteProject(String projectId) async {
    while (true) {
      final snap = await _db
          .collection('construction_entries')
          .where('projectId', isEqualTo: projectId)
          .limit(400)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) break;
    }
    await _db.collection('construction_projects').doc(projectId).delete();
  }

  // ── Entries ─────────────────────────────────────────────────────────────
  Stream<List<ConstructionEntry>> entriesStream(String projectId) {
    return _db
        .collection('construction_entries')
        .where('projectId', isEqualTo: projectId)
        .snapshots()
        .map((s) {
      final list = s.docs.map(ConstructionEntry.fromFirestore).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Future<void> addEntry(ConstructionEntry e) async {
    final id = e.id.isNotEmpty ? e.id : const Uuid().v4();
    await _db.collection('construction_entries').doc(id).set(e.toFirestore());
  }

  Future<void> deleteEntry(String id) =>
      _db.collection('construction_entries').doc(id).delete();

  // ── Recent material rates (learned from the builder's own entries) ─────────
  static const _ratesKey = 'kp_construction_rates';

  /// Remembers the last rate used for a material so the next Material entry
  /// pre-fills the builder's own price instead of the catalog default.
  Future<void> saveRecentRate(String material, double rate) async {
    if (material.trim().isEmpty || rate <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final map = _readRates(prefs);
    map[material.trim().toLowerCase()] = rate;
    await prefs.setString(_ratesKey, jsonEncode(map));
  }

  Future<Map<String, double>> recentRates() async {
    final prefs = await SharedPreferences.getInstance();
    return _readRates(prefs);
  }

  Map<String, double> _readRates(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_ratesKey);
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }
}

/// Rolled-up figures for a project's Summary tab.
class ProjectSummary {
  final double totalIncome;   // client entries
  final double totalExpense;  // material + labour + contractor
  final double pendingIn;     // client entries on credit (yet to collect)
  final double pendingOut;    // expense entries on credit (yet to pay)
  final Map<String, double> expenseByType; // material/labour/contractor → sum

  const ProjectSummary({
    this.totalIncome  = 0,
    this.totalExpense = 0,
    this.pendingIn    = 0,
    this.pendingOut   = 0,
    this.expenseByType = const {},
  });

  double get netProfit => totalIncome - totalExpense;

  static ProjectSummary from(List<ConstructionEntry> entries) {
    double income = 0, expense = 0, pIn = 0, pOut = 0;
    final byType = <String, double>{};
    for (final e in entries) {
      if (e.isIncome) {
        income += e.amount;
        if (!e.paidNow) pIn += e.amount;
      } else {
        expense += e.amount;
        byType[e.type] = (byType[e.type] ?? 0) + e.amount;
        if (!e.paidNow) pOut += e.amount;
      }
    }
    return ProjectSummary(
      totalIncome:   income,
      totalExpense:  expense,
      pendingIn:     pIn,
      pendingOut:    pOut,
      expenseByType: byType,
    );
  }
}
