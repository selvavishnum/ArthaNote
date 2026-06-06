import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../models/shop.dart';
import '../models/supplier.dart';
import '../models/payment_reminder.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/reminder_service.dart';
import 'shop_detail_screen.dart';
import 'reminders_screen.dart';

// ── Formatting helpers ────────────────────────────────────────────────────────
final _inrFmt = NumberFormat('#,##,##0', 'en_IN');
String rupee(double v) => '₹${_inrFmt.format(v.abs())}';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _db            = DbService();
  int  _period         = 0; // 0=today 1=yesterday 2=week 3=month
  bool _alertDismissed = false;
  String? _dismissedDate;
  int _streakCount     = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStreak());
  }

  Future<void> _loadStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('slv_streak_count') ?? 0;
    if (mounted) setState(() => _streakCount = count);
  }

  Future<void> _updateStreak(List<Txn> all) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final yesterday = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
    final lastDate = prefs.getString('slv_streak_date') ?? '';

    // Find last entry date
    if (all.isEmpty) return;
    final sortedTxns = List<Txn>.from(all)
      ..sort((a, b) => b.date.compareTo(a.date));
    final lastEntryDate = DateFormat('yyyy-MM-dd').format(sortedTxns.first.date);

    int count = prefs.getInt('slv_streak_count') ?? 0;

    if (lastDate == today) return; // already updated today

    if (lastEntryDate == today || lastEntryDate == yesterday) {
      if (lastDate == yesterday || lastDate == today) {
        count++;
      } else {
        count = 1;
      }
    } else {
      count = 0;
    }

    await prefs.setInt('slv_streak_count', count);
    await prefs.setString('slv_streak_date', today);
    if (mounted) setState(() => _streakCount = count);
  }

  // ── Shop Health Score ───────────────────────────────────────────────────────
  Map<String, dynamic> _shopHealthScore(String shopId, List<Txn> allTxns) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Last 7 days vs prev 7 days sales trend
    final last7Start = today.subtract(const Duration(days: 7));
    final prev7Start = today.subtract(const Duration(days: 14));

    final last7Sales = allTxns
        .where((tx) => tx.shop == shopId &&
            tx.type == 'sale' &&
            !tx.date.isBefore(last7Start) && tx.date.isBefore(today))
        .fold(0.0, (s, x) => s + x.amount);

    final prev7Sales = allTxns
        .where((tx) => tx.shop == shopId &&
            tx.type == 'sale' &&
            !tx.date.isBefore(prev7Start) && tx.date.isBefore(last7Start))
        .fold(0.0, (s, x) => s + x.amount);

    // Expense ratio last 30 days
    final last30Start = today.subtract(const Duration(days: 30));
    final last30Sales = allTxns
        .where((tx) => tx.shop == shopId &&
            tx.type == 'sale' &&
            !tx.date.isBefore(last30Start))
        .fold(0.0, (s, x) => s + x.amount);
    final last30Exp = allTxns
        .where((tx) => tx.shop == shopId &&
            tx.type == 'expense' &&
            !tx.date.isBefore(last30Start))
        .fold(0.0, (s, x) => s + x.amount);

    // Days active last 30 days
    final activeDays = allTxns
        .where((tx) => tx.shop == shopId && !tx.date.isBefore(last30Start))
        .map((tx) => DateFormat('yyyy-MM-dd').format(tx.date))
        .toSet()
        .length;

    int score = 50;
    final breakdown = <String>[];

    // Sales trend
    int trendPts = 0;
    if (prev7Sales > 0) {
      final growth = (last7Sales - prev7Sales) / prev7Sales;
      if (growth > 0.10) {
        trendPts = 20;
        breakdown.add('📈 Sales up ${(growth * 100).toStringAsFixed(0)}% (+20pts)');
      } else if (growth < -0.10) {
        trendPts = -20;
        breakdown.add('📉 Sales down ${(growth.abs() * 100).toStringAsFixed(0)}% (-20pts)');
      } else {
        breakdown.add('➡️ Sales stable (0pts)');
      }
    } else {
      breakdown.add('➡️ No prev week data (0pts)');
    }
    score += trendPts;

    // Expense ratio
    int expPts = 0;
    if (last30Sales > 0) {
      final ratio = last30Exp / last30Sales;
      if (ratio < 0.50) {
        expPts = 15;
        breakdown.add('✅ Low expense ratio ${(ratio * 100).toStringAsFixed(0)}% (+15pts)');
      } else if (ratio > 0.80) {
        expPts = -15;
        breakdown.add('⚠️ High expense ratio ${(ratio * 100).toStringAsFixed(0)}% (-15pts)');
      } else {
        breakdown.add('🔸 Expense ratio ${(ratio * 100).toStringAsFixed(0)}% (0pts)');
      }
    } else {
      breakdown.add('🔸 No sales data for ratio (0pts)');
    }
    score += expPts;

    // Days active
    int activePts = 0;
    if (activeDays > 22) {
      activePts = 15;
      breakdown.add('🟢 Active $activeDays days (+15pts)');
    } else if (activeDays < 10) {
      activePts = -15;
      breakdown.add('🔴 Active only $activeDays days (-15pts)');
    } else {
      breakdown.add('🟡 Active $activeDays days (0pts)');
    }
    score += activePts;

    String badge;
    String label;
    Color  color;
    if (score >= 75) {
      badge = '💚';
      label = 'Good Performance';
      color = const Color(0xFF16A34A);
    } else if (score >= 50) {
      badge = '💛';
      label = 'Moderate Performance';
      color = const Color(0xFFD97706);
    } else {
      badge = '🔴';
      label = 'Low Performance';
      color = const Color(0xFFDC2626);
    }

    return {
      'score': score,
      'badge': badge,
      'label': label,
      'color': color,
      'breakdown': breakdown,
    };
  }

  DateTimeRange _range() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 1:
        final y = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: y, end: today);
      case 2:
        return DateTimeRange(
            start: today.subtract(const Duration(days: 7)), end: now);
      case 3:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      default:
        return DateTimeRange(start: today, end: now);
    }
  }

  List<Txn> _filter(List<Txn> all, AppProvider p) {
    final r = _range();
    return all.where((txn) {
      final inRange = !txn.date.isBefore(r.start) && !txn.date.isAfter(r.end);
      final inShop  = p.selectedShop.isEmpty || txn.shop == p.selectedShop;
      return inRange && inShop;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p       = context.watch<AppProvider>();
    final l       = p.lang;
    final periods = [
      t('today', l),
      t('yesterday', l),
      t('this_week', l),
      t('this_month', l),
    ];

    final all    = p.txns;
    // Update streak in background
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStreak(all));

    final txns    = _filter(all, p);
    final sales   = txns.where((x) => x.type == 'sale')
        .fold(0.0, (s, x) => s + x.amount);
    final expense = txns.where((x) => x.type == 'expense' || x.type == 'payment')
        .fold(0.0, (s, x) => s + x.amount);
    final net = sales - expense;

    // Last 7 days overdraft check
    final now7 = DateTime.now();
    final sevenDaysAgo = DateTime(now7.year, now7.month, now7.day).subtract(const Duration(days: 7));
    final last7Txns = all.where((tx) => !tx.date.isBefore(sevenDaysAgo)).toList();
    final last7Sales = last7Txns.where((x) => x.type == 'sale').fold(0.0, (s, x) => s + x.amount);
    final last7Exp   = last7Txns.where((x) => x.type == 'expense').fold(0.0, (s, x) => s + x.amount);
    final last7Net   = last7Sales - last7Exp;
    final showOverdraft = last7Net < 0;

    // Most sold
    String mostSold = '';
    final saleTxns = txns.where((x) => x.type == 'sale').toList();
    if (saleTxns.isNotEmpty) {
      final freq = <String, int>{};
      for (final tx in saleTxns) {
        if (tx.desc.isNotEmpty) freq[tx.desc] = (freq[tx.desc] ?? 0) + 1;
      }
      if (freq.isNotEmpty) {
        mostSold = freq.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
      }
    }

    // Today entries for AI alert
    final now         = DateTime.now();
    final todayStart  = DateTime(now.year, now.month, now.day);
    final todayCount  = all.where((tx) => !tx.date.isBefore(todayStart)).length;
    final todayKey    = DateFormat('yyyy-MM-dd').format(now);
    final isEvening   = now.hour >= 18;
    final showAiAlert = isEvening && todayCount == 0 &&
        (_dismissedDate != todayKey);

    // AI: find patterns (entries that usually appear — last 14 days freq)
    final missingItems = _detectMissingPatterns(all);

    return RefreshIndicator(
          color: kPrimary,
          backgroundColor: Colors.white,
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
            children: [

              // Entry count + Streak + Refresh
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text(
                      '${all.length} ${t("entries", l)} · synced',
                      style: const TextStyle(
                        color: kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_streakCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFBD38D)),
                        ),
                        child: Text(
                          '🔥 $_streakCount-day streak',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  GestureDetector(
                    onTap: () => context.read<AppProvider>().syncNow(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(children: [
                        Icon(Icons.refresh, color: kPrimary, size: 14),
                        SizedBox(width: 4),
                        Text('Refresh',
                            style: TextStyle(
                                color: kPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Period chips
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: periods.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => setState(() => _period = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _period == i ? kPrimary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _period == i
                              ? kPrimary
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          periods[i],
                          style: TextStyle(
                            color: _period == i
                                ? Colors.white
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // No-entries warning
              if (txns.isEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFBBF24)),
                  ),
                  child: Row(children: [
                    const Text('⚠️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No entries — scan ledger or add manually',
                        style: TextStyle(
                          color: Colors.amber.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ]),
                ),

              // Upcoming payments card (personal mode only)
              if (p.isPersonal)
                _UpcomingPaymentsCard(onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RemindersScreen()))),

              // 4-box stat grid
              Row(children: [
                Expanded(
                    child: _StatBox(
                        label: p.isPersonal ? 'TO RECEIVE' : 'SALES',
                        value: rupee(sales),
                        valueColor: kSecondary,
                        icon: '💰')),
                const SizedBox(width: 10),
                Expanded(
                    child: _StatBox(
                        label: p.isPersonal ? 'TO PAY' : 'EXPENSES',
                        value: rupee(expense),
                        valueColor: kRed,
                        icon: p.isPersonal ? '💸' : '📉')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _StatBox(
                        label: p.isPersonal
                            ? 'BALANCE'
                            : t('net_profit', l).toUpperCase(),
                        value: net >= 0
                            ? '+ ${rupee(net)}'
                            : '− ${rupee(net)}',
                        valueColor: net >= 0 ? kSecondary : kRed,
                        icon: net >= 0 ? '📈' : '📊')),
                const SizedBox(width: 10),
                Expanded(
                    child: _StatBox(
                        label: t('most_sold', l).toUpperCase(),
                        value: mostSold.isEmpty ? 'NONE' : mostSold,
                        valueColor:
                            mostSold.isEmpty ? kAmber : kText,
                        icon: '⭐',
                        valueSmall: mostSold.isNotEmpty)),
              ]),

              const SizedBox(height: 12),

              // ── Overdraft Warning ─────────────────────────────────────────
              if (showOverdraft)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      '⚠️ Net loss last 7 days: ${rupee(last7Net.abs())}. Review expenses.',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                    )),
                  ]),
                ),

              const SizedBox(height: 4),

              // ── Shop Summary ─────────────────────────────────────────────
              _SectionHeader(
                icon: '🏪',
                title: t('shop_summary', l).toUpperCase(),
                trailing: 'TAP FOR 360° REPORT',
              ),
              const SizedBox(height: 8),

              if (p.syncing && p.shops.isEmpty)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: kPrimary),
                ))
              else if (p.shops.isEmpty)
                _EmptyCard(text: 'No shops set up yet')
              else
                ...p.shops.values.map((shop) {
                  final shopTxns =
                      txns.where((x) => x.shop == shop.id).toList();
                  final shopSales = shopTxns
                      .where((x) => x.type == 'sale')
                      .fold(0.0, (s, x) => s + x.amount);
                  final shopExp = shopTxns
                      .where((x) => x.type == 'expense')
                      .fold(0.0, (s, x) => s + x.amount);
                  final shopPay = shopTxns
                      .where((x) => x.type == 'payment')
                      .fold(0.0, (s, x) => s + x.amount);
                  final healthData = _shopHealthScore(shop.id, all);
                  return _ShopSummaryCard(
                    shop: shop,
                    entryCount: shopTxns.length,
                    sales: shopSales,
                    expense: shopExp,
                    net: shopSales - shopExp - shopPay,
                    l: l,
                    healthBadge: healthData['badge'] as String,
                    healthLabel: healthData['label'] as String,
                    healthColor: healthData['color'] as Color,
                    healthScore: healthData['score'] as int,
                    healthBreakdown: List<String>.from(healthData['breakdown'] as List),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              ShopDetailScreen(shop: shop)),
                    ),
                  );
                }),

              const SizedBox(height: 16),

              // ── Supplier Alerts ──────────────────────────────────────────
              _SupplierAlertsSection(businessId: p.businessId, db: _db),

              const SizedBox(height: 16),

              // ── Daily Reconciliation ─────────────────────────────────────
              _DailyReconcileSection(
                  txns: all, businessId: p.businessId),

              const SizedBox(height: 16),

              // ── AI Missing Entry Alert ────────────────────────────────────
              _AiAlertSection(
                show:          showAiAlert || missingItems.isNotEmpty,
                todayCount:    todayCount,
                missingItems:  missingItems,
                onDismiss:     () => setState(() => _dismissedDate = todayKey),
                businessId:    p.businessId,
                shops:         p.shops,
                db:            _db,
              ),
            ],
          ),
        );
  }

  // Detect frequently occurring descriptions that are missing today
  List<Map<String, dynamic>> _detectMissingPatterns(List<Txn> all) {
    final now        = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final since      = todayStart.subtract(const Duration(days: 14));

    // Get past 14 days txns (excluding today)
    final past = all.where((tx) =>
        !tx.date.isBefore(since) && tx.date.isBefore(todayStart)).toList();

    // Frequency map: desc+type+shop → count of days appeared
    final dayFreq = <String, Set<String>>{};
    final meta    = <String, Map<String, dynamic>>{};
    for (final tx in past) {
      if (tx.desc.isEmpty) continue;
      final key = '${tx.desc}|${tx.type}|${tx.shop}';
      dayFreq.putIfAbsent(key, () => {});
      dayFreq[key]!.add(DateFormat('yyyy-MM-dd').format(tx.date));
      meta[key] = {
        'desc':     tx.desc,
        'type':     tx.type,
        'shop':     tx.shop,
        'shopName': tx.shopName,
      };
    }

    // Get today's descs
    final todayDescs = all
        .where((tx) => !tx.date.isBefore(todayStart))
        .map((tx) => tx.desc)
        .toSet();

    // Find items appearing 3+ days in last 14 that are missing today
    final missing = <Map<String, dynamic>>[];
    for (final entry in dayFreq.entries) {
      if (entry.value.length >= 3 &&
          !todayDescs.contains(meta[entry.key]!['desc'])) {
        missing.add({
          ...meta[entry.key]!,
          'days': entry.value.length,
        });
      }
    }

    missing.sort((a, b) =>
        (b['days'] as int).compareTo(a['days'] as int));
    return missing.take(6).toList();
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String icon;
  final String title;
  final String trailing;
  const _SectionHeader(
      {required this.icon, required this.title, this.trailing = ''});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    color: kPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0)),
          ]),
          if (trailing.isNotEmpty)
            Text(trailing,
                style: const TextStyle(
                    color: kMuted, fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      );
}

// ── Stat box ──────────────────────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color  valueColor;
  final String icon;
  final bool   valueSmall;

  const _StatBox({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.icon,
    this.valueSmall = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: valueSmall ? 13 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      );
}

// ── Shop summary card ─────────────────────────────────────────────────────────
class _ShopSummaryCard extends StatelessWidget {
  final Shop     shop;
  final int      entryCount;
  final double   sales;
  final double   expense;
  final double   net;
  final String   l;
  final String   healthBadge;
  final String   healthLabel;
  final Color    healthColor;
  final int      healthScore;
  final List<String> healthBreakdown;
  final VoidCallback onTap;

  const _ShopSummaryCard({
    required this.shop,
    required this.entryCount,
    required this.sales,
    required this.expense,
    required this.net,
    required this.l,
    required this.healthBadge,
    required this.healthLabel,
    required this.healthColor,
    required this.healthScore,
    required this.healthBreakdown,
    required this.onTap,
  });

  void _showHealthSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text('${shop.icon} ${shop.name} — Health Report',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: healthColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: healthColor.withOpacity(0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(healthBadge, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(healthLabel,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: healthColor)),
                Text('Score: $healthScore / 100',
                    style: const TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          ...healthBreakdown.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(item, style: const TextStyle(fontSize: 13, color: kText)),
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: kCardShadow,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text(shop.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(shop.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: kText)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _showHealthSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: healthColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: healthColor.withOpacity(0.25)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(healthBadge, style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 3),
                          Text(healthLabel,
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: healthColor)),
                        ]),
                      ),
                    ),
                  ]),
                  Row(children: [
                    Text('$entryCount ${t("entries", l)}',
                        style: const TextStyle(
                            color: kMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios,
                        color: kMuted, size: 11),
                  ]),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                _MiniStat(
                    label: t('sales', l),
                    value: rupee(sales),
                    color: kSecondary),
                const SizedBox(width: 16),
                _MiniStat(
                    label: t('expense', l),
                    value: rupee(expense),
                    color: kRed),
                const SizedBox(width: 16),
                _MiniStat(
                    label: t('net', l),
                    value: rupee(net),
                    color: net >= 0 ? kSecondary : kRed),
              ]),
              const SizedBox(height: 6),
              const Text('Tap → 360° report',
                  style: TextStyle(
                      color: kMuted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic)),
            ]),
          ),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      );
}

// ── Empty placeholder card ───────────────────────────────────────────────────
class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: kCardShadow,
        ),
        child: Center(
            child: Text(text,
                style: const TextStyle(color: kMuted, fontSize: 13))),
      );
}

// ── Supplier Alerts Section ───────────────────────────────────────────────────
class _SupplierAlertsSection extends StatelessWidget {
  final String    businessId;
  final DbService db;
  const _SupplierAlertsSection(
      {required this.businessId, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Supplier>>(
      stream: db.supplierStream(businessId),
      builder: (ctx, snap) {
        final suppliers = snap.data ?? [];
        final dues      = suppliers.where((s) => s.balance > 0).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(icon: '⚠️', title: 'SUPPLIER ALERTS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: kCardShadow,
              ),
              child: dues.isEmpty
                  ? const Row(children: [
                      Text('✓  All supplier balances OK',
                          style: TextStyle(
                              color: kSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ])
                  : Column(
                      children: dues.take(5).map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(s.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kRed.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Due ${rupee(s.balance)}',
                                style: const TextStyle(
                                    color: kRed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ── Daily Reconciliation Section ──────────────────────────────────────────────
class _DailyReconcileSection extends StatelessWidget {
  final List<Txn> txns;
  final String    businessId;
  const _DailyReconcileSection(
      {required this.txns, required this.businessId});

  @override
  Widget build(BuildContext context) {
    final now        = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final today      = txns.where((tx) => !tx.date.isBefore(todayStart)).toList();
    final sales      = today
        .where((x) => x.type == 'sale')
        .fold(0.0, (s, x) => s + x.amount);
    final expense    = today
        .where((x) => x.type == 'expense')
        .fold(0.0, (s, x) => s + x.amount);
    final net        = sales - expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(icon: '📊', title: 'DAILY RECONCILIATION'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: kCardShadow,
          ),
          child: today.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No entries yet',
                        style:
                            TextStyle(color: kMuted, fontSize: 13)),
                  ),
                )
              : Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Today ${DateFormat("dd MMM").format(now)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      Text(
                        '${today.length} entries',
                        style: const TextStyle(
                            color: kMuted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _ReconcileItem(
                            label: 'Sales',
                            value: rupee(sales),
                            color: kSecondary)),
                    Expanded(
                        child: _ReconcileItem(
                            label: 'Expenses',
                            value: rupee(expense),
                            color: kRed)),
                    Expanded(
                        child: _ReconcileItem(
                            label: 'Net',
                            value: rupee(net),
                            color: net >= 0 ? kSecondary : kRed)),
                  ]),
                ]),
        ),
      ],
    );
  }
}

class _ReconcileItem extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _ReconcileItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
      ]);
}

// ── AI Missing Entry Alert Section ───────────────────────────────────────────
class _AiAlertSection extends StatelessWidget {
  final bool                       show;
  final int                        todayCount;
  final List<Map<String, dynamic>> missingItems;
  final VoidCallback               onDismiss;
  final String                     businessId;
  final Map<String, Shop>          shops;
  final DbService                  db;

  const _AiAlertSection({
    required this.show,
    required this.todayCount,
    required this.missingItems,
    required this.onDismiss,
    required this.businessId,
    required this.shops,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    if (!show && missingItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(icon: '🧠', title: 'AI MISSING ENTRY ALERT'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: kCardShadow,
          ),
          child: Column(
            children: [
              if (show)
                Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFBBF24)),
                  ),
                  child: Row(children: [
                    const Text('🤔', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${missingItems.length} entries you usually add are missing today.',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Did you forget them?',
                            style: TextStyle(
                                color: Colors.amber.shade700,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: onDismiss,
                      child: const Icon(Icons.close,
                          size: 16, color: kMuted),
                    ),
                  ]),
                ),

              if (missingItems.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: missingItems.length,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  itemBuilder: (ctx, i) {
                    final item     = missingItems[i];
                    final shopName = item['shopName'] as String;
                    final desc     = item['desc'] as String;
                    final type     = item['type'] as String;
                    final days     = item['days'] as int;
                    final typeColor = type == 'sale'
                        ? kSecondary
                        : type == 'expense'
                            ? kRed
                            : kAmber;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(desc,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              Text(
                                '${shopName.isNotEmpty ? "$shopName · " : ""}$type · Usually $days times/2 weeks',
                                style: const TextStyle(
                                    color: kMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () =>
                              _quickAdd(ctx, item, businessId, db),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            minimumSize: const Size(60, 34),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8)),
                            textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                          child: const Text('+ Add'),
                        ),
                      ]),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _quickAdd(BuildContext context,
      Map<String, dynamic> item, String businessId, DbService db) async {
    final desc = item['desc'] as String;
    final type = item['type'] as String;
    final shop = item['shop'] as String;
    final shopName = item['shopName'] as String;

    final amtCtrl = TextEditingController();

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('Quick Add: $desc',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: kPrimary)),
          const SizedBox(height: 4),
          Text(shopName,
              style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 20),
          TextFormField(
            controller: amtCtrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount ₹',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              final a = double.tryParse(amtCtrl.text.trim());
              Navigator.pop(ctx, a);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            child: const Text('Save Entry'),
          ),
        ]),
      ),
    );

    if (result == null || result <= 0) return;
    if (!context.mounted) return;

    try {
      final txn = Txn(
        id:         DateTime.now().millisecondsSinceEpoch.toString(),
        businessId: businessId,
        shop:       shop,
        shopName:   shopName,
        date:       DateTime.now(),
        type:       type,
        amount:     result,
        desc:       desc,
      );
      await db.addTxn(txn);
      if (context.mounted) {
        context.read<AppProvider>().addLocalTxn(txn);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$desc saved'),
          backgroundColor: kSecondary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }
}

// ── Upcoming Payments Card (personal mode) ────────────────────────────────────

class _UpcomingPaymentsCard extends StatefulWidget {
  final VoidCallback onTap;
  const _UpcomingPaymentsCard({required this.onTap});
  @override
  State<_UpcomingPaymentsCard> createState() => _UpcomingPaymentsCardState();
}

class _UpcomingPaymentsCardState extends State<_UpcomingPaymentsCard> {
  final _svc = ReminderService();
  List<PaymentReminder> _reminders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _svc.getActive();
    final upcoming = list.where((r) => !r.isPaidThisMonth).take(3).toList();
    if (mounted) setState(() => _reminders = upcoming);
  }

  @override
  Widget build(BuildContext context) {
    if (_reminders.isEmpty) return const SizedBox.shrink();
    final total = _reminders.fold<double>(0, (sum, r) => sum + r.amount);
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('📋', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Text('Upcoming Payments', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            const Spacer(),
            Text('₹${total.toStringAsFixed(0)} total',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF9CA3AF)),
          ]),
          const SizedBox(height: 12),
          ..._reminders.map((r) {
            final days  = r.daysUntilDue;
            final color = days == 0
                ? const Color(0xFFEF4444)
                : days <= 3 ? const Color(0xFFF97316) : const Color(0xFF6B7280);
            final label = days == 0 ? 'Today' : days == 1 ? 'Tomorrow' : '${days}d';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(reminderTypeLabel(r.type).split(' ').first, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(r.name, style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
                Text('₹${r.amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
                ),
              ]),
            );
          }),
        ]),
      ),
    );
  }
}
