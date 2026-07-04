import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../models/shop.dart';
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
  final _search = TextEditingController();
  String  _typeFilter  = 'all';
  _Period _period      = _Period.month;
  DateTimeRange? _customRange;
  DateTime? _monthStart;              // null = current month
  final Set<String> _collapsed = {};  // day keys that are folded
  bool _missingExpanded = false;      // AI missing-entry suggestion expand state
  // Memoized AI missing-entry scan — the ledger rebuilds on every search
  // keystroke/filter tap, and the detector is O(n) over ALL txns. Only
  // recompute when the data (or the day) actually changes.
  String _missingDigest = '';
  List<Map<String, dynamic>> _missingCache = const [];
  List<String> _duplicateWarnings = [];
  Set<String>  _duplicateIds      = {};
  bool   _dupBannerDismissed = false;
  // Cheap digest: length + first/last ID. Avoids re-running O(n²) scan when
  // the txn list hasn't meaningfully changed (e.g. only a rebuild triggered).
  String _lastDupDigest = '';

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

  // ── Detect duplicate entries (same day + same desc + exact same amount) ─────
  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  // Single O(n) pass: duplicate = SAME NAME + SAME AMOUNT + SAME DATE +
  // SAME TYPE + SAME SHOP (final owner spec). A sale and an expense with
  // the same name/amount are money-in vs money-out — never a duplicate.
  // The same entry in two different shops is also legitimate — not a
  // duplicate. Only a true accidental double entry (same shop, same type,
  // same day, same name, same amount) gets flagged. Name matching is
  // case/space-insensitive ("Tea" == "tea "). Matched rows get the
  // gold-yellow ledger highlight.
  static ({List<String> warnings, Set<String> ids}) _findDuplicates(
      List<Txn> all, String currencySymbol) {
    final groups = <String, List<Txn>>{};
    for (final t in all) {
      final name = t.desc.trim().toLowerCase();
      if (name.isEmpty) continue;
      final key = '${_dayKey(t.date)}|${t.shop}|${t.type}|${t.amount}|$name';
      (groups[key] ??= []).add(t);
    }
    final warnings = <String>[];
    final ids      = <String>{};
    for (final g in groups.values) {
      if (g.length < 2) continue;
      for (final t in g) {
        ids.add(t.id);
      }
      if (warnings.length < 3) {
        final a = g.first;
        warnings.add(
            '⚠️ Duplicate on ${_dayKey(a.date)}: "${a.desc}" $currencySymbol${a.amount.toStringAsFixed(0)}');
      }
    }
    return (warnings: warnings, ids: ids);
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

  // ── AI missing-entry: entries usually recorded that are absent TODAY ────────
  List<Map<String, dynamic>> _detectMissingToday(List<Txn> all) {
    final now      = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
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
      dayFreq[key]!.add(_dayKey(tx.date));
      meta[key] = {
        'desc': tx.desc, 'type': tx.type, 'shop': tx.shop, 'shopName': tx.shopName,
      };
    }
    final todayDescs = all
        .where((tx) => !tx.date.isBefore(dayStart) && tx.date.isBefore(dayEnd))
        .map((tx) => tx.desc)
        .toSet();

    final missing = <Map<String, dynamic>>[];
    for (final e in dayFreq.entries) {
      if (e.value.length >= 3 && !todayDescs.contains(meta[e.key]!['desc'])) {
        missing.add({...meta[e.key]!, 'days': e.value.length});
      }
    }
    missing.sort((a, b) => (b['days'] as int).compareTo(a['days'] as int));
    return missing.take(8).toList();
  }

  // Single-line suggestion at the very top of the ledger — tap to expand.
  Widget _missingBanner(List<Map<String, dynamic>> missing) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _missingExpanded = !_missingExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
            child: Row(children: [
              const Text('🧠', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${missing.length} entries you usually add are missing today',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kPrimary),
                ),
              ),
              AnimatedRotation(
                turns: _missingExpanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right,
                    size: 18, color: Colors.grey.shade400),
              ),
            ]),
          ),
        ),
        if (_missingExpanded)
          ...missing.map((m) => Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 10, 10),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['desc'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(
                          '${(m['shopName'] as String).isNotEmpty ? "${m['shopName']} · " : ""}${m['type']}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _quickAddMissing(m),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(56, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('+ Add'),
                  ),
                ]),
              )),
      ]),
    );
  }

  Future<void> _quickAddMissing(Map<String, dynamic> m) async {
    final p        = context.read<AppProvider>();
    final desc     = m['desc'] as String;
    final type     = m['type'] as String;
    final shop     = m['shop'] as String;
    final shopName = m['shopName'] as String;
    final amtCtrl  = TextEditingController();

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text('Quick Add: $desc',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
          const SizedBox(height: 4),
          Text(shopName, style: const TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 20),
          TextFormField(
            controller: amtCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount ${p.currency.symbol}',
              prefixText: '${p.currency.symbol} ',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(amtCtrl.text.trim())),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            child: const Text('Save Entry'),
          ),
        ]),
      ),
    );

    if (result == null || result <= 0) return;
    if (!mounted) return;
    final now = DateTime.now();
    final txn = Txn(
      id:         now.millisecondsSinceEpoch.toString(),
      businessId: p.businessId,
      shop:       shop,
      shopName:   shopName,
      date:       DateTime(now.year, now.month, now.day, now.hour, now.minute),
      type:       type,
      amount:     result,
      desc:       desc,
      createdAt:  now,
    );
    try {
      await DbService().addTxn(txn);
      if (mounted) {
        context.read<AppProvider>().addLocalTxn(txn);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$desc saved'),
          backgroundColor: kSecondary,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    final all  = p.txns;
    // Cheap digest: only re-run the O(n²) scan when list size or boundary IDs change.
    final digest = '${all.length}/${all.isEmpty ? "" : all.first.id}/${all.length > 1 ? all.last.id : ""}';
    if (digest != _lastDupDigest) {
      _lastDupDigest = digest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final result = _findDuplicates(all, p.currency.symbol);
        if (result.warnings.toString() != _duplicateWarnings.toString() ||
            result.ids.length != _duplicateIds.length) {
          setState(() {
            _duplicateWarnings  = result.warnings;
            _duplicateIds       = result.ids;
            _dupBannerDismissed = false;
          });
        }
      });
    }
    final txns = _applyFilters(all, p.selectedShop);

    final totalSales   = txns.where((x) => x.type == 'sale')
        .fold(0.0, (s, x) => s + x.amount);
    final totalExpense = txns.where((x) => x.type == 'expense')
        .fold(0.0, (s, x) => s + x.amount);
    final totalPayment = txns.where((x) => x.type == 'payment')
        .fold(0.0, (s, x) => s + x.amount);

    // Group by date
    final groups = <DateTime, List<Txn>>{};
    for (final tx in txns) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      groups.putIfAbsent(day, () => []).add(tx);
    }
    final days = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // newest first

    // Everything above the entries — duplicate alert, search bar, period &
    // type filters, and the Cash Book summary — is built as a list of leading
    // widgets so the WHOLE header scrolls away with the entries, giving the
    // ledger maximum room (nothing stays pinned).
    final Widget? dupBanner = (p.canUseDuplicateAlert &&
            _duplicateWarnings.isNotEmpty &&
            !_dupBannerDismissed)
        ? Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFEF9C3), Color(0xFFFDE68A)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
            ),
            child: Row(children: [
              const Text('🟡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Possible duplicate entries',
                      style: TextStyle(
                          color: Color(0xFF92600A),
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  ..._duplicateWarnings.map((w) => Text(w,
                      style: const TextStyle(
                          color: Color(0xFF92600A), fontSize: 11))),
                ],
              )),
              GestureDetector(
                onTap: () => setState(() => _dupBannerDismissed = true),
                child:
                    const Icon(Icons.close, size: 16, color: Color(0xFF92600A)),
              ),
            ]),
          )
        : null;

    final Widget searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextFormField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: t('search_hint', l),
          prefixIcon: const Icon(Icons.search_outlined, color: kPrimary),
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
    );

    // AI missing-entry suggestion (Pro/trial) — single line above the search
    // bar. Memoized: recompute only when the txn list or the day changes.
    List<Map<String, dynamic>> missingToday = const [];
    if (p.canUseAiAlerts) {
      final mDigest =
          '${all.length}/${all.isEmpty ? "" : all.first.id}/${all.length > 1 ? all.last.id : ""}/${_dayKey(DateTime.now())}';
      if (mDigest != _missingDigest) {
        _missingDigest = mDigest;
        _missingCache  = _detectMissingToday(all);
      }
      missingToday = _missingCache;
    }

    final leading = <Widget>[
      if (missingToday.isNotEmpty) _missingBanner(missingToday),
      if (dupBanner != null) dupBanner,
      searchField,
      _buildPeriodRow(l),
      _buildTypeRow(),
      if (txns.isNotEmpty)
        _buildHeader(txns, txns.length, totalSales, totalExpense,
            totalPayment, l),
    ];

    if (p.syncing && all.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          ...leading,
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(color: kPrimary)),
          ),
        ],
      );
    }
    if (txns.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [...leading, _buildEmpty(l)],
      );
    }
    return _buildList(days, groups, l, p.shops, _duplicateIds, leading: leading);
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(
      List<Txn> txns, int count, double sales, double expense, double payment, String l) {
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
                      if (payment > 0)
                        TextSpan(
                          text: '  ⇄${rupee(payment)}',
                          style: const TextStyle(
                              color: kAmber, fontWeight: FontWeight.w700),
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
      ('📅 Custom',              _Period.custom,   () => _pickCustomRange()),
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
    final isPersonal = context.read<AppProvider>().isPersonal;
    final options = isPersonal
        ? [
            {'key': 'all',     'label': 'All'},
            {'key': 'sale',    'label': 'Received'},
            {'key': 'expense', 'label': 'Paid'},
          ]
        : _typeOptions;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        children: options.map((f) {
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
      List<DateTime> days, Map<DateTime, List<Txn>> groups, String l,
      Map<String, Shop> shops, Set<String> duplicateIds,
      {required List<Widget> leading}) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      // The leading widgets (search, filters, Cash Book summary) scroll away
      // with the entries — nothing stays pinned, so the ledger gets full room.
      itemCount: days.length + leading.length,
      itemBuilder: (_, idx) {
        if (idx < leading.length) return leading[idx];
        final i     = idx - leading.length;
        final day   = days[i];
        final key   = DateFormat('yyyy-MM-dd').format(day);
        final items = groups[day]!;
        final isCollapsed = _collapsed.contains(key);

        final daySales   = items.where((x) => x.type == 'sale')
            .fold(0.0, (s, x) => s + x.amount);
        final dayExpense = items.where((x) => x.type == 'expense')
            .fold(0.0, (s, x) => s + x.amount);
        final dayPayment = items.where((x) => x.type == 'payment')
            .fold(0.0, (s, x) => s + x.amount);
        final dayNet = daySales - dayExpense - dayPayment;

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
                        if (dayPayment > 0) ...[
                          const SizedBox(width: 6),
                          Text('⇄${rupee(dayPayment)}',
                              style: TextStyle(
                                  color: kAmber.withOpacity(0.9),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ],
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
            if (!isCollapsed)
              ...items.map((txn) => _LedgerTile(
                txn: txn,
                shops: shops,
                isDuplicate: duplicateIds.contains(txn.id),
              )),
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
  final Txn  txn;
  final Map<String, Shop> shops;
  final bool isDuplicate;
  const _LedgerTile({required this.txn, required this.shops, this.isDuplicate = false});

  void _openEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTxnSheet(txn: txn, shops: shops),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSale       = txn.type == 'sale';
    final isExpense    = txn.type == 'expense';
    final color        = isExpense ? kRed : isSale ? kSecondary : kAmber;
    final p            = context.read<AppProvider>();
    final isPersonal   = p.isPersonal;
    final ownerEmail   = (p.profile['email'] as String?) ?? '';
    final isStaffEntry = txn.enteredBy.isNotEmpty && txn.enteredBy != ownerEmail;

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
      onDismissed: (_) {
        DbService().deleteTxn(txn.id, txn.businessId);
        context.read<AppProvider>().removeLocalTxn(txn.id);
      },
      child: GestureDetector(
        onTap: () => _openEdit(context),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: isDuplicate ? const Color(0xFFFFFBEB) : Colors.white,
            border: Border(
              left: isDuplicate
                  ? const BorderSide(color: Color(0xFFFCD34D), width: 3)
                  : BorderSide.none,
              bottom: const BorderSide(color: Color(0xFFF3F4F6), width: 1),
            ),
          ),
          child: Row(children: [
            // ── Arrow icon ────────────────────────────────────────────────
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

            // ── Name + subtitle ───────────────────────────────────────────
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
                    if (isPersonal)
                      isSale ? 'Received' : isExpense ? 'Paid' : 'Payment'
                    else
                      _capitalise(txn.type),
                    if (txn.contact.isNotEmpty) txn.contact,
                  ].join(' · '),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Tiny date + time stamp on every entry. Uses the real entry
                // time when available; legacy entries (no time) show date only.
                Text(
                  (txn.createdAt != null ||
                          txn.date.hour != 0 ||
                          txn.date.minute != 0)
                      ? DateFormat('d MMM yyyy · h:mm a')
                          .format(txn.createdAt ?? txn.date)
                      : DateFormat('d MMM yyyy').format(txn.date),
                  style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500),
                ),
              ]),
            ),

            // ── Staff badge ────────────────────────────────────────────────
            if (isStaffEntry)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '👤',
                  style: const TextStyle(fontSize: 10),
                ),
              ),

            // ── Amount ────────────────────────────────────────────────────
            Text(
              '${isExpense ? "-" : "+"}${rupee(txn.amount)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 4),

            // ── Edit button ───────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 17),
              color: Colors.grey.shade400,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _openEdit(context),
            ),
          ]),
        ),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Edit transaction bottom sheet ─────────────────────────────────────────────
class _EditTxnSheet extends StatefulWidget {
  final Txn txn;
  final Map<String, Shop> shops;
  const _EditTxnSheet({required this.txn, required this.shops});

  @override
  State<_EditTxnSheet> createState() => _EditTxnSheetState();
}

class _EditTxnSheetState extends State<_EditTxnSheet> {
  final _db     = DbService();
  final _amtCtl = TextEditingController();
  final _descCtl = TextEditingController();
  bool  _saving  = false;

  late String   _type;
  late String   _shopId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _type   = widget.txn.type;
    _shopId = widget.txn.shop;
    _date   = widget.txn.date;
    _amtCtl.text  = widget.txn.amount > 0
        ? widget.txn.amount.toStringAsFixed(
            widget.txn.amount == widget.txn.amount.roundToDouble() ? 0 : 2)
        : '';
    _descCtl.text = widget.txn.desc;
  }

  @override
  void dispose() {
    _amtCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amtCtl.text.trim()) ?? 0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid amount'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final shop = widget.shops[_shopId];
      final updated = widget.txn.copyWith(
        type:     _type,
        amount:   amt,
        desc:     _descCtl.text.trim(),
        shop:     _shopId,
        shopName: shop?.name ?? widget.txn.shopName,
        date:     _date,
      );
      await _db.updateTxn(updated);
      if (mounted) {
        context.read<AppProvider>().updateLocalTxn(updated);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = DateTime(
          picked.year, picked.month, picked.day,
          _date.hour, _date.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final currencySymbol = context.watch<AppProvider>().currency.symbol;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // handle
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        const Text(
          'Edit Entry',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kText),
        ),
        const SizedBox(height: 18),

        // ── Type selector ──────────────────────────────────────────────────
        Builder(builder: (context) {
          final isPersonal = context.read<AppProvider>().isPersonal;
          final opts = isPersonal
              ? [('sale', '💰 Received', kSecondary), ('expense', '💸 Paid', kRed)]
              : [
                  ('sale', '↑ Sale', kSecondary),
                  ('expense', '↓ Expense', kRed),
                  ('payment', '⇄ Payment', kAmber),
                ];
          return Row(children: [
          for (final opt in opts)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _type = opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _type == opt.$1
                        ? opt.$3.withOpacity(0.12)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _type == opt.$1 ? opt.$3 : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    opt.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _type == opt.$1 ? opt.$3 : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ),
          ]); // Row
        }),   // Builder
        const SizedBox(height: 14),

        // ── Amount ─────────────────────────────────────────────────────────
        TextFormField(
          controller: _amtCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            prefixText: '$currencySymbol ',
            prefixStyle: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary),
            labelText: 'Amount',
            filled: true,
            fillColor: const Color(0xFFF0FDF4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          autofocus: false,
        ),
        const SizedBox(height: 12),

        // ── Description ────────────────────────────────────────────────────
        TextFormField(
          controller: _descCtl,
          decoration: InputDecoration(
            labelText: 'Description',
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Shop + Date row ────────────────────────────────────────────────
        Row(children: [
          // shop selector
          if (widget.shops.length > 1)
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _shopId,
                decoration: InputDecoration(
                  labelText: 'Shop',
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: widget.shops.entries.map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    '${e.value.icon} ${e.value.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                )).toList(),
                onChanged: (v) => setState(() => _shopId = v!),
              ),
            ),

          if (widget.shops.length > 1) const SizedBox(width: 10),

          // date picker
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 15, color: kPrimary),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('d MMM yyyy').format(_date),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                  ),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Save button ────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Save Changes',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
          ),
        ),
      ]),
    );
  }
}
