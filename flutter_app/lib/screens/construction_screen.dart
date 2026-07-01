import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../providers/app_provider.dart';
import '../models/construction_project.dart';
import '../models/construction_entry.dart';
import '../services/construction_service.dart';
import 'dashboard_tab.dart' show rupee;
import 'upgrade_screen.dart';

const _kProjectTypes = [
  {'k': 'residential', 'l': 'Residential'},
  {'k': 'commercial', 'l': 'Commercial'},
  {'k': 'industrial', 'l': 'Industrial'},
  {'k': 'other', 'l': 'Other'},
];
const _kStatuses = [
  {'k': 'planning', 'l': 'Planning'},
  {'k': 'ongoing', 'l': 'Ongoing'},
  {'k': 'onhold', 'l': 'On Hold'},
  {'k': 'completed', 'l': 'Completed'},
];
const _kEntryTypes = [
  {'k': 'client', 'l': 'Client'},
  {'k': 'material', 'l': 'Material'},
  {'k': 'labour', 'l': 'Labour'},
  {'k': 'contractor', 'l': 'Contractor'},
];
const _kPayModes = ['cash', 'upi', 'bank', 'cheque', 'rtgs'];

// ── Construction module: project list ────────────────────────────────────────
class ConstructionScreen extends StatelessWidget {
  const ConstructionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p   = context.watch<AppProvider>();
    final svc = ConstructionService();

    if (!p.canUseConstruction) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          title: const Text('Construction'),
        ),
        body: const ProLockView(
          feature: 'Construction Ledger',
          blurb: 'Track every site — projects, materials, labour, contractor '
              'bills, budget vs profit — with ArthaNote Pro.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text('🏗️ Projects',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        onPressed: () => _newProjectSheet(context, svc, p.businessId),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
      body: StreamBuilder<List<ConstructionProject>>(
        stream: svc.projectsStream(p.businessId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: kPrimary));
          }
          final projects = snap.data ?? [];
          if (projects.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏗️', style: TextStyle(fontSize: 44)),
                    SizedBox(height: 12),
                    Text('No projects yet',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6),
                    Text('Tap “New Project” to add your first site.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMuted)),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            itemCount: projects.length,
            itemBuilder: (_, i) => _ProjectCard(project: projects[i]),
          );
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ConstructionProject project;
  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final statusColor = {
      'planning': kMuted,
      'ongoing': kSecondary,
      'onhold': kAmber,
      'completed': kPrimary,
    }[project.status] ?? kMuted;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ConstructionProjectDetail(project: project))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(project.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _kStatuses.firstWhere((s) => s['k'] == project.status,
                    orElse: () => _kStatuses.first)['l']!,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          if (project.location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: kMuted),
              const SizedBox(width: 4),
              Text(project.location,
                  style: const TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (project.clientName.isNotEmpty)
              Expanded(
                child: Text('👤 ${project.clientName}',
                    style: const TextStyle(fontSize: 12, color: kText)),
              ),
            if (project.budget > 0)
              Text('Budget ${rupee(project.budget)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kPrimary)),
          ]),
        ]),
      ),
    );
  }
}

// ── New / edit project form ──────────────────────────────────────────────────
void _newProjectSheet(
    BuildContext context, ConstructionService svc, String businessId) {
  final nameCtrl   = TextEditingController();
  final locCtrl    = TextEditingController();
  final mapCtrl    = TextEditingController();
  final clientCtrl = TextEditingController();
  final phoneCtrl  = TextEditingController();
  final budgetCtrl = TextEditingController();
  String type   = 'residential';
  String status = 'planning';
  bool saving   = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('New Project',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            _field('Project name', nameCtrl, hint: 'e.g. Saravanan Residence'),
            const SizedBox(height: 14),
            _chipRow('Project type', _kProjectTypes, type,
                (v) => setSt(() => type = v)),
            const SizedBox(height: 14),
            _field('Location', locCtrl, hint: 'Area, City'),
            const SizedBox(height: 14),
            _field('Client name', clientCtrl, hint: "Client's name"),
            const SizedBox(height: 14),
            _field('Client phone', phoneCtrl,
                hint: '10-digit mobile', number: true),
            const SizedBox(height: 14),
            _chipRow('Status', _kStatuses, status,
                (v) => setSt(() => status = v)),
            const SizedBox(height: 14),
            _field('Total budget (₹)', budgetCtrl, hint: '0', number: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (saving || nameCtrl.text.trim().isEmpty)
                    ? null
                    : () async {
                        setSt(() => saving = true);
                        try {
                          await svc.addProject(ConstructionProject(
                            id: '',
                            businessId: businessId,
                            name: nameCtrl.text.trim(),
                            projectType: type,
                            location: locCtrl.text.trim(),
                            mapLink: mapCtrl.text.trim(),
                            clientName: clientCtrl.text.trim(),
                            clientPhone: phoneCtrl.text.trim(),
                            status: status,
                            budget:
                                double.tryParse(budgetCtrl.text.trim()) ?? 0,
                            createdAt: DateTime.now(),
                          ));
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setSt(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: kRed));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Create project',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ── Project detail (Summary + Ledger) ────────────────────────────────────────
class ConstructionProjectDetail extends StatelessWidget {
  final ConstructionProject project;
  const ConstructionProjectDetail({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final svc = ConstructionService();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              if (project.location.isNotEmpty)
                Text(project.location,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
            ],
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'Summary'), Tab(text: 'Ledger')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          onPressed: () => _addEntrySheet(context, svc, project),
          icon: const Icon(Icons.add),
          label: const Text('Add entry'),
        ),
        body: StreamBuilder<List<ConstructionEntry>>(
          stream: svc.entriesStream(project.id),
          builder: (context, snap) {
            final entries = snap.data ?? [];
            final summary = ProjectSummary.from(entries);
            return TabBarView(children: [
              _SummaryTab(project: project, summary: summary),
              _LedgerTab(entries: entries, svc: svc),
            ]);
          },
        ),
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final ConstructionProject project;
  final ProjectSummary summary;
  const _SummaryTab({required this.project, required this.summary});

  @override
  Widget build(BuildContext context) {
    final budgetUsed = project.budget > 0
        ? (summary.totalExpense / project.budget * 100).clamp(0, 999)
        : 0.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Net profit hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: kGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: kCardShadow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Net Profit',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              '${summary.netProfit >= 0 ? '+' : '−'} ${rupee(summary.netProfit)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _statCard('Total Expense', rupee(summary.totalExpense), kRed),
          const SizedBox(width: 12),
          _statCard('Total Income', rupee(summary.totalIncome), kSecondary),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statCard('Pending Collection', rupee(summary.pendingIn), kAmber),
          const SizedBox(width: 12),
          _statCard('Budget Used', '${budgetUsed.toStringAsFixed(0)}%', kPrimary),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: kCardShadow,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Expense Breakdown',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (summary.expenseByType.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No expenses yet',
                    style: TextStyle(color: kMuted)),
              )
            else
              ...summary.expenseByType.entries.map((e) {
                final pct = summary.totalExpense > 0
                    ? e.value / summary.totalExpense
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_capitalise(e.key),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(rupee(e.value),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: kRed)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.toDouble(),
                          minHeight: 6,
                          backgroundColor: const Color(0xFFF1F1F1),
                          color: kPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ]),
        ),
      ],
    );
  }
}

class _LedgerTab extends StatelessWidget {
  final List<ConstructionEntry> entries;
  final ConstructionService svc;
  const _LedgerTab({required this.entries, required this.svc});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text('No entries yet — tap “Add entry”.',
            style: TextStyle(color: kMuted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final e = entries[i];
        final income = e.isIncome;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: kCardShadow,
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (income ? kSecondary : kRed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(income ? Icons.south_west : Icons.north_east,
                  color: income ? kSecondary : kRed, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.desc.isNotEmpty
                        ? e.desc
                        : (e.vendor.isNotEmpty
                            ? e.vendor
                            : _capitalise(e.type)),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_capitalise(e.type)} · ${e.paidNow ? _capitalise(e.paymentMode) : 'On credit'} · ${DateFormat('d MMM').format(e.date)}',
                    style: const TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${income ? '+' : '−'} ${rupee(e.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: income ? kSecondary : kRed),
            ),
          ]),
        );
      },
    );
  }
}

// ── Add entry sheet ──────────────────────────────────────────────────────────
void _addEntrySheet(
    BuildContext context, ConstructionService svc, ConstructionProject project) {
  String type = 'material';
  bool gst = false;
  bool paidNow = true;
  String payMode = 'cash';
  DateTime date = DateTime.now();
  final descCtrl   = TextEditingController();
  final vendorCtrl = TextEditingController();
  final amountCtrl = TextEditingController(); // for non-material types
  // material line items — each is a list of controllers
  final items = <Map<String, TextEditingController>>[
    {
      'item': TextEditingController(),
      'qty': TextEditingController(text: '1'),
      'unit': TextEditingController(),
      'rate': TextEditingController(),
    }
  ];
  bool saving = false;

  double lineTotal() {
    double sum = 0;
    for (final it in items) {
      final q = double.tryParse(it['qty']!.text.trim()) ?? 0;
      final r = double.tryParse(it['rate']!.text.trim()) ?? 0;
      sum += q * r;
    }
    return sum;
  }

  double billTotal() {
    final base = type == 'material'
        ? lineTotal()
        : (double.tryParse(amountCtrl.text.trim()) ?? 0);
    return gst ? base * 1.18 : base;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Add entry',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            _chipRow('Type', _kEntryTypes, type, (v) => setSt(() => type = v)),
            const SizedBox(height: 16),

            if (type == 'material') ...[
              Row(children: [
                const Text('ITEMS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kMuted,
                        letterSpacing: 0.6)),
                const Spacer(),
                const Text('+ GST',
                    style: TextStyle(fontSize: 12, color: kMuted)),
                Switch(
                  value: gst,
                  activeColor: kPrimary,
                  onChanged: (v) => setSt(() => gst = v),
                ),
              ]),
              const SizedBox(height: 6),
              ...items.asMap().entries.map((entry) {
                final idx = entry.key;
                final it = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: _plainField(it['item']!, 'Item (e.g. Cement)',
                            onChanged: (_) => setSt(() {})),
                      ),
                      if (items.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: kRed),
                          onPressed: () => setSt(() => items.removeAt(idx)),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: _plainField(it['qty']!, 'Qty',
                              number: true, onChanged: (_) => setSt(() {}))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _plainField(it['unit']!, 'Unit (bag)')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _plainField(it['rate']!, 'Rate ₹',
                              number: true, onChanged: (_) => setSt(() {}))),
                    ]),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(rupee(
                          (double.tryParse(it['qty']!.text.trim()) ?? 0) *
                              (double.tryParse(it['rate']!.text.trim()) ?? 0)),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ]),
                );
              }),
              TextButton.icon(
                onPressed: () => setSt(() => items.add({
                      'item': TextEditingController(),
                      'qty': TextEditingController(text: '1'),
                      'unit': TextEditingController(),
                      'rate': TextEditingController(),
                    })),
                icon: const Icon(Icons.add, color: kPrimary),
                label: const Text('Add item',
                    style: TextStyle(color: kPrimary)),
              ),
            ] else ...[
              _field(
                  type == 'client' ? 'Amount received (₹)' : 'Amount (₹)',
                  amountCtrl,
                  hint: '0',
                  number: true,
                  onChanged: (_) => setSt(() {})),
            ],

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Text('Bill total',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(rupee(billTotal()),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 14),
            _field('Description', descCtrl, hint: 'Bill reference (optional)'),
            const SizedBox(height: 14),
            _field('Vendor / Party', vendorCtrl, hint: 'Who was it paid to?'),
            const SizedBox(height: 14),

            // date
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: date,
                  firstDate: DateTime(DateTime.now().year - 5),
                  lastDate: DateTime(DateTime.now().year + 2),
                );
                if (picked != null) setSt(() => date = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 18, color: kPrimary),
                  const SizedBox(width: 10),
                  Text(DateFormat('dd/MM/yyyy').format(date),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 14),

            // Paid now / on credit
            Row(children: [
              Expanded(
                child: _toggle('Paid now', paidNow, kSecondary,
                    () => setSt(() => paidNow = true)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _toggle('On credit', !paidNow, kAmber,
                    () => setSt(() => paidNow = false)),
              ),
            ]),
            if (paidNow) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _kPayModes
                    .map((m) => GestureDetector(
                          onTap: () => setSt(() => payMode = m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: payMode == m ? kPrimary : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: payMode == m
                                      ? kPrimary
                                      : const Color(0xFFE5E7EB)),
                            ),
                            child: Text(_capitalise(m),
                                style: TextStyle(
                                    color: payMode == m
                                        ? Colors.white
                                        : kText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final base = type == 'material'
                            ? lineTotal()
                            : (double.tryParse(amountCtrl.text.trim()) ?? 0);
                        if (base <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                              content: Text('Enter a valid amount'),
                              backgroundColor: kRed));
                          return;
                        }
                        setSt(() => saving = true);
                        final lineItems = type == 'material'
                            ? items
                                .where((it) =>
                                    it['item']!.text.trim().isNotEmpty)
                                .map((it) => ConstructionLineItem(
                                      item: it['item']!.text.trim(),
                                      qty: double.tryParse(
                                              it['qty']!.text.trim()) ??
                                          0,
                                      unit: it['unit']!.text.trim(),
                                      rate: double.tryParse(
                                              it['rate']!.text.trim()) ??
                                          0,
                                    ))
                                .toList()
                            : <ConstructionLineItem>[];
                        try {
                          await svc.addEntry(ConstructionEntry(
                            id: '',
                            businessId: project.businessId,
                            projectId: project.id,
                            type: type,
                            items: lineItems,
                            amount: gst ? base * 1.18 : base,
                            gst: gst,
                            gstAmount: gst ? base * 0.18 : 0,
                            desc: descCtrl.text.trim(),
                            vendor: vendorCtrl.text.trim(),
                            paidNow: paidNow,
                            paymentMode: payMode,
                            date: date,
                            createdAt: DateTime.now(),
                          ));
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setSt(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: kRed));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Save entry',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ── Small shared widgets/helpers ─────────────────────────────────────────────
String _capitalise(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Widget _statCard(String label, String value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: kMuted)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
    );

Widget _field(String label, TextEditingController ctrl,
        {String hint = '',
        bool number = false,
        ValueChanged<String>? onChanged}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kMuted,
              letterSpacing: 0.6)),
      const SizedBox(height: 6),
      _plainField(ctrl, hint, number: number, onChanged: onChanged),
    ]);

Widget _plainField(TextEditingController ctrl, String hint,
        {bool number = false, ValueChanged<String>? onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5),
        ),
      ),
    );

Widget _chipRow(String label, List<Map<String, String>> opts, String sel,
        ValueChanged<String> onSel) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kMuted,
              letterSpacing: 0.6)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: opts.map((o) {
          final on = o['k'] == sel;
          return GestureDetector(
            onTap: () => onSel(o['k']!),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: on ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: on ? kPrimary : const Color(0xFFE5E7EB)),
              ),
              child: Text(o['l']!,
                  style: TextStyle(
                      color: on ? Colors.white : kText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    ]);

Widget _toggle(String label, bool on, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? color : const Color(0xFFE5E7EB)),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? Colors.white : kText,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ),
    );
