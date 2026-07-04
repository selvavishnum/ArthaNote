import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../models/shop.dart';
import 'dashboard_tab.dart' show rupee;
import 'upgrade_screen.dart';

// ── Enums & constants ─────────────────────────────────────────────────────────

enum _Period { week, month, lastMonth, custom }

// Simplified per owner request: credit / salary / staff / payment / alerts /
// insights / actions sections removed to keep Reports focused.
const _kSections = [
  {'id': 'exec',     'label': 'Summary'},
  {'id': 'shopwise', 'label': 'Shop P&L'},
  {'id': 'daily',    'label': 'Daily'},
  {'id': 'weekly',   'label': 'Weekly'},
  {'id': 'monthly',  'label': 'Monthly'},
  {'id': 'expense',  'label': 'Expense'},
  {'id': 'variance', 'label': 'Variance'},
  {'id': 'charts',   'label': 'Charts'},
];

// ── Module-level helpers ──────────────────────────────────────────────────────

double _sumSales(List<Txn> txns) =>
    txns.where((t) => t.type == 'sale').fold(0.0, (s, t) => s + t.amount);

double _sumExp(List<Txn> txns) =>
    txns.where((t) => t.type == 'expense' || t.type == 'payment').fold(0.0, (s, t) => s + t.amount);

double _sumNet(List<Txn> txns) => _sumSales(txns) - _sumExp(txns);

String _pct(double part, double total) =>
    total > 0 ? '${(part / total * 100).toStringAsFixed(1)}%' : '0%';

String _chg(double cur, double prev) {
  if (prev == 0) return '-';
  final p = ((cur - prev) / prev.abs() * 100);
  return '${p >= 0 ? '+' : ''}${p.toStringAsFixed(0)}%';
}

String _fmtDate(DateTime d) => DateFormat('dd MMM').format(d);

String _fmtMonth(String ym) {
  try {
    return DateFormat('MMM yyyy').format(DateTime.parse('$ym-01'));
  } catch (_) {
    return ym;
  }
}

// ── Main widget ───────────────────────────────────────────────────────────────

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  _Period _period = _Period.month;
  DateTimeRange? _customRange;
  String _section = 'exec';

  DateTimeRange _getRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    switch (_period) {
      case _Period.week:
        final weekday = today.weekday; // 1=Mon, 7=Sun
        final startOfWeek = today.subtract(Duration(days: weekday - 1));
        return DateTimeRange(start: startOfWeek, end: tomorrow);
      case _Period.month:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: tomorrow,
        );
      case _Period.lastMonth:
        final firstOfMonth = DateTime(now.year, now.month, 1);
        final firstOfLastMonth = DateTime(now.year, now.month - 1, 1);
        return DateTimeRange(start: firstOfLastMonth, end: firstOfMonth);
      case _Period.custom:
        return _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: tomorrow,
            );
    }
  }

  DateTimeRange _getPrevRange() {
    final r = _getRange();
    final duration = r.end.difference(r.start);
    return DateTimeRange(
      start: r.start.subtract(duration),
      end: r.start,
    );
  }

  List<Txn> _filteredTxns(List<Txn> all, String selectedShop) {
    final r = _getRange();
    return all.where((t) {
      final inRange = !t.date.isBefore(r.start) && t.date.isBefore(r.end);
      final inShop  = selectedShop.isEmpty || t.shop == selectedShop;
      return inRange && inShop;
    }).toList();
  }

  List<Txn> _prevTxns(List<Txn> all, String selectedShop) {
    final r = _getPrevRange();
    return all.where((t) {
      final inRange = !t.date.isBefore(r.start) && t.date.isBefore(r.end);
      final inShop  = selectedShop.isEmpty || t.shop == selectedShop;
      return inRange && inShop;
    }).toList();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: kPrimary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = _Period.custom;
      });
    }
  }

  void _shareWhatsApp(String period, List<Txn> txns) async {
    final r = _getRange();
    final sales = _sumSales(txns);
    final expense = _sumExp(txns);
    final net = _sumNet(txns);

    String dateRange;
    if (period == 'today') {
      dateRange = _fmtDate(DateTime.now());
    } else {
      dateRange = '${_fmtDate(r.start)} – ${_fmtDate(r.end.subtract(const Duration(days: 1)))}';
    }

    final text = '*ArthaNote — $period Summary*\n'
        '📅 $dateRange\n'
        '💚 Total Sales: ${rupee(sales)}\n'
        '💸 Total Expenses: ${rupee(expense)}\n'
        '💰 Net Profit: ${rupee(net)}\n'
        '_Sent from ArthaNote_';

    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open WhatsApp'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  /// Opens a date picker and shares that single day's summary to WhatsApp.
  Future<void> _shareDailyWhatsApp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: kPrimary, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final allTxns = context.read<AppProvider>().txns;
    final dayTxns = allTxns.where((t) {
      final d = t.date;
      return d.year == picked.year &&
          d.month == picked.month &&
          d.day == picked.day;
    }).toList();

    // Per-shop breakdown for sales
    final shopMap = <String, double>{};
    for (final t in dayTxns) {
      if (t.type == 'sale') {
        final n = t.shopName.isNotEmpty ? t.shopName : 'Other';
        shopMap[n] = (shopMap[n] ?? 0) + t.amount;
      }
    }
    final shopLines = shopMap.entries
        .map((e) => '🏪 ${e.key}: ${rupee(e.value)}')
        .join('\n');

    final dateStr = DateFormat('d MMM yyyy').format(picked);
    final text = '*ArthaNote — Daily Report*\n'
        '📅 $dateStr\n'
        '💚 Sales: ${rupee(_sumSales(dayTxns))}\n'
        '💸 Expenses: ${rupee(_sumExp(dayTxns))}\n'
        '💰 Net: ${rupee(_sumNet(dayTxns))}'
        '${shopLines.isNotEmpty ? '\n$shopLines' : ''}\n'
        '📊 ${dayTxns.length} entries\n'
        '_Sent from ArthaNote_';

    final uri =
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open WhatsApp'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final all = p.txns;

    // Pro gate — Reports are unlocked during the trial and for Pro users.
    if (!p.canUseReports) {
      return const ProLockView(
        feature: 'Reports',
        blurb: 'Get 15 sections of MIS reports — sales, profit, GST, '
            'supplier dues and CSV export — with ArthaNote Pro.',
      );
    }

    if (p.syncing && all.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    final txns = _filteredTxns(all, p.selectedShop);
    final prevTxns = _prevTxns(all, p.selectedShop);
    // All txns filtered by shop only (no period) — used by Weekly/Monthly trend sections
    final shopAll = p.selectedShop.isEmpty
        ? all
        : all.where((t) => t.shop == p.selectedShop).toList();

    return Column(
      children: [
        // Period tabs
        Container(
          color: Colors.white,
          child: _buildPeriodTabs(context),
        ),
        // Section nav
        Container(
          color: Colors.white,
          child: _buildSectionNav(),
        ),
        // Section content
        Expanded(
          child: _buildSectionContent(txns, prevTxns, p, shopAll),
        ),
      ],
    );
  }

  Widget _buildPeriodTabs(BuildContext context) {
    final tabs = [
      {'period': _Period.week,      'label': 'This Week'},
      {'period': _Period.month,     'label': 'This Month'},
      {'period': _Period.lastMonth, 'label': 'Last Month'},
      {'period': _Period.custom,    'label': 'Custom'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: tabs.map((tab) {
          final active = _period == tab['period'] as _Period;
          return GestureDetector(
            onTap: () {
              if (tab['period'] == _Period.custom) {
                _pickCustomRange();
              } else {
                setState(() => _period = tab['period'] as _Period);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? kPrimary : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tab['label'] as String,
                style: TextStyle(
                  color: active ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionNav() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _kSections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final sec = _kSections[i];
          final active = _section == sec['id'];
          return GestureDetector(
            onTap: () => setState(() => _section = sec['id']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? kPrimary : const Color(0xFFE5E7EB),
                ),
              ),
              child: Text(
                sec['label']!,
                style: TextStyle(
                  color: active ? Colors.white : kMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionContent(
      List<Txn> txns, List<Txn> prevTxns, AppProvider p, List<Txn> shopAll) {
    switch (_section) {
      case 'exec':
        return _ExecSection(
          txns: txns,
          prevTxns: prevTxns,
          allTxns: shopAll,
          shops: p.shops,
          onShareToday:  () => _shareWhatsApp('Today', txns),
          onShareMonth:  () => _shareWhatsApp('Month', txns),
          onShareDaily:  _shareDailyWhatsApp,
        );
      case 'shopwise':
        return _ShopwiseSection(txns: txns, shops: p.shops);
      case 'daily':
        return _DailySection(txns: txns);
      case 'weekly':
        return _WeeklySection(allTxns: shopAll);
      case 'monthly':
        return _MonthlySection(allTxns: shopAll);
      case 'expense':
        return _ExpenseSection(txns: txns);
      case 'variance':
        return _VarianceSection(txns: txns, prevTxns: prevTxns, shops: p.shops);
      case 'charts':
        return _ChartsSection(txns: txns, allTxns: shopAll);
      default:
        return _ExecSection(
          txns: txns,
          prevTxns: prevTxns,
          allTxns: shopAll,
          shops: p.shops,
          onShareToday: () => _shareWhatsApp('Today', txns),
          onShareMonth: () => _shareWhatsApp('Month', txns),
          onShareDaily: _shareDailyWhatsApp,
        );
    }
  }
}

// ── Section 1: Executive Summary ──────────────────────────────────────────────

class _ExecSection extends StatelessWidget {
  final List<Txn> txns;
  final List<Txn> prevTxns;
  final List<Txn> allTxns;
  final Map<String, Shop> shops;
  final VoidCallback onShareToday;
  final VoidCallback onShareMonth;
  final VoidCallback onShareDaily;

  const _ExecSection({
    required this.txns,
    required this.prevTxns,
    required this.allTxns,
    required this.shops,
    required this.onShareToday,
    required this.onShareMonth,
    required this.onShareDaily,
  });

  @override
  Widget build(BuildContext context) {
    final sales = _sumSales(txns);
    final expense = _sumExp(txns);
    final net = _sumNet(txns);
    final prevSales = _sumSales(prevTxns);
    final prevNet = _sumNet(prevTxns);
    final margin = sales > 0 ? (net / sales * 100) : 0.0;

    // Days active
    final days = txns.map((t) => DateFormat('yyyy-MM-dd').format(t.date)).toSet().length;
    final avgDay = days > 0 ? sales / days : 0.0;

    final totalSales = sales > 0 ? sales : 1.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // Profit/Loss pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: net >= 0
                ? kSecondary.withOpacity(0.1)
                : kRed.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: net >= 0 ? kSecondary : kRed,
            ),
          ),
          child: Row(
            children: [
              Text(
                net >= 0
                    ? '✓ Profitable — ${rupee(net)} net'
                    : '✗ Loss — ${rupee(net.abs())} deficit',
                style: TextStyle(
                  color: net >= 0 ? kSecondary : kRed,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2x2 KPI grid
        _SectionCard(
          title: 'Key Metrics',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiBox(
                      label: 'Total Sales',
                      value: rupee(sales),
                      color: kSecondary,
                      delta: _chg(sales, prevSales),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiBox(
                      label: 'Total Expenses',
                      value: rupee(expense),
                      color: kRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _KpiBox(
                      label: 'Net Profit',
                      value: rupee(net),
                      color: net >= 0 ? kSecondary : kRed,
                      delta: _chg(net, prevNet),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiBox(
                      label: 'Margin %',
                      value: '${margin.toStringAsFixed(1)}%',
                      color: margin >= 0 ? kSecondary : kRed,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3-column activity
        _SectionCard(
          title: 'Activity',
          child: Row(
            children: [
              Expanded(
                child: _KpiBox(label: 'Days Active', value: '$days', color: kText),
              ),
              Expanded(
                child: _KpiBox(label: 'Avg/Day', value: rupee(avgDay), color: kSecondary),
              ),
              Expanded(
                child: _KpiBox(label: '# Entries', value: '${txns.length}', color: kText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Shop-wise mini list
        if (shops.isNotEmpty)
          _SectionCard(
            title: 'Shop Performance',
            child: Column(
              children: shops.entries.map((entry) {
                final shop = entry.value;
                final shopTxns = txns.where((t) => t.shop == shop.id).toList();
                final shopSales = _sumSales(shopTxns);
                final shopNet = _sumNet(shopTxns);
                final pct = shopSales / totalSales;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Text(shop.icon, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              shop.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ]),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(
                              rupee(shopNet),
                              style: TextStyle(
                                color: shopNet >= 0 ? kPrimary : kRed,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${rupee(shopSales)} · ${_pct(shopSales, totalSales)}',
                              style: const TextStyle(
                                color: kMuted,
                                fontSize: 10,
                              ),
                            ),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _ProgressBar(value: pct.clamp(0.0, 1.0), color: kSecondary),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 12),

        // WhatsApp Share
        _SectionCard(
          title: '📱 Share via WhatsApp',
          child: Column(
            children: [
              // Daily (date picker) — prominent
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onShareDaily,
                  icon: const Text('📅', style: TextStyle(fontSize: 14)),
                  label: const Text('Share Daily Report (pick date)',
                      style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Today + Period
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onShareToday,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      foregroundColor: const Color(0xFF25D366),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Today',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onShareMonth,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      foregroundColor: const Color(0xFF25D366),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('This Period',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section 2: Shop P&L ───────────────────────────────────────────────────────

class _ShopwiseSection extends StatefulWidget {
  final List<Txn> txns;
  final Map<String, Shop> shops;

  const _ShopwiseSection({required this.txns, required this.shops});

  @override
  State<_ShopwiseSection> createState() => _ShopwiseSectionState();
}

class _ShopwiseSectionState extends State<_ShopwiseSection> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final totalSales = _sumSales(widget.txns);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: widget.shops.entries.map((entry) {
        final shop = entry.value;
        final shopTxns = widget.txns.where((t) => t.shop == shop.id).toList();
        final shopSales = _sumSales(shopTxns);
        final shopExp = _sumExp(shopTxns);
        final shopNet = shopSales - shopExp;
        final pct = totalSales > 0 ? shopSales / totalSales : 0.0;
        final isExpanded = _expanded.contains(shop.id);

        // Group by date for day-wise breakdown
        final Map<String, List<Txn>> byDay = {};
        for (final t in shopTxns) {
          final k = DateFormat('yyyy-MM-dd').format(t.date);
          byDay.putIfAbsent(k, () => []).add(t);
        }
        final sortedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

        return _SectionCard(
          title: '${shop.icon} ${shop.name}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiBox(label: 'Sales', value: rupee(shopSales), color: kSecondary),
                  ),
                  Expanded(
                    child: _KpiBox(label: 'Expenses', value: rupee(shopExp), color: kRed),
                  ),
                  Expanded(
                    child: _KpiBox(
                      label: 'Net',
                      value: rupee(shopNet),
                      color: shopNet >= 0 ? kSecondary : kRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ProgressBar(value: pct.clamp(0.0, 1.0), color: kSecondary),
              const SizedBox(height: 6),
              Text(
                '${_pct(shopSales, totalSales > 0 ? totalSales : 1)} of total sales',
                style: const TextStyle(color: kMuted, fontSize: 11),
              ),
              if (shopTxns.isNotEmpty) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expanded.remove(shop.id);
                    } else {
                      _expanded.add(shop.id);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? kPrimary.withOpacity(0.06)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: kPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpanded ? 'Hide Day-wise' : '📅 View Day-wise Breakdown',
                          style: const TextStyle(
                            color: kPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 10),
                  _DataRow(const ['Date', 'Sales', 'Expense', 'Net'], isHeader: true),
                  ...sortedDays.map((k) {
                    final dayTxns = byDay[k]!;
                    final dSales = _sumSales(dayTxns);
                    final dExp   = _sumExp(dayTxns);
                    final dNet   = dSales - dExp;
                    return _DataRow([
                      _fmtDate(DateTime.parse(k)),
                      rupee(dSales),
                      rupee(dExp),
                      rupee(dNet),
                    ]);
                  }),
                ],
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Section 3: Daily ──────────────────────────────────────────────────────────

class _DailySection extends StatelessWidget {
  final List<Txn> txns;

  const _DailySection({required this.txns});

  @override
  Widget build(BuildContext context) {
    // Group by date
    final Map<String, List<Txn>> byDay = {};
    for (final t in txns) {
      final key = DateFormat('yyyy-MM-dd').format(t.date);
      byDay.putIfAbsent(key, () => []).add(t);
    }
    final sortedKeys = byDay.keys.toList()..sort();

    if (sortedKeys.isEmpty) {
      return const Center(
        child: Text('No data in this period', style: TextStyle(color: kMuted)),
      );
    }

    // Build day rows
    final rows = sortedKeys.map((k) {
      final dayTxns = byDay[k]!;
      final daySales = _sumSales(dayTxns);
      final dayExp = _sumExp(dayTxns);
      final dayNet = daySales - dayExp;
      return {'key': k, 'sales': daySales, 'exp': dayExp, 'net': dayNet};
    }).toList();

    // Best / lowest by sales
    final bestDay = rows.reduce(
        (a, b) => (a['sales'] as double) >= (b['sales'] as double) ? a : b);
    final lowestDay = rows.reduce(
        (a, b) => (a['sales'] as double) <= (b['sales'] as double) ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // Best / Lowest KPI
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSecondary.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🏆 Best Day',
                        style: TextStyle(
                            color: kSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _fmtDate(DateTime.parse(bestDay['key'] as String)),
                      style: const TextStyle(color: kMuted, fontSize: 11),
                    ),
                    Text(
                      rupee(bestDay['sales'] as double),
                      style: const TextStyle(
                          color: kSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kRed.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📉 Lowest Day',
                        style: TextStyle(
                            color: kRed,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _fmtDate(DateTime.parse(lowestDay['key'] as String)),
                      style: const TextStyle(color: kMuted, fontSize: 11),
                    ),
                    Text(
                      rupee(lowestDay['sales'] as double),
                      style: const TextStyle(
                          color: kRed,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _SectionCard(
          title: 'Daily Breakdown',
          child: Column(
            children: [
              _DataRow(const ['Date', 'Sales', 'Expense', 'Profit', '↑↓'],
                  isHeader: true),
              ...List.generate(rows.length, (i) {
                final row = rows[i];
                final net = row['net'] as double;
                final prevNet = i > 0 ? rows[i - 1]['net'] as double : 0.0;
                final trend = i == 0
                    ? '-'
                    : net >= prevNet
                        ? '▲'
                        : '▼';
                return _DataRow([
                  _fmtDate(DateTime.parse(row['key'] as String)),
                  rupee(row['sales'] as double),
                  rupee(row['exp'] as double),
                  rupee(net),
                  trend,
                ]);
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section 4: Weekly ─────────────────────────────────────────────────────────

class _WeeklySection extends StatelessWidget {
  final List<Txn> allTxns;

  const _WeeklySection({required this.allTxns});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Txn>> byWeek = {};
    for (final t in allTxns) {
      final d = t.date;
      final week =
          '${d.year}-W${((d.difference(DateTime(d.year, 1, 1)).inDays / 7) + 1).floor()}';
      byWeek.putIfAbsent(week, () => []).add(t);
    }
    // Show last 12 weeks (most recent first)
    final sortedKeys = (byWeek.keys.toList()..sort()).reversed.take(12).toList().reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _SectionCard(
          title: 'Weekly Summary',
          child: Column(
            children: [
              _DataRow(const ['Week', 'Sales', 'Avg/Day', 'Expense', 'Net'],
                  isHeader: true),
              ...sortedKeys.map((k) {
                final weekTxns = byWeek[k]!;
                final sales = _sumSales(weekTxns);
                final exp = _sumExp(weekTxns);
                final net = sales - exp;
                final days = weekTxns
                    .map((t) => DateFormat('yyyy-MM-dd').format(t.date))
                    .toSet()
                    .length;
                final avg = days > 0 ? sales / days : 0.0;
                return _DataRow([
                  k,
                  rupee(sales),
                  rupee(avg),
                  rupee(exp),
                  rupee(net),
                ]);
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section 5: Monthly ────────────────────────────────────────────────────────

class _MonthlySection extends StatelessWidget {
  final List<Txn> allTxns;

  const _MonthlySection({required this.allTxns});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Txn>> byMonth = {};
    for (final t in allTxns) {
      final key = DateFormat('yyyy-MM').format(t.date);
      byMonth.putIfAbsent(key, () => []).add(t);
    }
    final sortedKeys = (byMonth.keys.toList()..sort()).reversed.take(6).toList().reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _SectionCard(
          title: 'Monthly Trend (Last 6 Months)',
          child: Column(
            children: [
              _DataRow(
                  const ['Month', 'Sales', 'Expense', 'Net', 'Margin', '↑↓'],
                  isHeader: true),
              ...List.generate(sortedKeys.length, (i) {
                final k = sortedKeys[i];
                final mTxns = byMonth[k]!;
                final sales = _sumSales(mTxns);
                final exp = _sumExp(mTxns);
                final net = sales - exp;
                final margin = sales > 0 ? (net / sales * 100) : 0.0;
                final prevNet = i > 0
                    ? _sumNet(byMonth[sortedKeys[i - 1]]!)
                    : 0.0;
                final trend = i == 0
                    ? '-'
                    : net >= prevNet
                        ? '▲'
                        : '▼';
                return _DataRow([
                  _fmtMonth(k),
                  rupee(sales),
                  rupee(exp),
                  rupee(net),
                  '${margin.toStringAsFixed(1)}%',
                  trend,
                ]);
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section 6: Expense ────────────────────────────────────────────────────────

class _ExpenseSection extends StatelessWidget {
  final List<Txn> txns;

  const _ExpenseSection({required this.txns});

  @override
  Widget build(BuildContext context) {
    final expTxns =
        txns.where((t) => t.type == 'expense' || t.type == 'payment').toList();
    final total = expTxns.fold(0.0, (s, t) => s + t.amount);

    // Group by desc
    final Map<String, double> byCat = {};
    for (final t in expTxns) {
      final cat = t.desc.trim().isEmpty ? 'Uncategorised' : t.desc.trim();
      byCat[cat] = (byCat[cat] ?? 0) + t.amount;
    }
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxAmt = sorted.isEmpty ? 1.0 : sorted.first.value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiBox(
                  label: 'Total Expense', value: rupee(total), color: kRed),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiBox(
                  label: '# Categories',
                  value: '${byCat.length}',
                  color: kText),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Expense Breakdown',
          child: Column(
            children: sorted.map((e) {
              final barPct = maxAmt > 0 ? e.value / maxAmt : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${rupee(e.value)} · ${_pct(e.value, total > 0 ? total : 1)}',
                          style: const TextStyle(
                              color: kMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _ProgressBar(value: barPct.clamp(0.0, 1.0), color: kRed),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Section 11: Variance ──────────────────────────────────────────────────────

class _VarianceSection extends StatelessWidget {
  final List<Txn> txns;
  final List<Txn> prevTxns;
  final Map<String, Shop> shops;

  const _VarianceSection(
      {required this.txns, required this.prevTxns, required this.shops});

  Widget _varRow(String label, double cur, double prev) {
    final chg = prev == 0 ? 0.0 : ((cur - prev) / prev.abs() * 100);
    final improved = cur >= prev;
    final chgStr = prev == 0
        ? '-'
        : '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(1)}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              flex: 3,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(
              flex: 2,
              child: Text(rupee(prev),
                  style: const TextStyle(color: kMuted, fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text(rupee(cur),
                  style: const TextStyle(fontSize: 12))),
          Expanded(
            flex: 2,
            child: Text(
              chgStr,
              style: TextStyle(
                color: improved ? kSecondary : kRed,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final curSales = _sumSales(txns);
    final curExp = _sumExp(txns);
    final curNet = _sumNet(txns);
    final curMargin = curSales > 0 ? (curNet / curSales * 100) : 0.0;

    final prevSales = _sumSales(prevTxns);
    final prevExp = _sumExp(prevTxns);
    final prevNet = _sumNet(prevTxns);
    final prevMargin = prevSales > 0 ? (prevNet / prevSales * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _SectionCard(
          title: 'Period vs Previous Period',
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: const [
                    Expanded(flex: 3, child: Text('')),
                    Expanded(
                        flex: 2,
                        child: Text('Previous',
                            style: TextStyle(
                                color: kMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: 11))),
                    Expanded(
                        flex: 2,
                        child: Text('Current',
                            style: TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 11))),
                    Expanded(
                        flex: 2,
                        child: Text('Change',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 11))),
                  ],
                ),
              ),
              _varRow('Sales', curSales, prevSales),
              _varRow('Expenses', curExp, prevExp),
              _varRow('Net Profit', curNet, prevNet),
              _varRow('Margin %', curMargin, prevMargin),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (shops.isNotEmpty)
          _SectionCard(
            title: 'Shop-wise Variance',
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: const [
                      Expanded(flex: 3, child: Text('Shop', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: kMuted))),
                      Expanded(flex: 2, child: Text('Prev', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: kMuted))),
                      Expanded(flex: 2, child: Text('Cur', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: kMuted))),
                      Expanded(flex: 2, child: Text('Δ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: kMuted))),
                    ],
                  ),
                ),
                ...shops.values.map((shop) {
                  final cur =
                      _sumSales(txns.where((t) => t.shop == shop.id).toList());
                  final prev = _sumSales(
                      prevTxns.where((t) => t.shop == shop.id).toList());
                  return _varRow('${shop.icon} ${shop.name}', cur, prev);
                }),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Section 12: Charts ────────────────────────────────────────────────────────

class _ChartsSection extends StatelessWidget {
  final List<Txn> txns;
  final List<Txn> allTxns;

  const _ChartsSection({required this.txns, required this.allTxns});

  // Donut chart color palette
  static const _palette = [
    Color(0xFF059669), Color(0xFFDC2626), Color(0xFFF59E0B),
    Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEC4899),
    Color(0xFF06B6D4), Color(0xFF84CC16), Color(0xFF6366F1),
    Color(0xFFF97316),
  ];

  Map<String, double> _byCategory(List<Txn> list) {
    final map = <String, double>{};
    for (final t in list) {
      final cat = t.desc.trim().isEmpty ? 'Other' : t.desc.trim();
      map[cat] = (map[cat] ?? 0) + t.amount;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final result = <String, double>{};
    double other = 0;
    for (int i = 0; i < sorted.length; i++) {
      if (i < 8) {
        result[sorted[i].key] = sorted[i].value;
      } else {
        other += sorted[i].value;
      }
    }
    if (other > 0) result['Other'] = other;
    return result;
  }

  Widget _buildDonut(String title, Map<String, double> cats, double total) {
    if (cats.isEmpty) {
      return _SectionCard(
        title: title,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
              child: Text('No data in this period',
                  style: TextStyle(color: kMuted))),
        ),
      );
    }

    final entries = cats.entries.toList();
    final sections = entries.asMap().entries.map((e) {
      return PieChartSectionData(
        value:  e.value.value,
        color:  _palette[e.key % _palette.length],
        title:  '',
        radius: 40,
      );
    }).toList();

    return _SectionCard(
      title: title,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Donut
          SizedBox(
            width: 110,
            height: 110,
            child: PieChart(PieChartData(
              sections:          sections,
              centerSpaceRadius: 28,
              sectionsSpace:     1.5,
              borderData:        FlBorderData(show: false),
            )),
          ),
          const SizedBox(width: 14),
          // Legend
          Expanded(
            child: Column(
              children: entries.asMap().entries.map((e) {
                final color = _palette[e.key % _palette.length];
                final pct   = total > 0 ? e.value.value / total * 100 : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(e.value.key,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${pct.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 11)),
                        Text(rupee(e.value.value),
                            style: const TextStyle(
                                color: kMuted, fontSize: 10)),
                      ],
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _last14Days() {
    final now = DateTime.now();
    return List.generate(14, (i) {
      final day = DateTime(now.year, now.month, now.day - (13 - i));
      final total = allTxns.where((t) {
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return d == day && t.type == 'sale';
      }).fold(0.0, (s, t) => s + t.amount);
      return {
        'label':   i == 13 ? 'T' : DateFormat('dd').format(day),
        'value':   total,
        'isToday': i == 13,
      };
    });
  }

  List<Map<String, dynamic>> _last6Months() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final m   = DateTime(now.year, now.month - (5 - i), 1);
      final key = DateFormat('yyyy-MM').format(m);
      final total = allTxns
          .where((t) =>
              DateFormat('yyyy-MM').format(t.date) == key &&
              t.type == 'sale')
          .fold(0.0, (s, t) => s + t.amount);
      return {
        'label':   DateFormat('MMM').format(m),
        'value':   total,
        'isToday': i == 5,
      };
    });
  }

  Widget _buildBarChart(List<Map<String, dynamic>> data, double height) {
    final maxY = data.fold(
        0.0, (m, d) => (d['value'] as double) > m ? d['value'] as double : m);
    if (data.every((d) => (d['value'] as double) == 0)) {
      return SizedBox(
          height: height,
          child: const Center(
              child: Text('No data', style: TextStyle(color: kMuted))));
    }

    return SizedBox(
      height: height,
      child: BarChart(BarChartData(
        maxY:       maxY > 0 ? maxY * 1.25 : 1000,
        gridData:   FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 8,
            getTooltipColor: (_) => kPrimary,
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              rupee(rod.toY),
              const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= data.length) return const Text('');
                final label   = data[idx]['label'] as String;
                final isToday = data[idx]['isToday'] as bool;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      style: TextStyle(
                        fontSize:   9,
                        color:      isToday ? kPrimary : Colors.grey.shade400,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.normal,
                      )),
                );
              },
            ),
          ),
        ),
        barGroups: data.asMap().entries.map((e) {
          final isToday = e.value['isToday'] as bool;
          return BarChartGroupData(x: e.key, barRods: [
            BarChartRodData(
              toY:          e.value['value'] as double,
              color:        isToday ? kAccent : kSecondary,
              width:        14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
          ]);
        }).toList(),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sales   = _sumSales(txns);
    final expense = _sumExp(txns);
    final net     = _sumNet(txns);

    final salesCats = _byCategory(txns.where((t) => t.type == 'sale').toList());
    final expCats   = _byCategory(
        txns.where((t) => t.type == 'expense' || t.type == 'payment').toList());

    final daily   = _last14Days();
    final monthly = _last6Months();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // ── Trend totals header ────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: kCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 4, height: 18,
                  decoration: BoxDecoration(
                      color: kPrimary, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                const Text('TREND CHARTS',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: kPrimary,
                        letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(children: [
                    Text(rupee(sales),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kSecondary)),
                    const Text('SALES',
                        style: TextStyle(
                            fontSize: 10,
                            color: kMuted,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
                Expanded(
                  child: Column(children: [
                    Text(rupee(expense),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: kRed)),
                    const Text('EXPENSES',
                        style: TextStyle(
                            fontSize: 10,
                            color: kMuted,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
                Expanded(
                  child: Column(children: [
                    Text(rupee(net.abs()),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: net >= 0 ? kPrimary : kRed)),
                    Text(net >= 0 ? 'NET PROFIT' : 'NET LOSS',
                        style: TextStyle(
                            fontSize: 10,
                            color: net >= 0 ? kPrimary : kRed,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ],
          ),
        ),

        // ── Sales by category donut ───────────────────────────────────────
        _buildDonut('💚 SALES BY CATEGORY', salesCats, sales),

        // ── Expense by category donut ─────────────────────────────────────
        _buildDonut('💸 EXPENSE BY CATEGORY', expCats, expense),

        // ── Bar charts ────────────────────────────────────────────────────
        _SectionCard(
          title: 'Daily Sales — Last 14 Days',
          child: Column(children: [
            _buildBarChart(daily, 220),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              _Legend(color: kAccent, label: 'Today'),
              const SizedBox(width: 14),
              _Legend(color: kSecondary, label: 'Past days'),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Monthly Sales — Last 6 Months',
          child: _buildBarChart(monthly, 200),
        ),
      ],
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _KpiBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? delta;

  const _KpiBox({
    required this.label,
    required this.value,
    this.color = kText,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final deltaVal = delta;
    Color deltaColor = kMuted;
    if (deltaVal != null && deltaVal != '-') {
      deltaColor = deltaVal.startsWith('+') ? kSecondary : kRed;
    }

    // Colour psychology: the CARD stays neutral (white + hairline) so the
    // page doesn't become a multi-colour patchwork — only the VALUE carries
    // the semantic colour (green = money in, red = money out/loss,
    // black = neutral counts).
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (deltaVal != null) ...[
            const SizedBox(height: 2),
            Text(
              deltaVal,
              style: TextStyle(
                color: deltaColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final List<String> cells;
  final bool isHeader;
  final bool isTotal;

  const _DataRow(this.cells, {this.isHeader = false, this.isTotal = false});

  @override
  Widget build(BuildContext context) {
    final style = isHeader
        ? const TextStyle(color: kMuted, fontWeight: FontWeight.w700, fontSize: 11)
        : isTotal
            ? const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 12)
            : const TextStyle(color: kText, fontSize: 12);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFF3F4F6),
            width: isHeader ? 1.5 : 0.5,
          ),
        ),
      ),
      child: Row(
        children: cells.map((c) {
          return Expanded(
            child: Text(
              c,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.grey.shade100,
        color: color,
        minHeight: 7,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
      ],
    );
  }
}
