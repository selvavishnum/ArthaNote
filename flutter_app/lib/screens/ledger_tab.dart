import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

// ── Period enum ───────────────────────────────────────────────────────────────
enum _Period { today, yesterday, week, month, custom, all }

class LedgerTab extends StatefulWidget {
  const LedgerTab({super.key});
  @override
  State<LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<LedgerTab> {
  final _db     = DbService();
  final _search = TextEditingController();
  String  _typeFilter  = 'all';
  _Period _period      = _Period.all;
  DateTimeRange? _customRange;
  DateTime? _monthStart;              // null = current month
  final Set<String> _collapsed = {};  // day keys that are folded

  static const _typeOptions = [
    {'key': 'all',     'label': 'All'},
    {'key': 'sale',    'label': 'Sales'},
    {'key': 'expense', 'label': 'Expenses'},
    {'key': 'payment', 'label': 'Payments'},
  ];

  // ── Date range for active period ──────────────────────────────────────────
  DateTimeRange _range() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eod   = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_period) {
      case _Period.today:
        return DateTimeRange(start: today, end: eod);
      case _Period.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return DateTimeRange(
            start: y,
            end: DateTime(y.year, y.month, y.day, 23, 59, 59));
      case _Period.week:
        return DateTimeRange(
            start: today.subtract(const Duration(days: 6)), end: eod);
      case _Period.month:
        final ms = _monthStart ?? DateTime(now.year, now.month, 1);
        // day-0 trick: month+1, day 0 = last day of current month
        final me = DateTime(ms.year, ms.month + 1, 0, 23, 59, 59);
        return DateTimeRange(start: ms, end: me);
      case _Period.custom:
        return _customRange ??
            DateTimeRange(
                start: today.subtract(const Duration(days: 6)), end: eod);
      case _Period.all:
        return DateTimeRange(start: DateTime(2020), end: eod);
    }
  }

  // ── Month picker dialog ───────────────────────────────────────────────────
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    int pickerYear = (_monthStart ?? now).year;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setDlg(() => pickerYear--),
            ),
            Expanded(
              child: Text('$pickerYear',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: pickerYear >= now.year
                  ? null
                  : () => setDlg(() => pickerYear++),
            ),
          ]),
          content: SizedBox(
            width: 280,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: List.generate(12, (i) {
                final m = i + 1;
                final isFuture = pickerYear == now.year && m > now.month;
                final isSelected = _monthStart != null &&
                    _monthStart!.year == pickerYear &&
                    _monthStart!.month == m;
                return GestureDetector(
                  onTap: isFuture
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          setState(() {
                            _monthStart = DateTime(pickerYear, m, 1);
                            _period = _Period.month;
                          });
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? kPrimary
                          : isFuture
                              ? Colors.grey.shade100
                              : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      DateFormat('MMM').format(DateTime(pickerYear, m)),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : isFuture
                                ? Colors.grey.shade400
                                : kPrimary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _monthStart = null;
                  _period = _Period.month;
                });
              },
              child: const Text('This Month'),
            ),
          ],
        );
      }),
    );
  }

  // ── Custom date range picker ──────────────────────────────────────────────
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = DateTimeRange(
          start: picked.start,
          end: DateTime(
              picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
        );
        _period = _Period.custom;
      });
    }
  }

  // ── CSV export ────────────────────────────────────────────────────────────
  Future<void> _exportCsv(List<Txn> txns) async {
    try {
      final buf = StringBuffer('Date,Shop,Type,Description,Amount\n');
      for (final tx in txns) {
        final d = DateFormat('yyyy-MM-dd HH:mm').format(tx.date);
        final desc = tx.desc.replaceAll('"', '""');
        buf.writeln('$d,"${tx.shopName}","${tx.type}","$desc",${tx.amount}');
      }
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/arthanote_ledger.csv');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: 'arthanote_ledger.csv')],
        subject: 'ArthaNote Ledger Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Apply all filters ─────────────────────────────────────────────────────
  List<Txn> _applyFilters(List<Txn> all, String selectedShop) {
    final r = _range();
    var txns = all.where((tx) {
      final inRange = !tx.date.isBefore(r.start) && !tx.date.isAfter(r.end);
      final inShop  = selectedShop.isEmpty || tx.shop == selectedShop;
      final inType  = _typeFilter == 'all' || tx.type == _typeFilter;
      return inRange && inShop && inType;
    }).toList();

    final q = _search.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      txns = txns.where((tx) =>
          tx.desc.toLowerCase().contains(q) ||
          tx.shopName.toLowerCase().contains(q) ||
          tx.type.contains(q)).toList();
    }
    return txns;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    return StreamBuilder<List<Txn>>(
      stream: _db.txnStream(p.businessId),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, color: kRed, size: 40),
                const SizedBox(height: 12),
                const Text('Sync error — check connection',
                    style: TextStyle(
                        color: kRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const SizedBox(height: 6),
                Text(snap.error.toString(),
                    style: const TextStyle(color: kMuted, fontSize: 11),
                    textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        final all  = snap.data ?? [];
        final txns = _applyFilters(all, p.selectedShop);

        final totalSales   = txns.where((x) => x.type == 'sale')
            .fold(0.0, (s, x) => s + x.amount);
        final totalExpense = txns.where((x) => x.type == 'expense')
            .fold(0.0, (s, x) => s + x.amount);

        // Group by date
        final groups = <DateTime, List<Txn>>{};
        for (final tx in txns) {
          final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
          groups.putIfAbsent(day, () => []).add(tx);
        }
        final days = groups.keys.toList()
          ..sort((a, b) => b.compareTo(a)); // newest first

        return Column(children: [
          _buildHeader(txns, txns.length, totalSales, totalExpense, l),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextFormField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: t('search_hint', l),
                prefixIcon:
                    const Icon(Icons.search_outlined, color: kPrimary),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        })
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          _buildPeriodRow(l),
          _buildTypeRow(),
          Expanded(
            child: snap.connectionState == ConnectionState.waiting
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary))
                : txns.isEmpty
                    ? _buildEmpty(l)
                    : _buildList(days, groups, l),
          ),
        ]);
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(
      List<Txn> txns, int count, double sales, double expense, String l) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('📒', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    t('cash_book', l),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kText,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12),
                    children: [
                      TextSpan(
                        text: '$count ${t("entries", l)}  ',
                        style: const TextStyle(color: kMuted),
                      ),
                      TextSpan(
                        text: '+${rupee(sales)}',
                        style: const TextStyle(
                            color: kSecondary, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '  -${rupee(expense)}',
                        style: const TextStyle(
                            color: kRed, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // CSV button
          GestureDetector(
            onTap: () => _exportCsv(txns),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.download_outlined, size: 15, color: kPrimary),
                SizedBox(width: 4),
                Text(
                  'CSV',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Period chips row ──────────────────────────────────────────────────────
  Widget _buildPeriodRow(String l) {
    String monthLabel = 'Month ▾';
    if (_period == _Period.month) {
      final ms = _monthStart ?? DateTime.now();
      monthLabel = '${DateFormat("MMM yyyy").format(ms)} ▾';
    }

    final chips = <(String, _Period, VoidCallback)>[
      ('📅 ${t("today", l)}',    _Period.today,    () => setState(() => _period = _Period.today)),
      ('◀ ${t("yesterday", l)}', _Period.yesterday,() => setState(() => _period = _Period.yesterday)),
      ('📅 ${t("this_week", l)}',_Period.week,     () => setState(() => _period = _Period.week)),
      (monthLabel,                _Period.month,    _pickMonth),
      ('📅 Custom',              _Period.custom,   _pickCustomRange),
      ('📋 ${t("all", l)}',      _Period.all,      () => setState(() => _period = _Period.all)),
    ];

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        children: chips.map((chip) {
          final label  = chip.$1;
          final period = chip.$2;
          final onTap  = chip.$3;
          final active = _period == period;

          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? kPrimary : const Color(0xFFE5E7EB),
                ),
              ),
              child: Center(
                child: Text(
                  _period == _Period.custom && period == _Period.custom &&
                          _customRange != null
                      ? '${DateFormat("d MMM").format(_customRange!.start)} – ${DateFormat("d MMM").format(_customRange!.end)}'
                      : label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Type filter row ───────────────────────────────────────────────────────
  Widget _buildTypeRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        children: _typeOptions.map((f) {
          final active = _typeFilter == f['key'];
          return GestureDetector(
            onTap: () => setState(() => _typeFilter = f['key']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? kText : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? kText : const Color(0xFFE5E7EB),
                ),
              ),
              child: Center(
                child: Text(
                  f['label']!,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmpty(String l) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('📬', style: TextStyle(fontSize: 36)),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'No transactions',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: kText,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Tap Entry tab to add your first entry',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    ]),
  );

  // ── Expandable grouped list ───────────────────────────────────────────────
  Widget _buildList(
      List<DateTime> days, Map<DateTime, List<Txn>> groups, String l) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day   = days[i];
        final key   = DateFormat('yyyy-MM-dd').format(day);
        final items = groups[day]!;
        final isCollapsed = _collapsed.contains(key);

        final daySales   = items.where((x) => x.type == 'sale')
            .fold(0.0, (s, x) => s + x.amount);
        final dayExpense = items.where((x) => x.type == 'expense')
            .fold(0.0, (s, x) => s + x.amount);
        final dayNet = daySales - dayExpense;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tappable day header ──────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() {
                if (isCollapsed) {
                  _collapsed.remove(key);
                } else {
                  _collapsed.add(key);
                }
              }),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: dayNet >= 0 ? kSecondary : kRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEE, d MMM, yyyy').format(day),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: kText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${items.length} ${t("entries", l)}',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(
                        '${dayNet >= 0 ? "+" : "-"}${rupee(dayNet.abs())}',
                        style: TextStyle(
                          color: dayNet >= 0 ? kSecondary : kRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('↑${rupee(daySales)}',
                            style: TextStyle(
                                color: kSecondary.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Text('↓${rupee(dayExpense)}',
                            style: TextStyle(
                                color: kRed.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                    const SizedBox(width: 8),
                    // expand/collapse chevron
                    AnimatedRotation(
                      turns: isCollapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Entries (hidden when collapsed) ──────────────────────────
            if (!isCollapsed) ...items.map((txn) => _LedgerTile(txn: txn)),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

// ── Ledger tile ───────────────────────────────────────────────────────────────
class _LedgerTile extends StatelessWidget {
  final Txn txn;
  const _LedgerTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isSale    = txn.type == 'sale';
    final isExpense = txn.type == 'expense';
    final color     = isExpense ? kRed : isSale ? kSecondary : kAmber;

    return Dismissible(
      key: Key(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        decoration: BoxDecoration(
          color: kRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Icon(Icons.delete_outline, color: kRed, size: 22),
          SizedBox(height: 2),
          Text('Delete',
              style: TextStyle(
                  color: kRed, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete entry?'),
          content: Text(
              'Delete "${txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: kRed),
                child: const Text('Delete')),
          ],
        ),
      ),
      onDismissed: (_) => DbService().deleteTxn(txn.id, txn.businessId),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
          ),
        ),
        child: Row(children: [
          // ── Arrow icon ──────────────────────────────────────────────────
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                isExpense
                    ? Icons.arrow_downward_rounded
                    : isSale
                        ? Icons.arrow_upward_rounded
                        : Icons.swap_horiz_rounded,
                color: color,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // ── Name + subtitle ─────────────────────────────────────────────
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: kText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (txn.shopName.isNotEmpty) txn.shopName,
                  _capitalise(txn.type),
                  DateFormat('hh:mm a').format(txn.date),
                ].join(' · '),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),

          // ── Amount ──────────────────────────────────────────────────────
          Text(
            '${isExpense ? "-" : "+"}${rupee(txn.amount)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ]),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
