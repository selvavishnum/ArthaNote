import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../models/shop.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';

// ── Formatting helpers ────────────────────────────────────────────────────────
final _inrFmt = NumberFormat('#,##,##0', 'en_IN');
String rupee(double v) => '₹${_inrFmt.format(v.abs())}';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _db = DbService();
  int _period = 0; // 0=today 1=yesterday 2=week 3=month

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
      '📅 ${t("today", l)}',
      '◀◀ ${t("yesterday", l)}',
      '📅 ${t("this_week", l)}',
      '📅 ${t("this_month", l)}',
    ];

    return StreamBuilder<List<Txn>>(
      stream: _db.txnStream(p.businessId),
      builder: (ctx, snap) {
        final all    = snap.data ?? [];
        final txns   = _filter(all, p);
        final sales  = txns.where((x) => x.type == 'sale')
            .fold(0.0, (s, x) => s + x.amount);
        final expense = txns.where((x) => x.type == 'expense')
            .fold(0.0, (s, x) => s + x.amount);
        final net = sales - expense;

        // Most sold: find the most common desc in sales
        final saleTxns = txns.where((x) => x.type == 'sale').toList();
        String mostSold = '';
        if (saleTxns.isNotEmpty) {
          final freq = <String, int>{};
          for (final tx in saleTxns) {
            if (tx.desc.isNotEmpty) {
              freq[tx.desc] = (freq[tx.desc] ?? 0) + 1;
            }
          }
          if (freq.isNotEmpty) {
            mostSold = freq.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
          }
        }

        return RefreshIndicator(
          color: kPrimary,
          backgroundColor: Colors.white,
          onRefresh: () async => setState(() {}),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Entry count + Refresh row ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${all.length} entries · synced',
                          style: const TextStyle(
                            color: kMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {}),
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
                              Text(
                                'Refresh',
                                style: TextStyle(
                                    color: kPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Period selector ───────────────────────────────────────
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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

                  // ── No-entries yellow banner ──────────────────────────────
                  if (txns.isEmpty && snap.connectionState != ConnectionState.waiting)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
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
                    ),

                  // ── 4-box stats grid ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      // Sales box
                      Expanded(
                        child: _StatBox(
                          label: 'SALES',
                          value: rupee(sales),
                          valueColor: kSecondary,
                          icon: '💰',
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Expenses box
                      Expanded(
                        child: _StatBox(
                          label: 'EXPENSES',
                          value: rupee(expense),
                          valueColor: kRed,
                          icon: '📉',
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      // Net Profit box
                      Expanded(
                        child: _StatBox(
                          label: t('net_profit', l).toUpperCase(),
                          value: net >= 0 ? '+ ${rupee(net)}' : '− ${rupee(net)}',
                          valueColor: net >= 0 ? kSecondary : kRed,
                          icon: net >= 0 ? '📈' : '📊',
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Most Sold box
                      Expanded(
                        child: _StatBox(
                          label: t('most_sold', l).toUpperCase(),
                          value: mostSold.isEmpty ? 'NONE' : mostSold,
                          valueColor: mostSold.isEmpty
                              ? kAmber
                              : kText,
                          icon: '⭐',
                          valueSmall: mostSold.isNotEmpty,
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // ── Shop summary section header ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t('shop_summary', l).toUpperCase(),
                          style: const TextStyle(
                            color: kPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: kMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  ),

                  // ── Per-shop summary cards ────────────────────────────────
                  if (p.shops.isNotEmpty)
                    ...p.shops.values.map((shop) {
                      final shopTxns = txns.where((x) => x.shop == shop.id).toList();
                      final shopSales = shopTxns
                          .where((x) => x.type == 'sale')
                          .fold(0.0, (s, x) => s + x.amount);
                      final shopExp = shopTxns
                          .where((x) => x.type == 'expense')
                          .fold(0.0, (s, x) => s + x.amount);
                      final shopNet = shopSales - shopExp;
                      return _ShopSummaryCard(
                        shop: shop,
                        entryCount: shopTxns.length,
                        sales: shopSales,
                        expense: shopExp,
                        net: shopNet,
                        l: l,
                      );
                    }),

                  const SizedBox(height: 100),
                ],
              ),
            ),

            // ── Loading indicator ─────────────────────────────────────────
            if (snap.connectionState == ConnectionState.waiting)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: kPrimary),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// ── Stat box (2x2 grid cell) ──────────────────────────────────────────────────
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
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
      ],
    ),
  );
}

// ── Shop summary card ─────────────────────────────────────────────────────────
class _ShopSummaryCard extends StatelessWidget {
  final Shop   shop;
  final int    entryCount;
  final double sales;
  final double expense;
  final double net;
  final String l;

  const _ShopSummaryCard({
    required this.shop,
    required this.entryCount,
    required this.sales,
    required this.expense,
    required this.net,
    required this.l,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: kCardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text(shop.icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                shop.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: kText,
                ),
              ),
            ]),
            Row(children: [
              Text(
                '$entryCount ${t("entries", l)}',
                style: const TextStyle(
                  color: kMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios, color: kMuted, size: 11),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        Row(children: [
          _MiniStat(
            label: t('sales', l),
            value: rupee(sales),
            color: kSecondary,
          ),
          const SizedBox(width: 16),
          _MiniStat(
            label: t('expense', l),
            value: rupee(expense),
            color: kRed,
          ),
          const SizedBox(width: 16),
          _MiniStat(
            label: t('net', l),
            value: rupee(net),
            color: net >= 0 ? kSecondary : kRed,
          ),
        ]),
      ],
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
