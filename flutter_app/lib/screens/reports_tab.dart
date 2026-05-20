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
  @override State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _db = DbService();
  int _months = 1;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    return StreamBuilder<List<Txn>>(
      stream: _db.txnStream(p.businessId),
      builder: (ctx, snap) {
        final all  = snap.data ?? [];
        final now  = DateTime.now();
        final from = DateTime(now.year, now.month - _months + 1, 1);
        final txns = all.where((t) => !t.date.isBefore(from)).toList();

        final sales   = txns.where((t) => t.type == 'sale').fold(0.0,    (s, t) => s + t.amount);
        final expense = txns.where((t) => t.type == 'expense').fold(0.0, (s, t) => s + t.amount);
        final net     = sales - expense;

        // Daily chart data (last 14 days)
        final chartData = _buildChartData(all);

        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 80), children: [
          // Period selector
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [1, 3, 6].map((m) {
            final active = _months == m;
            return GestureDetector(
              onTap: () => setState(() => _months = m),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? kPrimary : Colors.grey.shade300),
                ),
                child: Text(m == 1 ? '1 Month' : '$m Months',
                  style: TextStyle(color: active ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w700)),
              ),
            );
          }).toList()),
          const SizedBox(height: 20),

          // Summary cards
          _statRow([
            _stat(t('total_sales', l), rupee(sales), kSecondary, '📈'),
            _stat(t('total_expense', l), rupee(expense), kRed, '📉'),
          ]),
          const SizedBox(height: 10),
          _bigStat(t('net_profit', l), rupee(net), net >= 0 ? kSecondary : kRed),
          const SizedBox(height: 24),

          // Bar chart
          const Text('Daily Sales (Last 14 days)', style: TextStyle(fontWeight: FontWeight.w700, color: kPrimary, fontSize: 15)),
          const SizedBox(height: 12),
          Container(
            height: 180,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
            child: chartData.isEmpty
                ? const Center(child: Text('No data', style: TextStyle(color: Colors.grey)))
                : BarChart(BarChartData(
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= chartData.length) return const Text('');
                          return Text(chartData[idx]['label'] as String,
                            style: const TextStyle(fontSize: 9, color: Colors.grey));
                        },
                      )),
                    ),
                    barGroups: chartData.asMap().entries.map((e) => BarChartGroupData(
                      x: e.key,
                      barRods: [BarChartRodData(toY: e.value['value'] as double, color: kSecondary, width: 10, borderRadius: BorderRadius.circular(4))],
                    )).toList(),
                  )),
          ),
          const SizedBox(height: 24),

          // Shop breakdown
          if (p.shops.length > 1) ...[
            const Text('Shop Breakdown', style: TextStyle(fontWeight: FontWeight.w700, color: kPrimary, fontSize: 15)),
            const SizedBox(height: 12),
            ...p.shops.values.map((shop) {
              final shopSales = txns.where((t) => t.shop == shop.id && t.type == 'sale').fold(0.0, (s, t) => s + t.amount);
              final pct = sales > 0 ? shopSales / sales : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${shop.icon} ${shop.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(rupee(shopSales), style: const TextStyle(color: kSecondary, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.shade100, color: kSecondary, minHeight: 6)),
                ]),
              );
            }),
          ],
        ]);
      },
    );
  }

  List<Map<String, dynamic>> _buildChartData(List<Txn> all) {
    final now    = DateTime.now();
    final result = <Map<String, dynamic>>[];
    for (int i = 13; i >= 0; i--) {
      final day   = DateTime(now.year, now.month, now.day - i);
      final total = all.where((t) {
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return d == day && t.type == 'sale';
      }).fold(0.0, (s, t) => s + t.amount);
      result.add({'label': i == 0 ? 'T' : DateFormat('dd').format(day), 'value': total});
    }
    return result;
  }

  Widget _statRow(List<Widget> children) => Row(
    children: children.map((w) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 5), child: w))).toList(),
  );

  Widget _stat(String label, String value, Color color, String icon) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$icon  $label', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _bigStat(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [color.withOpacity(0.9), color]),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
    ]),
  );
}
