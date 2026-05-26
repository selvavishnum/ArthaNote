import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminUser {
  final String uid;
  final String businessId;
  final String name;
  final String email;
  final String role;
  final bool isPro;
  final String bizType;
  final DateTime? createdAt;

  const AdminUser({
    required this.uid,
    required this.businessId,
    required this.name,
    required this.email,
    required this.role,
    required this.isPro,
    required this.bizType,
    this.createdAt,
  });

  factory AdminUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AdminUser(
      uid:        doc.id,
      businessId: d['businessId'] as String? ?? doc.id,
      name:       d['name']       as String? ?? 'Unknown',
      email:      d['email']      as String? ?? '',
      role:       d['role']       as String? ?? 'owner',
      isPro:      d['pro']        as bool?   ?? false,
      bizType:    d['bizType']    as String? ?? '',
      createdAt:  (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }
}

class AdminUserDetails {
  final List<Map<String, dynamic>> shops; // [{id, name, icon, type}]
  final double totalSales;
  final double totalExpense;
  final int    entryCount;
  final int    activeDays;
  final DateTime? lastActive;
  final List<double> last7DaySales; // index 0 = 6 days ago, index 6 = today

  const AdminUserDetails({
    required this.shops,
    required this.totalSales,
    required this.totalExpense,
    required this.entryCount,
    required this.activeDays,
    this.lastActive,
    required this.last7DaySales,
  });
}

class AdminDashboardStats {
  final int totalUsers;
  final int activeToday;
  final int activeThisWeek;
  final int totalEntriesEver;
  final int entriesToday;
  final int proUsers;
  final double totalSalesAllTime;

  const AdminDashboardStats({
    required this.totalUsers,
    required this.activeToday,
    required this.activeThisWeek,
    required this.totalEntriesEver,
    required this.entriesToday,
    required this.proUsers,
    required this.totalSalesAllTime,
  });
}

class AdminService {
  final _db = FirebaseFirestore.instance;

  // ── Users ─────────────────────────────────────────────────────────────────

  Stream<List<AdminUser>> usersStream() {
    return _db.collection('staff').snapshots().map((snap) {
      final list = snap.docs.map((d) => AdminUser.fromDoc(d)).toList();
      list.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return list;
    });
  }

  // ── Dashboard stats ───────────────────────────────────────────────────────

  Future<AdminDashboardStats> getDashboardStats() async {
    final now      = DateTime.now();
    final todayStart  = DateTime(now.year, now.month, now.day);
    final weekStart   = todayStart.subtract(Duration(days: now.weekday - 1));

    // 1. All users
    final usersSnap = await _db.collection('staff').get();
    final totalUsers = usersSnap.docs.length;
    final proUsers   = usersSnap.docs.where((d) => d.data()['pro'] == true).length;

    // 2. Today's transactions (to find active users today + entry count)
    final todayTxSnap = await _db
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .get();
    final activeTodayIds = todayTxSnap.docs
        .map((d) => d.data()['businessId'] as String? ?? '')
        .toSet();
    final activeToday   = activeTodayIds.length;
    final entriesToday  = todayTxSnap.docs.length;

    // 3. This week's active users
    final weekTxSnap = await _db
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .get();
    final activeWeekIds = weekTxSnap.docs
        .map((d) => d.data()['businessId'] as String? ?? '')
        .toSet();

    // 4. All-time total sales (approximate from recent 90 days to save reads)
    final ninetyDaysAgo = todayStart.subtract(const Duration(days: 90));
    final recentSnap = await _db
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(ninetyDaysAgo))
        .get();
    double totalSales = 0;
    int totalEntries = recentSnap.docs.length;
    for (final d in recentSnap.docs) {
      final t = d.data()['type'] as String? ?? '';
      if (t == 'sale' || t == 'sales') {
        totalSales += (d.data()['amount'] as num?)?.toDouble() ?? 0;
      }
    }

    return AdminDashboardStats(
      totalUsers:        totalUsers,
      activeToday:       activeToday,
      activeThisWeek:    activeWeekIds.length,
      totalEntriesEver:  totalEntries,
      entriesToday:      entriesToday,
      proUsers:          proUsers,
      totalSalesAllTime: totalSales,
    );
  }

  // ── User details (lazy, called on expand) ─────────────────────────────────

  Future<AdminUserDetails> getUserDetails(String businessId) async {
    // 1. Config (shops)
    final configDoc = await _db.collection('config').doc(businessId).get();
    final rawShops = configDoc.data()?['shops'] as Map<String, dynamic>? ?? {};
    final shops = rawShops.entries.map((e) {
      final v = e.value as Map<String, dynamic>? ?? {};
      return {
        'id':   e.key,
        'name': v['name'] as String? ?? '',
        'icon': v['icon'] as String? ?? '🏪',
        'type': v['type'] as String? ?? '',
      };
    }).toList();

    // 2. Last 90 days transactions
    final ninetyDaysAgo = DateTime.now().subtract(const Duration(days: 90));
    final txSnap = await _db
        .collection('transactions')
        .where('businessId', isEqualTo: businessId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(ninetyDaysAgo))
        .get();

    double totalSales = 0, totalExpense = 0;
    final activeDaySet  = <String>{};
    DateTime? lastActive;
    final daySales = <String, double>{};

    final now = DateTime.now();
    for (final d in txSnap.docs) {
      final data = d.data();
      final t   = data['type'] as String? ?? '';
      final amt = (data['amount'] as num?)?.toDouble() ?? 0;
      DateTime date;
      final dv = data['date'];
      if (dv is Timestamp) date = dv.toDate();
      else if (dv is String) date = DateTime.tryParse(dv) ?? now;
      else date = now;

      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      activeDaySet.add(dateStr);
      if (lastActive == null || date.isAfter(lastActive)) lastActive = date;

      if (t == 'sale' || t == 'sales') {
        totalSales += amt;
        daySales[dateStr] = (daySales[dateStr] ?? 0) + amt;
      }
      if (t == 'expense') totalExpense += amt;
    }

    // Build last 7 days sales array (index 0 = 6 days ago, index 6 = today)
    final last7 = List<double>.filled(7, 0);
    for (int i = 0; i < 7; i++) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      last7[i] = daySales[key] ?? 0;
    }

    return AdminUserDetails(
      shops:        shops,
      totalSales:   totalSales,
      totalExpense: totalExpense,
      entryCount:   txSnap.docs.length,
      activeDays:   activeDaySet.length,
      lastActive:   lastActive,
      last7DaySales: last7,
    );
  }
}
