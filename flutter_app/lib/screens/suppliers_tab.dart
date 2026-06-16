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
                  return _buildBody(suppliers, allBills, p, l);
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
      List<SupplierBill> allBills, AppProvider p, String l) {
    final range       = _range();
    final periodBills = allBills
        .where((b) =>
            !b.date.isBefore(range.start) && b.date.isBefore(range.end))
        .toList();

    // Filter suppliers by shop context:
    // - Cashier: only their assigned shop + shared (empty shopId)
    // - Owner with a shop selected: that shop + shared
    // - Owner with all shops: show all
    final List<Supplier> visibleSuppliers;
    if (p.isCashier && p.staffShop.isNotEmpty) {
      visibleSuppliers = suppliers.where((s) => s.shopId.isEmpty || s.shopId == p.staffShop).toList();
    } else if (!p.isCashier && p.selectedShop.isNotEmpty) {
      visibleSuppliers = suppliers.where((s) => s.shopId.isEmpty || s.shopId == p.selectedShop).toList();
    } else {
      visibleSuppliers = suppliers;
    }

    if (visibleSuppliers.isEmpty) {
      return _EmptyState(l: l);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
      itemCount: visibleSuppliers.length,
      itemBuilder: (_, i) {
        final sup      = visibleSuppliers[i];
        final supBills = periodBills
            .where((b) => b.supplierId == sup.id)
            .toList();
        return _SupplierCard(
          supplier:  sup,
          bills:     supBills,
          isAllTime: _period == _Period.all,
          db:        _db,
          p:         p,
          l:         l,
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
    String shopId   = '';

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
            Row(children: const [
              _CircleIcon(icon: Icons.store_outlined, color: kPrimary),
              SizedBox(width: 12),
              Text('Add Supplier',
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
            // Shop selector (owner only — cashier auto-assigned)
            if (!p.isCashier && p.shops.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: shopId.isEmpty ? null : shopId,
                hint: const Text('All Shops (shared supplier)'),
                decoration: const InputDecoration(
                  labelText: 'Assign to Shop (optional)',
                  prefixIcon: Icon(Icons.store_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                      value: '',
                      child: Text('All Shops')),
                  ...p.shops.values.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.icon} ${s.name}'),
                      )),
                ],
                onChanged: (v) => setSt(() => shopId = v ?? ''),
              ),
            ],
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
                          shopId:     p.isCashier ? p.staffShop : shopId,
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
  final Supplier?   presetSupplier; // pre-select a supplier when opened from ⋮ menu
  const _AddBillSheet({
    required this.db,
    required this.p,
    this.presetSupplier,
  });

  @override
  State<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends State<_AddBillSheet> {
  String?     _supplierId;
  String      _type    = 'bill';
  final _amtCtrl       = TextEditingController();
  final _descCtrl      = TextEditingController();
  DateTime    _date    = DateTime.now();
  bool        _saving  = false;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.presetSupplier?.id;
  }

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
        final allSuppliers = snap.data ?? [];
        final suppliers = widget.p.isCashier && widget.p.staffShop.isNotEmpty
            ? allSuppliers.where((s) => s.shopId.isEmpty || s.shopId == widget.p.staffShop).toList()
            : allSuppliers;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SheetHandle(),
            const SizedBox(height: 16),
            Row(children: const [
              _CircleIcon(
                  icon: Icons.receipt_long_outlined,
                  color: Color(0xFF2563EB)),
              SizedBox(width: 12),
              Text('Bill / Payment',
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

// ── Edit Bill Sheet ───────────────────────────────────────────────────────────
class _EditBillSheet extends StatefulWidget {
  final DbService    db;
  final SupplierBill oldBill;
  const _EditBillSheet({required this.db, required this.oldBill});

  @override
  State<_EditBillSheet> createState() => _EditBillSheetState();
}

class _EditBillSheetState extends State<_EditBillSheet> {
  late String   _type;
  late DateTime _date;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b   = widget.oldBill;
    _type     = b.type;
    _date     = b.date;
    _amtCtrl  = TextEditingController(text: b.amount.toStringAsFixed(
        b.amount == b.amount.truncateToDouble() ? 0 : 2));
    _descCtrl = TextEditingController(text: b.desc);
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _type == 'bill' ? kRed : kSecondary;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SheetHandle(),
        const SizedBox(height: 16),
        Row(children: [
          _CircleIcon(icon: Icons.edit_outlined, color: typeColor),
          const SizedBox(width: 12),
          const Text('Edit Entry',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18, color: kText)),
        ]),
        const SizedBox(height: 20),

        // Type toggle
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
                      color: _type == 'bill' ? kRed : const Color(0xFFE5E7EB)),
                ),
                child: Center(
                  child: Text('BILL',
                      style: TextStyle(
                          color: _type == 'bill'
                              ? Colors.white
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
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
                  child: Text('PAYMENT',
                      style: TextStyle(
                          color: _type == 'payment'
                              ? Colors.white
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        TextFormField(
          controller: _amtCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: typeColor),
          decoration: const InputDecoration(
              labelText: 'Amount ₹',
              prefixIcon: Icon(Icons.payments_outlined)),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _descCtrl,
          decoration: const InputDecoration(
              labelText: 'Description (optional)',
              prefixIcon: Icon(Icons.notes_outlined)),
        ),
        const SizedBox(height: 12),

        // Date picker
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(primary: kPrimary)),
                child: child!,
              ),
            );
            if (picked != null) setState(() => _date = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 18, color: kMuted),
              const SizedBox(width: 10),
              Text(DateFormat('d MMM yyyy').format(_date),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 18, color: kMuted),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    final amount =
                        double.tryParse(_amtCtrl.text.trim());
                    if (amount == null || amount <= 0) return;
                    setState(() => _saving = true);
                    final newBill = SupplierBill(
                      id:           widget.oldBill.id,
                      businessId:   widget.oldBill.businessId,
                      supplierId:   widget.oldBill.supplierId,
                      supplierName: widget.oldBill.supplierName,
                      date:         _date,
                      type:         _type,
                      amount:       amount,
                      desc:         _descCtrl.text.trim(),
                    );
                    await widget.db.updateSupplierBill(widget.oldBill, newBill);
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(backgroundColor: typeColor),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Update Entry',
                    style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ── Supplier card ─────────────────────────────────────────────────────────────
class _SupplierCard extends StatefulWidget {
  final Supplier           supplier;
  final List<SupplierBill> bills;
  final bool               isAllTime;  // true when the "All" period filter is active (bills = full history)
  final DbService          db;
  final AppProvider        p;
  final String             l;

  const _SupplierCard({
    required this.supplier,
    required this.bills,
    required this.isAllTime,
    required this.db,
    required this.p,
    required this.l,
  });

  @override
  State<_SupplierCard> createState() => _SupplierCardState();
}

class _SupplierCardState extends State<_SupplierCard> {
  bool _expanded = false;

  // ── Edit supplier sheet ──────────────────────────────────────────────────
  void _showEditSheet(BuildContext context) {
    final sup       = widget.supplier;
    final nameCtrl  = TextEditingController(text: sup.name);
    final phoneCtrl = TextEditingController(text: sup.phone);
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
              _CircleIcon(icon: Icons.edit_outlined, color: kPrimary),
              const SizedBox(width: 12),
              const Text('Edit Supplier',
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
                  prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined)),
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
                        await widget.db.updateSupplierInfo(
                          sup.id,
                          nameCtrl.text.trim(),
                          phoneCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                child: saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Save Changes',
                        style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Add bill for this specific supplier ───────────────────────────────────
  void _showAddBillHere(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddBillSheet(
        db:             widget.db,
        p:              widget.p,
        presetSupplier: widget.supplier,
      ),
    );
  }

  // ── Delete supplier ───────────────────────────────────────────────────────
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Supplier?'),
        content: Text(
            'This will permanently delete "${widget.supplier.name}".\nBill history will remain but the supplier card will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.db.deleteSupplier(widget.supplier.id);
            },
            child:
                const Text('Delete', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  // ── Edit bill/payment entry ───────────────────────────────────────────────
  void _showEditBillSheet(BuildContext context, SupplierBill oldBill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) =>
          _EditBillSheet(db: widget.db, oldBill: oldBill),
    );
  }

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

    // sup.balance is the running due, atomically kept in sync with every
    // bill/payment (opening balance + all-time bills − all-time payments).
    // The period-filtered totals above don't include the opening balance,
    // so when showing full history, fold it back in to keep BILLS/BALANCE
    // consistent with the correct due amount above.
    final openingBalance = widget.isAllTime
        ? sup.balance - totalBills + totalPaid
        : 0.0;
    final displayBills   = totalBills + openingBalance;
    final displayBalance = widget.isAllTime ? sup.balance : (totalBills - totalPaid);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showAddBillHere(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: avatar, name/phone, balance, ⋮ menu
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
                const SizedBox(width: 4),
                // ⋮ context menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: kMuted),
                  onSelected: (v) {
                    if (v == 'edit')   _showEditSheet(context);
                    if (v == 'bill')   _showAddBillHere(context);
                    if (v == 'delete') _confirmDelete(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 16, color: kPrimary),
                        SizedBox(width: 10),
                        Text('Edit Supplier'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'bill',
                      child: Row(children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 16, color: Color(0xFF2563EB)),
                        SizedBox(width: 10),
                        Text('Add Bill / Payment'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 16, color: kRed),
                        SizedBox(width: 10),
                        Text('Delete Supplier',
                            style: TextStyle(color: kRed)),
                      ]),
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
                        value: rupee(displayBills),
                        color: kRed),
                    _VertDiv(),
                    _StatCol(
                        label: 'PAID',
                        value: rupee(totalPaid),
                        color: kSecondary),
                    _VertDiv(),
                    _StatCol(
                        label: 'BALANCE',
                        value: rupee(displayBalance),
                        color: displayBalance > 0 ? kRed : kSecondary),
                  ]),
                ),
              ),

              // Expand toggle hint
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
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
              ),

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
                  ...bills.map((b) => _BillRow(
                        bill: b,
                        db:   widget.db,
                        onEdit: () => _showEditBillSheet(context, b),
                      )),
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
  final VoidCallback onEdit;
  const _BillRow({required this.bill, required this.db, required this.onEdit});

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
            '${bill.type == 'bill' ? 'Bill' : 'Payment'} of ${rupee(bill.amount)}'
            '${bill.desc.isNotEmpty ? ' (${bill.desc})' : ''}\n'
            '${DateFormat('d MMM yyyy').format(bill.date)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await db.deleteSupplierBill(bill);
            },
            child: const Text('Delete', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

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
      confirmDismiss: (_) async {
        _confirmDelete(context);
        return false; // let the dialog handle deletion
      },
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
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
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${isBill ? '+' : '-'}${rupee(bill.amount)}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onEdit,
              child: const Icon(Icons.edit_outlined,
                  size: 14, color: kMuted),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _confirmDelete(context),
              child: const Icon(Icons.delete_outline,
                  size: 14, color: kRed),
            ),
          ]),
        ),
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
  const _VertDiv();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    color: const Color(0xFFE5E7EB),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
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
