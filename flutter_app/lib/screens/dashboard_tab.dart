import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../models/shop.dart';
import '../models/currency.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'shop_detail_screen.dart';

// ── Serif Ledger design tokens (concept #10) ──────────────────────────────────
const _kGold = Color(0xFFA16207); // single accent
const _kSerif = 'serif';          // built-in serif (Noto Serif on Android)

// ── Formatting helpers ────────────────────────────────────────────────────────
final _dayFmt   = DateFormat('yyyy-MM-dd');
String rupee(double v) => Currency.active.format(v.abs());
// Signed rupee: negative renders with a proper minus glyph.
String _signed(double v) => v < 0 ? '−${rupee(v)}' : rupee(v);

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final _db            = DbService();
  int  _period         = 0; // 0=today 1=yesterday 2=week 3=month 4=custom 5=year
  DateTime? _customDate;     // chosen day when _period == 4
  String? _dismissedDate;

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

  /// The single reference day the AI Missing-Entry alert checks against.
  DateTime _refDate() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_period == 4 && _customDate != null) {
      return DateTime(_customDate!.year, _customDate!.month, _customDate!.day);
    }
    if (_period == 1) return today.subtract(const Duration(days: 1));
    return today;
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

    // AI Missing-Entry alert — computed for the selected reference day.
    final refDate    = _refDate();
    final missingItems = _detectMissingPatterns(all, refDate);
    final isRefToday = _period != 4 ||
        (_customDate != null && _dayFmt.format(_customDate!) == _dayFmt.format(DateTime.now()));
    final aiDateLabel = isRefToday
        ? 'today'
        : (_period == 1 ? 'yesterday' : 'on ${_dayFmt.format(refDate)}');

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

          // ── AI Missing Entry Alert (Pro / trial only, conditional) ────────
          _AiAlertSection(
            show: p.canUseAiAlerts &&
                missingItems.isNotEmpty &&
                _dismissedDate != _dayFmt.format(refDate),
            dateLabel:     aiDateLabel,
            targetDate:    refDate,
            missingItems:  missingItems,
            onDismiss: () => setState(
                () => _dismissedDate = _dayFmt.format(refDate)),
            businessId:    p.businessId,
            shops:         p.visibleShops,
            db:            _db,
          ),
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
                ? '📅 ${_dayFmt.format(_customDate!)}'
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

  /// Entries the user usually records that are missing on [refDate].
  List<Map<String, dynamic>> _detectMissingPatterns(List<Txn> all, DateTime refDate) {
    final dayStart = DateTime(refDate.year, refDate.month, refDate.day);
    final dayEnd   = dayStart.add(const Duration(days: 1));
    final since    = dayStart.subtract(const Duration(days: 14));

    final past = all.where((tx) =>
        !tx.date.isBefore(since) && tx.date.isBefore(dayStart)).toList();

    final dayFreq = <String, Set<String>>{};
    final meta    = <String, Map<String, dynamic>>{};
    for (final tx in past) {
      if (tx.desc.isEmpty) continue;
      final key = '${tx.desc}|${tx.type}|${tx.shop}';
      dayFreq.putIfAbsent(key, () => {});
      dayFreq[key]!.add(_dayFmt.format(tx.date));
      meta[key] = {
        'desc':     tx.desc,
        'type':     tx.type,
        'shop':     tx.shop,
        'shopName': tx.shopName,
      };
    }

    final dayDescs = all
        .where((tx) => !tx.date.isBefore(dayStart) && tx.date.isBefore(dayEnd))
        .map((tx) => tx.desc)
        .toSet();

    final missing = <Map<String, dynamic>>[];
    for (final entry in dayFreq.entries) {
      if (entry.value.length >= 3 &&
          !dayDescs.contains(meta[entry.key]!['desc'])) {
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

// ── Section header (used by the AI alert) ─────────────────────────────────────
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
                    color: _kGold,
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

// ── AI Missing Entry Alert Section ───────────────────────────────────────────
class _AiAlertSection extends StatelessWidget {
  final bool                       show;
  final String                     dateLabel;
  final DateTime                   targetDate; // the day a "+ Add" entry lands on
  final List<Map<String, dynamic>> missingItems;
  final VoidCallback               onDismiss;
  final String                     businessId;
  final Map<String, Shop>          shops;
  final DbService                  db;

  const _AiAlertSection({
    required this.show,
    required this.dateLabel,
    required this.targetDate,
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
                            '${missingItems.length} entries you usually add are missing $dateLabel.',
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
                            backgroundColor: _kGold,
                            foregroundColor: Colors.white,
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
            decoration: InputDecoration(
              labelText: 'Amount ${Currency.active.symbol}',
              prefixText: '${Currency.active.symbol} ',
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
        date:       targetDate, // add on the selected day, not today
        type:       type,
        amount:     result,
        desc:       desc,
        createdAt:  DateTime.now(),
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
