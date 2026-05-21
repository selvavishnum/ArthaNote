import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _db    = DbService();
  int   _months = 1;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    return StreamBuilder<List<Txn>>(
      stream: _db.txnStream(p.businessId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kPrimary));
        }

        final all  = snap.data ?? [];
        final now  = DateTime.now();
        final from = DateTime(now.year, now.month - (_months - 1), 1);
        final txns = all.where((tx) => !tx.date.isBefore(from)).toList();

        final sales   = txns.where((tx) => tx.type == 'sale')
            .fold(0.0, (s, tx) => s + tx.amount);
        final expense = txns.where((tx) => tx.type == 'expense')
            .fold(0.0, (s, tx) => s + tx.amount);
        final net = sales - expense;

        final chartData = _buildChartData(all);
        final maxY      = chartData.fold(
            0.0, (m, d) => d['value'] > m ? d['value'] as double : m);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ── Period selector ───────────────────────────────────────────
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [1, 3, 6].map((m) {
                  final active = _months == m;
                  return GestureDetector(
                    onTap: () => setState(() => _months = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? kPrimary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active ? [
                          BoxShadow(
                            color: kPrimary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ] : null,
                      ),
                      child: Text(
                        m == 1 ? '1 Month' : '$m Months',
                        style: TextStyle(
                          color: active ? Colors.white : Colors.grey.shade600,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList()),
              ),
            ),
            const SizedBox(height: 20),

            // ── Summary stat pair ─────────────────────────────────────────
            Row(children: [
              _StatCard(
                label: t('total_sales', l),
                value: rupee(sales),
                color: kSecondary,
                icon: '📈',
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: t('total_expense', l),
                value: rupee(expense),
                color: kRed,
                icon: '📉',
              ),
            ]),
            const SizedBox(height: 10),

            // ── Net profit gradient card ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: net >= 0
                      ? [kPrimary, kSecondary]
                      : [kRed, const Color(0xFFEF4444)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (net >= 0 ? kPrimary : kRed).withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('net_profit', l),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      net >= 0 ? 'Profitable period 🎉' : 'Loss period',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 11),
                    ),
                  ]),
                  Text(
                    rupee(net),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bar chart ─────────────────────────────────────────────────
            _SectionHeader(label: t('last_14_days', l)),
            const SizedBox(height: 10),
            Container(
              height: 190,
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: kCardShadow,
              ),
              child: chartData.isEmpty
                  ? const Center(
                      child: Text('No data',
                          style: TextStyle(color: kMuted)))
                  : BarChart(
                      BarChartData(
                        maxY: maxY > 0 ? maxY * 1.2 : 1000,
                        gridData: FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            tooltipRoundedRadius: 8,
                            getTooltipColor: (_) => kPrimary,
                            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                              rupee(rod.toY),
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= chartData.length) {
                                  return const Text('');
                                }
                                final label = chartData[idx]['label'] as String;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: label == 'T'
                                          ? kPrimary
                                          : Colors.grey.shade400,
                                      fontWeight: label == 'T'
                                          ? FontWeight.w800
                                          : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: chartData.asMap().entries.map((e) {
                          final isToday = chartData[e.key]['label'] == 'T';
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value['value'] as double,
                                color: isToday ? kAccent : kSecondary,
                                width: 12,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5)),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: const [
              _Legend(color: kAccent, label: 'Today'),
              SizedBox(width: 14),
              _Legend(color: kSecondary, label: 'Past days'),
            ]),
            const SizedBox(height: 24),

            // ── Shop breakdown ────────────────────────────────────────────
            if (p.shops.length > 1) ...[
              _SectionHeader(label: t('shop_breakdown', l)),
              const SizedBox(height: 10),
              ...p.shops.values.map((shop) {
                final shopSales = txns
                    .where((tx) => tx.shop == shop.id && tx.type == 'sale')
                    .fold(0.0, (s, tx) => s + tx.amount);
                final pct = sales > 0 ? (shopSales / sales).clamp(0.0, 1.0) : 0.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: kCardShadow,
                  ),
                  child: Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [
                          Text(shop.icon, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Text(shop.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ]),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(rupee(shopSales),
                              style: const TextStyle(
                                  color: kSecondary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          Text(
                            '${(pct * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11),
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.grey.shade100,
                        color: kSecondary,
                        minHeight: 7,
                      ),
                    ),
                  ]),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _buildChartData(List<Txn> all) {
    final now    = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (int i = 13; i >= 0; i--) {
      final day   = DateTime(now.year, now.month, now.day - i);
      final total = all.where((tx) {
        final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
        return d == day && tx.type == 'sale';
      }).fold(0.0, (s, tx) => s + tx.amount);
      result.add({
        'label': i == 0 ? 'T' : DateFormat('dd').format(day),
        'value': total,
      });
    }
    return result;
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  final String icon;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$icon  $label',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 4, height: 18,
        decoration: BoxDecoration(
          color: kPrimary, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label,
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: kPrimary, fontSize: 15)),
  ]);
}

class _Legend extends StatelessWidget {
  final Color  color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
  ]);
}
