import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class AdminUser {
  final String    uid;
  final String    businessId;
  final String    name;
  final String    email;
  final String    role;
  final bool      isPro;
  final String    bizType;
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

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

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

  factory AdminUser.fromJson(Map<String, dynamic> m) => AdminUser(
    uid:        m['uid']        as String? ?? '',
    businessId: m['businessId'] as String? ?? '',
    name:       m['name']       as String? ?? '',
    email:      m['email']      as String? ?? '',
    role:       m['role']       as String? ?? 'owner',
    isPro:      m['isPro']      as bool?   ?? false,
    bizType:    m['bizType']    as String? ?? '',
    createdAt:  m['createdAt'] != null ? DateTime.tryParse(m['createdAt'] as String) : null,
  );

  Map<String, dynamic> toJson() => {
    'uid':        uid,
    'businessId': businessId,
    'name':       name,
    'email':      email,
    'role':       role,
    'isPro':      isPro,
    'bizType':    bizType,
    'createdAt':  createdAt?.toIso8601String(),
  };
}

class AdminUserDetails {
  final List<Map<String, dynamic>> shops;
  final double    totalSales;
  final double    totalExpense;
  final int       entryCount;
  final int       activeDays;
  final DateTime? lastActive;
  final List<double> last7DaySales;

  const AdminUserDetails({
    required this.shops,
    required this.totalSales,
    required this.totalExpense,
    required this.entryCount,
    required this.activeDays,
    this.lastActive,
    required this.last7DaySales,
  });

  factory AdminUserDetails.fromJson(Map<String, dynamic> m) => AdminUserDetails(
    shops:        (m['shops'] as List<dynamic>? ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    totalSales:   (m['totalSales']   as num?)?.toDouble() ?? 0,
    totalExpense: (m['totalExpense'] as num?)?.toDouble() ?? 0,
    entryCount:   m['entryCount']   as int?    ?? 0,
    activeDays:   m['activeDays']   as int?    ?? 0,
    lastActive:   m['lastActive'] != null ? DateTime.tryParse(m['lastActive'] as String) : null,
    last7DaySales: (m['last7DaySales'] as List<dynamic>? ?? [])
                    .map((e) => (e as num).toDouble()).toList(),
  );

  Map<String, dynamic> toJson() => {
    'shops':        shops,
    'totalSales':   totalSales,
    'totalExpense': totalExpense,
    'entryCount':   entryCount,
    'activeDays':   activeDays,
    'lastActive':   lastActive?.toIso8601String(),
    'last7DaySales': last7DaySales,
  };
}

class AdminDashboardStats {
  final int    totalUsers;
  final int    activeToday;
  final int    activeThisWeek;
  final int    totalEntriesEver;
  final int    entriesToday;
  final int    proUsers;
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

  factory AdminDashboardStats.fromJson(Map<String, dynamic> m) => AdminDashboardStats(
    totalUsers:        m['totalUsers']        as int?    ?? 0,
    activeToday:       m['activeToday']       as int?    ?? 0,
    activeThisWeek:    m['activeThisWeek']    as int?    ?? 0,
    totalEntriesEver:  m['totalEntriesEver']  as int?    ?? 0,
    entriesToday:      m['entriesToday']      as int?    ?? 0,
    proUsers:          m['proUsers']          as int?    ?? 0,
    totalSalesAllTime: (m['totalSalesAllTime'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'totalUsers':        totalUsers,
    'activeToday':       activeToday,
    'activeThisWeek':    activeThisWeek,
    'totalEntriesEver':  totalEntriesEver,
    'entriesToday':      entriesToday,
    'proUsers':          proUsers,
    'totalSalesAllTime': totalSalesAllTime,
  };
}

// ── AdminService ──────────────────────────────────────────────────────────────

class AdminService {
  final _db = FirebaseFirestore.instance;

  static const _syncTsKey = 'admin_sync_ts';

  // ── File cache helpers ────────────────────────────────────────────────────

  Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  Future<T?> _readJson<T>(String name, T Function(dynamic) parse) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return null;
      return parse(jsonDecode(await f.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String name, dynamic data) async {
    try {
      final f = await _file(name);
      await f.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  // ── Sync timestamp ────────────────────────────────────────────────────────

  Future<bool> needsSync() async {
    final prefs = await SharedPreferences.getInstance();
    final ts    = prefs.getInt(_syncTsKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - ts > 23 * 3600 * 1000;
  }

  Future<void> markSynced() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncTsKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts    = prefs.getInt(_syncTsKey);
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  // ── Users cache ───────────────────────────────────────────────────────────

  Future<List<AdminUser>> loadUsersFromCache() async {
    final list = await _readJson<List<AdminUser>>(
      'admin_users.json',
      (raw) => (raw as List).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList(),
    );
    return list ?? [];
  }

  Future<void> _saveUsersToCache(List<AdminUser> users) =>
      _writeJson('admin_users.json', users.map((u) => u.toJson()).toList());

  // ── Stats cache ───────────────────────────────────────────────────────────

  Future<AdminDashboardStats?> loadStatsFromCache() =>
      _readJson<AdminDashboardStats>(
        'admin_stats.json',
        (raw) => AdminDashboardStats.fromJson(raw as Map<String, dynamic>),
      );

  Future<void> _saveStatsToCache(AdminDashboardStats s) =>
      _writeJson('admin_stats.json', s.toJson());

  // ── User details cache ────────────────────────────────────────────────────

  Future<AdminUserDetails?> loadUserDetailsFromCache(String businessId) =>
      _readJson<AdminUserDetails>(
        'admin_detail_$businessId.json',
        (raw) => AdminUserDetails.fromJson(raw as Map<String, dynamic>),
      );

  Future<void> _saveUserDetailsToCache(String businessId, AdminUserDetails d) =>
      _writeJson('admin_detail_$businessId.json', d.toJson());

  // ── Firestore fetchers (called only when cache is stale) ──────────────────

  Future<List<AdminUser>> _fetchUsersFromFirestore() async {
    final snap = await _db.collection('staff').get();
    final list = snap.docs.map((d) => AdminUser.fromDoc(d)).toList();
    list.sort((a, b) {
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return list;
  }

  Future<AdminDashboardStats> _fetchStatsFromFirestore() async {
    final now         = DateTime.now();
    final todayStart  = DateTime(now.year, now.month, now.day);
    final weekStart   = todayStart.subtract(Duration(days: now.weekday - 1));
    final ninetyAgo   = todayStart.subtract(const Duration(days: 90));

    final usersSnap = await _db.collection('staff').get();
    final totalUsers = usersSnap.docs.length;
    final proUsers   = usersSnap.docs.where((d) => d.data()['pro'] == true).length;

    final todaySnap = await _db
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .get();
    final activeTodayIds  = todaySnap.docs.map((d) => d.data()['businessId'] as String? ?? '').toSet();

    final weekSnap = await _db
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .get();
    final activeWeekIds = weekSnap.docs.map((d) => d.data()['businessId'] as String? ?? '').toSet();

    final recentSnap = await _db
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(ninetyAgo))
        .get();
    double totalSales = 0;
    for (final d in recentSnap.docs) {
      final t = d.data()['type'] as String? ?? '';
      if (t == 'sale' || t == 'sales') totalSales += (d.data()['amount'] as num?)?.toDouble() ?? 0;
    }

    return AdminDashboardStats(
      totalUsers:        totalUsers,
      activeToday:       activeTodayIds.length,
      activeThisWeek:    activeWeekIds.length,
      totalEntriesEver:  recentSnap.docs.length,
      entriesToday:      todaySnap.docs.length,
      proUsers:          proUsers,
      totalSalesAllTime: totalSales,
    );
  }

  Future<AdminUserDetails> _fetchUserDetailsFromFirestore(String businessId) async {
    final configDoc  = await _db.collection('config').doc(businessId).get();
    final rawShops   = configDoc.data()?['shops'] as Map<String, dynamic>? ?? {};
    final shops = rawShops.entries.map((e) {
      final v = e.value as Map<String, dynamic>? ?? {};
      return {'id': e.key, 'name': v['name'] as String? ?? '', 'icon': v['icon'] as String? ?? '🏪', 'type': v['type'] as String? ?? ''};
    }).toList();

    final ninetyAgo = DateTime.now().subtract(const Duration(days: 90));
    final txSnap    = await _db
        .collection('transactions')
        .where('businessId', isEqualTo: businessId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(ninetyAgo))
        .get();

    double totalSales = 0, totalExpense = 0;
    final activeDaySet = <String>{};
    DateTime? lastActive;
    final daySales = <String, double>{};
    final now = DateTime.now();

    for (final d in txSnap.docs) {
      final data = d.data();
      final t    = data['type'] as String? ?? '';
      final amt  = (data['amount'] as num?)?.toDouble() ?? 0;
      DateTime date;
      final dv = data['date'];
      if (dv is Timestamp)      date = dv.toDate();
      else if (dv is String)    date = DateTime.tryParse(dv) ?? now;
      else                      date = now;

      final ds = DateFormat('yyyy-MM-dd').format(date);
      activeDaySet.add(ds);
      if (lastActive == null || date.isAfter(lastActive)) lastActive = date;
      if (t == 'sale' || t == 'sales') { totalSales += amt; daySales[ds] = (daySales[ds] ?? 0) + amt; }
      if (t == 'expense') totalExpense += amt;
    }

    final last7 = List<double>.filled(7, 0);
    for (int i = 0; i < 7; i++) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i));
      last7[i] = daySales[DateFormat('yyyy-MM-dd').format(d)] ?? 0;
    }

    return AdminUserDetails(
      shops: shops, totalSales: totalSales, totalExpense: totalExpense,
      entryCount: txSnap.docs.length, activeDays: activeDaySet.length,
      lastActive: lastActive, last7DaySales: last7,
    );
  }

  // ── Public API (cache-first) ──────────────────────────────────────────────

  /// Load users: from cache immediately, then sync if stale.
  /// [onFresh] is called after a successful Firestore sync.
  Future<List<AdminUser>> loadUsers({void Function(List<AdminUser>)? onFresh}) async {
    final cached = await loadUsersFromCache();
    if (await needsSync()) {
      try {
        final fresh = await _fetchUsersFromFirestore();
        await _saveUsersToCache(fresh);
        onFresh?.call(fresh);
        return fresh;
      } catch (_) {}
    }
    return cached;
  }

  /// Load dashboard stats: from cache immediately, sync if stale.
  Future<AdminDashboardStats?> loadStats({void Function(AdminDashboardStats)? onFresh}) async {
    final cached = await loadStatsFromCache();
    if (await needsSync()) {
      try {
        final fresh = await _fetchStatsFromFirestore();
        await _saveStatsToCache(fresh);
        onFresh?.call(fresh);
        return fresh;
      } catch (_) {}
    }
    return cached;
  }

  /// Load user details: from cache if exists, otherwise fetch once from Firestore.
  /// Details are cached forever (only refreshed on full syncAll).
  Future<AdminUserDetails> getUserDetails(String businessId) async {
    final cached = await loadUserDetailsFromCache(businessId);
    if (cached != null) return cached;
    final fresh = await _fetchUserDetailsFromFirestore(businessId);
    await _saveUserDetailsToCache(businessId, fresh);
    return fresh;
  }

  /// Force full sync from Firestore — call on manual "Sync" button.
  /// Fetches users + stats. User details are refreshed lazily on expand.
  Future<({List<AdminUser> users, AdminDashboardStats stats})> syncAll() async {
    final users = await _fetchUsersFromFirestore();
    final stats = await _fetchStatsFromFirestore();
    await _saveUsersToCache(users);
    await _saveStatsToCache(stats);
    await markSynced();
    return (users: users, stats: stats);
  }
}
