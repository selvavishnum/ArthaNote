import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/supplier.dart';
import '../models/supplier_bill.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

// ── Period enum ───────────────────────────────────────────────────────────────
enum _Period { all, today, week, month, lastMonth, custom }

class SuppliersTab extends StatefulWidget {
  const SuppliersTab({super.key});
  @override
  State<SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<SuppliersTab> {
  final _db      = DbService();
  _Period        _period      = _Period.all;
  DateTimeRange? _customRange;

  DateTimeRange _range() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case _Period.today:
        return DateTimeRange(
            start: today,
            end: today.add(const Duration(days: 1)));
      case _Period.week:
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(
            start: startOfWeek,
            end: today.add(const Duration(days: 1)));
      case _Period.month:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: today.add(const Duration(days: 1)));
      case _Period.lastMonth:
        final first = DateTime(now.year, now.month - 1, 1);
        return DateTimeRange(
            start: first,
            end: DateTime(now.year, now.month, 1));
      case _Period.custom:
        return _customRange ??
            DateTimeRange(
                start: today,
                end: today.add(const Duration(days: 1)));
      case _Period.all:
        return DateTimeRange(
            start: DateTime(2000),
            end: DateTime(2100));
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _customRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period      = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, p, l),
        _buildPeriodRow(l),
        Expanded(
          child: StreamBuilder<List<Supplier>>(
            stream: _db.supplierStream(p.businessId),
            builder: (ctx, supSnap) {
              if (supSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: kPrimary));
              }
              final suppliers = supSnap.data ?? [];

              return StreamBuilder<List<SupplierBill>>(
                stream: _db.allSupplierBillStream(p.businessId),
                builder: (ctx, billSnap) {
                  if (billSnap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: kPrimary));
                  }
                  final allBills = billSnap.data ?? [];
                  return _buildBody(suppliers, allBills, l);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, AppProvider p, String l) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Text(
            '🤝 Suppliers',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: kText),
          ),
          const Spacer(),
          _HeaderBtn(
            label: '+ Add Supplier',
            color: kPrimary,
            onTap: () => _showAddSupplierSheet(context, p),
          ),
          const SizedBox(width: 8),
          _HeaderBtn(
            label: '📋 Bill/Payment',
            color: const Color(0xFF2563EB),
            onTap: () => _showAddBillSheet(context, p),
          ),
        ],
      ),
    );
  }

  // ── Period chips row ──────────────────────────────────────────────────────
  Widget _buildPeriodRow(String l) {
    final customLabel = _period == _Period.custom && _customRange != null
        ? '${DateFormat('d MMM').format(_customRange!.start)} – '
          '${DateFormat('d MMM').format(_customRange!.end)}'
        : t('custom', l);

    final chips = <({_Period p, String label})>[
      (p: _Period.all,       label: t('all', l)),
      (p: _Period.today,     label: t('today', l)),
      (p: _Period.week,      label: t('this_week', l)),
      (p: _Period.month,     label: t('this_month', l)),
      (p: _Period.lastMonth, label: t('last_month', l)),
      (p: _Period.custom,    label: customLabel),
    ];

    return Container(
      color: Colors.white,
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          children: chips.map((c) {
            final active = _period == c.p;
            return GestureDetector(
              onTap: () {
                if (c.p == _Period.custom) {
                  _pickCustomRange();
                } else {
                  setState(() => _period = c.p);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: active ? kPrimary : const Color(0xFFE5E7EB)),
                ),
                child: Center(
                  child: Text(
                    c.label,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(List<Supplier> suppliers,
      List<SupplierBill> allBills, String l) {
    final range       = _range();
    final periodBills = allBills
        .where((b) =>
            !b.date.isBefore(range.start) && b.date.isBefore(range.end))
        .toList();

    if (suppliers.isEmpty) {
      return _EmptyState(l: l);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      itemCount: suppliers.length,
      itemBuilder: (_, i) {
        final sup      = suppliers[i];
        final supBills = periodBills
            .where((b) => b.supplierId == sup.id)
            .toList();
        return _SupplierCard(
          supplier: sup,
          bills:    supBills,
          db:       _db,
          l:        l,
        );
      },
    );
  }

  // ── Add Supplier sheet ────────────────────────────────────────────────────
  void _showAddSupplierSheet(BuildContext context, AppProvider p) {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final balCtrl   = TextEditingController();
    bool saving     = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SheetHandle(),
            const SizedBox(height: 16),
            Row(children: [
              _CircleIcon(icon: Icons.store_outlined, color: kPrimary),
              const SizedBox(width: 12),
              const Text('Add Supplier',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: kPrimary)),
            ]),
            const SizedBox(height: 20),
            TextFormField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Supplier Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: balCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening Balance ₹ (amount you owe)',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        setSt(() => saving = true);
                        await _db.addSupplier(Supplier(
                          id:         '',
                          businessId: p.businessId,
                          name:       nameCtrl.text.trim(),
                          phone:      phoneCtrl.text.trim(),
                          balance:    double.tryParse(balCtrl.text) ?? 0,
                        ));
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Save Supplier',
                        style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Add Bill/Payment sheet ────────────────────────────────────────────────
  void _showAddBillSheet(BuildContext context, AppProvider p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddBillSheet(db: _db, p: p),
    );
  }
}

// ── Add Bill Sheet widget ──────────────────────────────────────────────────────
class _AddBillSheet extends StatefulWidget {
  final DbService   db;
  final AppProvider p;
  const _AddBillSheet({required this.db, required this.p});

  @override
  State<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<_AddBillSheet> {
  String?     _supplierId;
  String      _type    = 'payment';
  final _amtCtrl       = TextEditingController();
  final _descCtrl      = TextEditingController();
  DateTime    _date    = DateTime.now();
  bool        _saving  = false;

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Supplier>>(
      stream: widget.db.supplierStream(widget.p.businessId),
      builder: (ctx, snap) {
        final suppliers = snap.data ?? [];
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SheetHandle(),
            const SizedBox(height: 16),
            Row(children: [
              _CircleIcon(
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFF2563EB)),
              const SizedBox(width: 12),
              const Text('Bill / Payment',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF2563EB))),
            ]),
            const SizedBox(height: 20),

            // Supplier picker
            DropdownButtonFormField<String>(
              value: _supplierId,
              hint: const Text('Select Supplier'),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.store_outlined)),
              items: suppliers
                  .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            const SizedBox(height: 12),

            // Type toggle: BILL / PAYMENT
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _type = 'bill'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _type == 'bill' ? kRed : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _type == 'bill'
                              ? kRed
                              : const Color(0xFFE5E7EB)),
                    ),
                    child: Center(
                      child: Text(
                        'BILL',
                        style: TextStyle(
                          color: _type == 'bill'
                              ? Colors.white
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _type = 'payment'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _type == 'payment' ? kSecondary : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _type == 'payment'
                              ? kSecondary
                              : const Color(0xFFE5E7EB)),
                    ),
                    child: Center(
                      child: Text(
                        'PAYMENT',
                        style: TextStyle(
                          color: _type == 'payment'
                              ? Colors.white
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // Amount field
            TextFormField(
              controller: _amtCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary),
              decoration: const InputDecoration(
                labelText: 'Amount ₹',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Description field
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Date picker row
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme:
                          const ColorScheme.light(primary: kPrimary),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 18, color: kMuted),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('d MMM yyyy').format(_date),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 18, color: kMuted),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_supplierId == null) return;
                        final amount =
                            double.tryParse(_amtCtrl.text.trim());
                        if (amount == null || amount <= 0) return;
                        final supplier = suppliers.firstWhere(
                            (s) => s.id == _supplierId,
                            orElse: () => suppliers.first);
                        setState(() => _saving = true);
                        await widget.db.addSupplierBill(SupplierBill(
                          id:           '',
                          businessId:   widget.p.businessId,
                          supplierId:   _supplierId!,
                          supplierName: supplier.name,
                          date:         _date,
                          type:         _type,
                          amount:       amount,
                          desc:         _descCtrl.text.trim(),
                        ));
                        if (mounted) Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB)),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Save',
                        style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Supplier card ─────────────────────────────────────────────────────────────
class _SupplierCard extends StatefulWidget {
  final Supplier           supplier;
  final List<SupplierBill> bills;
  final DbService          db;
  final String             l;

  const _SupplierCard({
    required this.supplier,
    required this.bills,
    required this.db,
    required this.l,
  });

  @override
  State<_SupplierCard> createState() => _SupplierCardState();
}

class _SupplierCardState extends State<_SupplierCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sup   = widget.supplier;
    final bills = widget.bills;
    final isDue = sup.balance > 0;
    final color = isDue ? kRed : kSecondary;

    final totalBills = bills
        .where((b) => b.type == 'bill')
        .fold(0.0, (s, b) => s + b.amount);
    final totalPaid = bills
        .where((b) => b.type == 'payment')
        .fold(0.0, (s, b) => s + b.amount);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: avatar, name/phone, balance
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: kPrimary.withOpacity(0.1),
                  child: Text(
                    sup.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sup.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      if (sup.phone.isNotEmpty)
                        Text(sup.phone,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rupee(sup.balance),
                        style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isDue ? t('due', widget.l) : t('paid', widget.l),
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ]),

              const SizedBox(height: 10),

              // Row 2: stats bar (BILLS | PAID | BALANCE)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: IntrinsicHeight(
                  child: Row(children: [
                    _StatCol(
                        label: 'BILLS',
                        value: rupee(totalBills),
                        color: kRed),
                    _VertDiv(),
                    _StatCol(
                        label: 'PAID',
                        value: rupee(totalPaid),
                        color: kSecondary),
                    _VertDiv(),
                    _StatCol(
                        label: 'BALANCE',
                        value: rupee(sup.balance),
                        color: color),
                  ]),
                ),
              ),

              // Expand toggle hint
              const SizedBox(height: 6),
              Row(children: [
                const Spacer(),
                Text(
                  _expanded
                      ? '▲ Hide history'
                      : '▼ Show history (${bills.length})',
                  style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
              ]),

              // Inline bill history (expanded)
              if (_expanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 6),
                if (bills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        'No transactions in this period',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12),
                      ),
                    ),
                  )
                else
                  ...bills.map((b) => _BillRow(bill: b, db: widget.db)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Individual bill row ───────────────────────────────────────────────────────
class _BillRow extends StatelessWidget {
  final SupplierBill bill;
  final DbService    db;
  const _BillRow({required this.bill, required this.db});

  @override
  Widget build(BuildContext context) {
    final isBill = bill.type == 'bill';
    final color  = isBill ? kRed : kSecondary;

    return Dismissible(
      key: Key(bill.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: kRed.withOpacity(0.1),
        child: const Icon(Icons.delete_outline, color: kRed),
      ),
      onDismissed: (_) => db.deleteSupplierBill(bill),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.desc.isEmpty
                      ? (isBill ? 'Bill' : 'Payment')
                      : bill.desc,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  DateFormat('d MMM').format(bill.date),
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isBill ? '+' : '-'}${rupee(bill.amount)}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ]),
      ),
    );
  }
}

// ── Stat column ───────────────────────────────────────────────────────────────
class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatCol(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(label,
          style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    ]),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _VertDiv extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    color: const Color(0xFFE5E7EB),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2)),
    ),
  );
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final Color    color;
  const _CircleIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
        color: color.withOpacity(0.1), shape: BoxShape.circle),
    child: Icon(icon, color: color, size: 20),
  );
}

class _HeaderBtn extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _HeaderBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    ),
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String l;
  const _EmptyState({required this.l});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08), shape: BoxShape.circle),
        child:
            const Center(child: Text('🤝', style: TextStyle(fontSize: 36))),
      ),
      const SizedBox(height: 18),
      Text(t('no_suppliers', l),
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 17, color: kPrimary)),
      const SizedBox(height: 8),
      Text('Tap "+ Add Supplier" to get started',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ]),
  );
}
