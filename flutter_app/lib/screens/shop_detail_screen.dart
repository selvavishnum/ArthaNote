import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../models/txn.dart';
import '../models/shop.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

class ShopDetailScreen extends StatefulWidget {
  final Shop shop;
  const ShopDetailScreen({super.key, required this.shop});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  final _db = DbService();
  int _period = 0; // 0=today 1=yesterday 2=week 3=month 4=all

  DateTimeRange? _range() {
    if (_period == 4) return null; // all
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
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1), end: now);
      default:
        return DateTimeRange(start: today, end: now);
    }
  }

  List<Txn> _filter(List<Txn> all) {
    final r = _range();
    if (r == null) return all;
    return all.where((txn) =>
        !txn.date.isBefore(r.start) && !txn.date.isAfter(r.end)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final shop = widget.shop;

    final periods = ['Today', 'Yesterday', 'This Week', 'This Month', 'All'];

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('${shop.icon} ${shop.name}'),
        backgroundColor: Colors.white,
        foregroundColor: kText,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0x18000000),
        titleTextStyle: const TextStyle(
          color: kText,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFF3F4F6)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<Txn>>(
        stream: _db.txnStream(p.businessId, shop: shop.id),
        builder: (ctx, snap) {
          final all  = snap.data ?? [];
          final txns = _filter(all);

          final sales   = txns.where((x) => x.type == 'sale')
              .fold(0.0, (s, x) => s + x.amount);
          final expense = txns.where((x) => x.type == 'expense')
              .fold(0.0, (s, x) => s + x.amount);
          final payment = txns.where((x) => x.type == 'payment')
              .fold(0.0, (s, x) => s + x.amount);
          final net     = sales - expense;

          // category breakdown
          final catMap = <String, double>{};
          for (final tx in txns) {
            if (tx.desc.isNotEmpty) {
              catMap[tx.desc] = (catMap[tx.desc] ?? 0) + tx.amount;
            }
          }
          final topCats = catMap.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 360° badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: const Text(
                      '360° ANALYSIS REPORT',
                      style: TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),

                  // Period chips
                  SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      itemCount: periods.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => setState(() => _period = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(right: 8),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
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

                  const SizedBox(height: 10),

                  // 4 stat boxes
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                          child: _StatBox(
                              label: 'SALES',
                              value: rupee(sales),
                              color: kSecondary)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _StatBox(
                              label: 'EXPENSES',
                              value: rupee(expense),
                              color: kRed)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                          child: _StatBox(
                              label: 'NET',
                              value: rupee(net),
                              color: net >= 0 ? kSecondary : kRed)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _StatBox(
                              label: 'ENTRIES',
                              value: '${txns.length}',
                              color: kPrimary)),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // Breakdown bars
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: kCardShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BREAKDOWN',
                              style: TextStyle(
                                color: kPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              )),
                          const SizedBox(height: 14),
                          _BreakdownRow(
                              icon: '💚',
                              label: 'Sales',
                              value: sales,
                              max: sales + expense + payment,
                              color: kSecondary),
                          const SizedBox(height: 10),
                          _BreakdownRow(
                              icon: '🔴',
                              label: 'Expenses',
                              value: expense,
                              max: sales + expense + payment,
                              color: kRed),
                          const SizedBox(height: 10),
                          _BreakdownRow(
                              icon: '🟡',
                              label: 'Payments',
                              value: payment,
                              max: sales + expense + payment,
                              color: kAmber),
                        ],
                      ),
                    ),
                  ),

                  // Top categories
                  if (topCats.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: kCardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('BY CATEGORY',
                                style: TextStyle(
                                  color: kPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                )),
                            const SizedBox(height: 12),
                            ...topCats.take(8).map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.key,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        rupee(e.value),
                                        style: const TextStyle(
                                          color: kPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: kCardShadow,
                        ),
                        child: const Column(children: [
                          Text('BY CATEGORY',
                              style: TextStyle(
                                color: kPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              )),
                          SizedBox(height: 12),
                          Text('No expense data',
                              style: TextStyle(color: kMuted, fontSize: 13)),
                        ]),
                      ),
                    ),

                  // Transaction list header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'TRANSACTIONS (${txns.length})',
                      style: const TextStyle(
                        color: kPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Transaction list
            if (snap.connectionState == ConnectionState.waiting)
              const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(color: kPrimary)),
              )
            else if (txns.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text('📭', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 12),
                    Text('No entries for this period',
                        style: TextStyle(color: kMuted, fontSize: 14)),
                  ]),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final txn   = txns[i];
                    final color = txn.type == 'expense'
                        ? kRed
                        : txn.type == 'payment'
                            ? kAmber
                            : kSecondary;
                    final icon  = txn.type == 'sale'
                        ? '📈'
                        : txn.type == 'expense'
                            ? '📉'
                            : '💳';
                    return Dismissible(
                      key: Key(txn.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 3),
                        decoration: BoxDecoration(
                          color: kRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline,
                            color: kRed, size: 22),
                      ),
                      confirmDismiss: (_) => showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete entry?'),
                          content: Text(
                              'Delete "${txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc}"?'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: kRed),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                      onDismissed: (_) => _db.deleteTxn(txn.id, txn.businessId),
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 3),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(icon,
                                  style:
                                      const TextStyle(fontSize: 18)),
                            ),
                          ),
                          title: Text(
                            txn.desc.isEmpty
                                ? txn.type.toUpperCase()
                                : txn.desc,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat('dd MMM · hh:mm a')
                                .format(txn.date),
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11),
                          ),
                          trailing: Text(
                            '${txn.type == "expense" ? "−" : "+"}${rupee(txn.amount)}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: txns.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ]);
        },
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              )),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _BreakdownRow extends StatelessWidget {
  final String icon;
  final String label;
  final double value;
  final double max;
  final Color  color;
  const _BreakdownRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.max,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final double pct = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
          Text(rupee(value),
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade100,
            color: color,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
