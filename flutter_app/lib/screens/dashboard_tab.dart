import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'entry_screen.dart';

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
      t('today', l),
      t('yesterday', l),
      t('this_week', l),
      t('this_month', l),
    ];

    return StreamBuilder<List<Txn>>(
      stream: _db.txnStream(p.businessId),
      builder: (ctx, snap) {
        final all   = snap.data ?? [];
        final txns  = _filter(all, p);
        final sales   = txns.where((x) => x.type == 'sale')
            .fold(0.0, (s, x) => s + x.amount);
        final expense = txns.where((x) => x.type == 'expense')
            .fold(0.0, (s, x) => s + x.amount);
        final net = sales - expense;

        return RefreshIndicator(
          color: kPrimary,
          backgroundColor: Colors.white,
          onRefresh: () async => setState(() {}),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Column(children: [
                // ── Shop filter chips ─────────────────────────────────────
                if (p.shops.isNotEmpty)
                  _ShopChips(p: p, l: l),

                // ── Period selector ───────────────────────────────────────
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    itemCount: periods.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => setState(() => _period = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: _period == i ? kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _period == i ? kPrimary : const Color(0xFFE5E7EB)),
                        ),
                        child: Center(
                          child: Text(
                            periods[i],
                            style: TextStyle(
                              color: _period == i ? Colors.white : Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Summary cards ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _SummaryCard(
                      label: t('total_sales', l),
                      amount: sales,
                      color: kSecondary,
                      icon: Icons.trending_up_rounded,
                    ),
                    const SizedBox(width: 10),
                    _SummaryCard(
                      label: t('total_expense', l),
                      amount: expense,
                      color: kRed,
                      icon: Icons.trending_down_rounded,
                    ),
                  ]),
                ),
                const SizedBox(height: 10),

                // ── Net profit card ───────────────────────────────────────
                _NetCard(label: t('net_profit', l), net: net),
                const SizedBox(height: 14),

                // ── Recent entries header ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t('recent_entries', l),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: kPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: kPrimary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${txns.length} ${t("entries", l)}',
                          style: const TextStyle(
                              color: kPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ]),
            ),

            // ── Transaction list ──────────────────────────────────────────
            snap.connectionState == ConnectionState.waiting
                ? const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: kPrimary),
                    ),
                  )
                : txns.isEmpty
                    ? SliverFillRemaining(
                        child: _EmptyState(l: l),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _TxnTile(txn: txns[i]),
                          childCount: txns.length,
                        ),
                      ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ]),
        );
      },
    );
  }
}

// ── Shop chips ────────────────────────────────────────────────────────────────
class _ShopChips extends StatelessWidget {
  final AppProvider p;
  final String l;
  const _ShopChips({required this.p, required this.l});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      children: [
        _chip(context, t('all_shops', l), p.selectedShop.isEmpty,
            () => p.setSelectedShop('')),
        ...p.shops.values.map((s) => _chip(
              context,
              '${s.icon} ${s.name}',
              p.selectedShop == s.id,
              () => p.setSelectedShop(s.id),
            )),
      ],
    ),
  );

  Widget _chip(BuildContext ctx, String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? kPrimary : const Color(0xFFE5E7EB)),
            boxShadow: active ? kBoxShadow : kCardShadow,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.grey.shade700,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
}

// ── Summary card ──────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color  color;
  final IconData icon;
  const _SummaryCard({
    required this.label,
    required this.amount,
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
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          rupee(amount),
          style: TextStyle(
            color: color,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]),
    ),
  );
}

// ── Net card ──────────────────────────────────────────────────────────────────
class _NetCard extends StatelessWidget {
  final String label;
  final double net;
  const _NetCard({required this.label, required this.net});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          net >= 0 ? kPrimary : kRed,
          net >= 0 ? kSecondary : const Color(0xFFEF4444),
        ],
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
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        Icon(
          net >= 0 ? Icons.emoji_events_outlined : Icons.warning_amber_outlined,
          color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
      ]),
      Text(
        rupee(net),
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
      ),
    ]),
  );
}

// ── Transaction tile ──────────────────────────────────────────────────────────
class _TxnTile extends StatelessWidget {
  final Txn txn;
  const _TxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isIncome = txn.type == 'sale' || txn.type == 'payment';
    final color    = txn.type == 'expense' ? kRed : kSecondary;
    final icon     = txn.type == 'sale' ? '📈' : txn.type == 'expense' ? '📉' : '💳';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 19))),
        ),
        title: Text(
          txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          DateFormat('dd MMM, hh:mm a').format(txn.date),
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        trailing: Text(
          '${isIncome ? "+" : "−"}${rupee(txn.amount)}',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String l;
  const _EmptyState({required this.l});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Text('📋', style: TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          t('no_entries', l),
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 17, color: kPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          t('add_first', l),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EntryScreen())),
          icon: const Icon(Icons.add, size: 18),
          label: Text(t('add_entry', l)),
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(180, 48)),
        ),
      ]),
    ),
  );
}
