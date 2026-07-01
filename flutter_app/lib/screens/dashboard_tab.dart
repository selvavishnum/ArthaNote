import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../models/currency.dart';
import '../providers/app_provider.dart';
import 'shop_detail_screen.dart';

// ── Serif Ledger design tokens (concept #10) ──────────────────────────────────
const _kGold = Color(0xFFA16207); // single accent
const _kSerif = 'serif';          // built-in serif (Noto Serif on Android)

// ── Formatting helpers ────────────────────────────────────────────────────────
String rupee(double v) => Currency.active.format(v.abs());
// Signed rupee: negative renders with a proper minus glyph.
String _signed(double v) => v < 0 ? '−${rupee(v)}' : rupee(v);

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  int  _period         = 0; // 0=today 1=yesterday 2=week 3=month 4=custom 5=year
  DateTime? _customDate;     // chosen day when _period == 4

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
      case 5:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 4:
        final d = _customDate ?? today;
        final start = DateTime(d.year, d.month, d.day);
        return DateTimeRange(
            start: start, end: start.add(const Duration(days: 1)));
      default:
        return DateTimeRange(start: today, end: now);
    }
  }

  String _periodLabel() {
    switch (_period) {
      case 1: return 'YESTERDAY';
      case 2: return 'THIS WEEK';
      case 3: return 'THIS MONTH';
      case 5: return 'THIS YEAR';
      case 4: return 'CUSTOM';
      default: return 'TODAY';
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _kGold),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customDate = picked;
        _period = 4;
      });
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
    final p   = context.watch<AppProvider>();
    final l   = p.lang;
    final all = p.txns;
    final txns = _filter(all, p);

    // Net Balance hero totals (across all visible shops in the period).
    final totSales = txns.where((x) => x.type == 'sale').fold(0.0, (s, x) => s + x.amount);
    final totExp   = txns.where((x) => x.type == 'expense').fold(0.0, (s, x) => s + x.amount);
    final totPay   = txns.where((x) => x.type == 'payment').fold(0.0, (s, x) => s + x.amount);
    final totNet   = totSales - totExp - totPay;

    // (AI Missing-Entry alert moved OFF the dashboard → now a single-line
    // suggestion at the top of the Ledger page.)

    return RefreshIndicator(
      color: _kGold,
      backgroundColor: Colors.white,
      onRefresh: () async {
        await context.read<AppProvider>().syncNow();
        if (mounted) setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
        children: [
          // ── Date filter (underline tabs) ─────────────────────────────────
          _periodTabs(),
          const SizedBox(height: 16),

          // ── Net Balance hero ─────────────────────────────────────────────
          _NetHero(
            net: totNet,
            sales: totSales,
            expense: totExp,
            periodLabel: _periodLabel(),
            isPersonal: p.isPersonal,
          ),
          Container(
            height: 2,
            color: kText,
            margin: const EdgeInsets.fromLTRB(2, 6, 2, 18),
          ),

          // ── Shops ────────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 2, 2),
            child: Text('SHOPS',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                    color: kMuted)),
          ),

          if (p.syncing && p.visibleShops.isEmpty)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: _kGold)))
          else if (p.visibleShops.isEmpty)
            _EmptyCard(text: 'No shops set up yet')
          else
            ...p.visibleShops.values.map((shop) {
              final st = txns.where((x) => x.shop == shop.id);
              final ss = st.where((x) => x.type == 'sale').fold(0.0, (s, x) => s + x.amount);
              final se = st.where((x) => x.type == 'expense').fold(0.0, (s, x) => s + x.amount);
              final sp = st.where((x) => x.type == 'payment').fold(0.0, (s, x) => s + x.amount);
              return _LxShopRow(
                name: shop.name,
                sales: ss,
                expense: se,
                net: ss - se - sp,
                l: l,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ShopDetailScreen(shop: shop)),
                ),
              );
            }),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _periodTabs() {
    final tabs = <(String, int)>[
      ('Today', 0), ('Week', 2), ('Month', 3), ('Year', 5),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final tb in tabs)
            _tabItem(tb.$1, tb.$2, () => setState(() => _period = tb.$2)),
          _tabItem(
            _period == 4 && _customDate != null
                ? '📅 ${_customDate!.day}/${_customDate!.month}/${_customDate!.year}'
                : '📅 Custom',
            4,
            _pickCustomDate,
          ),
        ],
      ),
    );
  }

  Widget _tabItem(String label, int pv, VoidCallback onTap) {
    final on = _period == pv;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 22),
        padding: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: on ? _kGold : Colors.transparent, width: 2)),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? _kGold : kMuted)),
        ),
      ),
    );
  }

}

// ── Net Balance hero ──────────────────────────────────────────────────────────
class _NetHero extends StatelessWidget {
  final double net;
  final double sales;
  final double expense;
  final String periodLabel;
  final bool   isPersonal;
  const _NetHero({
    required this.net,
    required this.sales,
    required this.expense,
    required this.periodLabel,
    required this.isPersonal,
  });

  Widget _sub(String label, double val) => RichText(
        text: TextSpan(
          style: const TextStyle(color: kMuted, fontSize: 13),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
                text: rupee(val),
                style: const TextStyle(
                    color: kText, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${isPersonal ? "BALANCE" : "NET BALANCE"} · $periodLabel',
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                    color: kMuted)),
            const SizedBox(height: 2),
            Text(_signed(net),
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    letterSpacing: -1.2,
                    height: 1.04)),
            const SizedBox(height: 9),
            Row(children: [
              _sub('Sales', sales),
              const SizedBox(width: 22),
              _sub('Expense', expense),
            ]),
          ],
        ),
      );
}

// ── Serif shop row ────────────────────────────────────────────────────────────
class _LxShopRow extends StatelessWidget {
  final String name;
  final double sales;
  final double expense;
  final double net;
  final String l;
  final VoidCallback onTap;
  const _LxShopRow({
    required this.name,
    required this.sales,
    required this.expense,
    required this.net,
    required this.l,
    required this.onTap,
  });

  Widget _num(String label, String value, Color valColor) => RichText(
        text: TextSpan(
          style: const TextStyle(color: kMuted, fontSize: 13),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
                text: value,
                style: TextStyle(
                    color: valColor, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontFamily: _kSerif,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: kText,
                      height: 1.1,
                      letterSpacing: -0.3)),
              const SizedBox(height: 7),
              Wrap(spacing: 20, runSpacing: 4, children: [
                _num(t('sales', l), rupee(sales), kText),
                _num('Exp', rupee(expense), kText),
                _num(t('net', l), _signed(net), _kGold),
              ]),
            ],
          ),
        ),
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
