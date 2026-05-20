import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'entry_screen.dart';

final _fmt = NumberFormat('#,##,##0', 'en_IN');
String rupee(double v) => '₹${_fmt.format(v.abs())}';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _db = DbService();
  int _period = 0; // 0=today 1=yesterday 2=week 3=month

  DateTimeRange _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 1: final y = today.subtract(const Duration(days: 1)); return DateTimeRange(start: y, end: today);
      case 2: return DateTimeRange(start: today.subtract(const Duration(days: 7)), end: now);
      case 3: return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      default: return DateTimeRange(start: today, end: now);
    }
  }

  List<Txn> _filter(List<Txn> all, AppProvider p) {
    final r = _range();
    return all.where((t) {
      final inRange = !t.date.isBefore(r.start) && !t.date.isAfter(r.end);
      final inShop  = p.selectedShop.isEmpty || t.shop == p.selectedShop;
      return inRange && inShop;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p  = context.watch<AppProvider>();
    final l  = p.lang;
    final periods = [t('today', l), t('yesterday', l), t('this_week', l), t('this_month', l)];

    return StreamBuilder<List<Txn>>(
      stream: _db.txnStream(p.businessId, shop: p.selectedShop.isEmpty ? null : p.selectedShop),
      builder: (ctx, snap) {
        final all = snap.data ?? [];
        final txns = _filter(all, p);
        final sales   = txns.where((t) => t.type == 'sale').fold(0.0,   (s, t) => s + t.amount);
        final expense = txns.where((t) => t.type == 'expense').fold(0.0, (s, t) => s + t.amount);
        final net = sales - expense;

        return RefreshIndicator(
          color: kPrimary,
          onRefresh: () async => setState(() {}),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Column(children: [
              // Shop filter chips
              if (p.shops.isNotEmpty)
                _shopChips(p, l),
              // Period tabs
              _periodRow(periods),
              // Summary cards
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  _summaryCard(t('total_sales', l), sales, kSecondary, Icons.trending_up),
                  const SizedBox(width: 10),
                  _summaryCard(t('total_expense', l), expense, kRed, Icons.trending_down),
                ]),
              ),
              _netCard(t('net_profit', l), net),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Recent Entries', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kPrimary)),
                  Text('${txns.length} entries', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ]),
              ),
            ])),
            txns.isEmpty
                ? SliverFillRemaining(child: _emptyState(l))
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _txnTile(txns[i]),
                      childCount: txns.length,
                    ),
                  ),
          ]),
        );
      },
    );
  }

  Widget _shopChips(AppProvider p, String l) => SizedBox(
    height: 48,
    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _chip(t('all_shops', l), p.selectedShop.isEmpty, () => p.setSelectedShop('')),
        ...p.shops.values.map((s) => _chip(
          '${s.icon} ${s.name}', p.selectedShop == s.id, () => p.setSelectedShop(s.id))),
      ],
    ),
  );

  Widget _chip(String label, bool active, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: active ? kPrimary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? kPrimary : Colors.grey.shade200),
      ),
      child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
    ),
  );

  Widget _periodRow(List<String> periods) => SizedBox(
    height: 44,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: periods.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => setState(() => _period = i),
        child: Container(
          margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _period == i ? kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _period == i ? kPrimary : Colors.grey.shade200),
          ),
          child: Center(child: Text(periods[i],
            style: TextStyle(color: _period == i ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 13))),
        ),
      ),
    ),
  );

  Widget _summaryCard(String label, double amount, Color color, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6),
          Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]),
        const SizedBox(height: 6),
        Text(rupee(amount), style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  Widget _netCard(String label, double net) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [kPrimary.withOpacity(0.9), kSecondary.withOpacity(0.8)]),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
      Text(rupee(net), style: TextStyle(color: net >= 0 ? Colors.white : const Color(0xFFFFCDD2), fontSize: 20, fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _txnTile(Txn txn) {
    final isIncome = txn.type == 'sale' || txn.type == 'payment';
    final color = isIncome ? kSecondary : kRed;
    final icon  = txn.type == 'sale' ? '📈' : txn.type == 'expense' ? '📉' : '💳';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
        ),
        title: Text(txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis),
        subtitle: Text(DateFormat('dd MMM, hh:mm a').format(txn.date), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        trailing: Text(
          '${isIncome ? '+' : '-'}${rupee(txn.amount)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }

  Widget _emptyState(String l) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text('📋', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 12),
    Text(t('no_entries', l), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kPrimary)),
    const SizedBox(height: 6),
    Text(t('add_first', l), style: TextStyle(color: Colors.grey.shade500)),
    const SizedBox(height: 20),
    ElevatedButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EntryScreen())),
      child: Text(t('add_entry', l)),
      style: ElevatedButton.styleFrom(minimumSize: const Size(160, 46)),
    ),
  ]));
}
