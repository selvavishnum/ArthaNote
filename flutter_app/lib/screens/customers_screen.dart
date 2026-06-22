import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/customer.dart';
import '../models/customer_txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

/// Customer credit ledger (உதிரி கணக்கு).
///
/// A full-screen view (pushed from the Quick-Actions sheet) that mirrors the
/// Supplier ledger but tracks money the SHOP has to collect from customers.
/// `Customer.balance > 0` ⇒ the customer owes the shop (money to collect).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _db = DbService();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kText,
        elevation: 0.5,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👥 ', style: TextStyle(fontSize: 18)),
            Text(
              t('customers', l),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17, color: kText),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _showAddCustomerSheet(context, p),
            icon: const Icon(Icons.person_add_alt_1, size: 18, color: kPrimary),
            label: Text(
              t('add_customer', l),
              style: const TextStyle(
                  color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(t('add_credit_payment', l)),
        onPressed: () => _showAddTxnSheet(context, p),
      ),
      body: StreamBuilder<List<Customer>>(
        stream: _db.customerStream(p.businessId),
        builder: (ctx, custSnap) {
          if (custSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final customers = custSnap.data ?? [];

          return StreamBuilder<List<CustomerTxn>>(
            stream: _db.allCustomerTxnStream(p.businessId),
            builder: (ctx, txnSnap) {
              if (txnSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: kPrimary));
              }
              final allTxns = txnSnap.data ?? [];
              return _buildBody(customers, allTxns, p, l);
            },
          );
        },
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody(List<Customer> customers, List<CustomerTxn> allTxns,
      AppProvider p, String l) {
    // Shop filtering — same rules as the supplier ledger.
    final List<Customer> visible;
    if (p.isCashier && p.staffShop.isNotEmpty) {
      visible = customers
          .where((c) => c.shopId.isEmpty || c.shopId == p.staffShop)
          .toList();
    } else if (!p.isCashier && p.selectedShop.isNotEmpty) {
      visible = customers
          .where((c) => c.shopId.isEmpty || c.shopId == p.selectedShop)
          .toList();
    } else {
      visible = customers;
    }

    if (visible.isEmpty) return _EmptyState(l: l);

    final outstanding = visible
        .where((c) => c.balance > 0)
        .fold(0.0, (s, c) => s + c.balance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBanner(outstanding: outstanding, count: visible.length, l: l),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final cust = visible[i];
              final custTxns =
                  allTxns.where((x) => x.customerId == cust.id).toList();
              return _CustomerCard(
                customer: cust,
                txns:     custTxns,
                db:       _db,
                p:        p,
                l:        l,
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Add Customer sheet ──────────────────────────────────────────────────────
  void _showAddCustomerSheet(BuildContext context, AppProvider p) {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final balCtrl   = TextEditingController();
    bool saving     = false;
    String shopId   = '';
    final l = p.lang;

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
            const _SheetHandle(),
            const SizedBox(height: 16),
            Row(children: [
              const _CircleIcon(
                  icon: Icons.person_add_alt_1, color: kPrimary),
              const SizedBox(width: 12),
              Text(t('add_customer', l),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: kPrimary)),
            ]),
            const SizedBox(height: 20),
            TextFormField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: t('customer_name', l),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: '${t('phone', l)} (optional)',
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: balCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    '${t('opening_balance', l)} ${p.currency.symbol} (${t('to_collect', l)})',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            if (!p.isCashier && p.shops.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: shopId.isEmpty ? null : shopId,
                hint: const Text('All Shops (shared)'),
                decoration: const InputDecoration(
                  labelText: 'Assign to Shop (optional)',
                  prefixIcon: Icon(Icons.store_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All Shops')),
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
                        await _db.addCustomer(Customer(
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
                    : Text(t('save', l),
                        style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Add Credit/Payment sheet ────────────────────────────────────────────────
  void _showAddTxnSheet(BuildContext context, AppProvider p,
      {Customer? preset}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddTxnSheet(db: _db, p: p, presetCustomer: preset),
    );
  }
}

// ── Summary banner ──────────────────────────────────────────────────────────────
class _SummaryBanner extends StatelessWidget {
  final double outstanding;
  final int    count;
  final String l;
  const _SummaryBanner(
      {required this.outstanding, required this.count, required this.l});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF065f46), Color(0xFF059669)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('to_collect', l).toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFFA7F3D0),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              rupee(outstanding),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            Text(t('customers', l),
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}

// ── Add Txn Sheet ─────────────────────────────────────────────────────────────
class _AddTxnSheet extends StatefulWidget {
  final DbService   db;
  final AppProvider p;
  final Customer?   presetCustomer;
  const _AddTxnSheet({required this.db, required this.p, this.presetCustomer});

  @override
  State<_AddTxnSheet> createState() => _AddTxnSheetState();
}

class _AddTxnSheetState extends State<_AddTxnSheet> {
  String?  _customerId;
  String   _type    = 'credit';
  final _amtCtrl    = TextEditingController();
  final _descCtrl   = TextEditingController();
  DateTime _date    = DateTime.now();
  bool     _saving  = false;

  @override
  void initState() {
    super.initState();
    _customerId = widget.presetCustomer?.id;
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.p.lang;
    return StreamBuilder<List<Customer>>(
      stream: widget.db.customerStream(widget.p.businessId),
      builder: (ctx, snap) {
        final allCustomers = snap.data ?? [];
        final customers = widget.p.isCashier && widget.p.staffShop.isNotEmpty
            ? allCustomers
                .where((c) =>
                    c.shopId.isEmpty || c.shopId == widget.p.staffShop)
                .toList()
            : allCustomers;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _SheetHandle(),
            const SizedBox(height: 16),
            Row(children: [
              const _CircleIcon(
                  icon: Icons.receipt_long_outlined,
                  color: Color(0xFF2563EB)),
              const SizedBox(width: 12),
              Text(t('add_credit_payment', l),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Color(0xFF2563EB))),
            ]),
            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              value: _customerId,
              hint: Text(t('customers', l)),
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
              items: customers
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _customerId = v),
            ),
            const SizedBox(height: 12),

            // CREDIT / PAYMENT toggle
            Row(children: [
              Expanded(
                child: _ToggleBtn(
                  label: t('credit', l).toUpperCase(),
                  active: _type == 'credit',
                  activeColor: kRed,
                  onTap: () => setState(() => _type = 'credit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleBtn(
                  label: t('payment', l).toUpperCase(),
                  active: _type == 'payment',
                  activeColor: kSecondary,
                  onTap: () => setState(() => _type = 'payment'),
                ),
              ),
            ]),
            const SizedBox(height: 12),

            TextFormField(
              controller: _amtCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary),
              decoration: InputDecoration(
                labelText: '${t('amount', l)} ${widget.p.currency.symbol}',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: '${t('description', l)} (optional)',
                prefixIcon: const Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),

            _DateField(
              date: _date,
              onPick: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (_customerId == null) return;
                        final amount = double.tryParse(_amtCtrl.text.trim());
                        if (amount == null || amount <= 0) return;
                        // Null-safe lookup — never throws even if the stream
                        // briefly returns an empty/stale list.
                        Customer? customer;
                        for (final c in customers) {
                          if (c.id == _customerId) { customer = c; break; }
                        }
                        if (customer == null) return;
                        setState(() => _saving = true);
                        await widget.db.addCustomerTxn(CustomerTxn(
                          id:           '',
                          businessId:   widget.p.businessId,
                          customerId:   _customerId!,
                          customerName: customer.name,
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
                    : Text(t('save', l),
                        style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Edit Txn Sheet ────────────────────────────────────────────────────────────
class _EditTxnSheet extends StatefulWidget {
  final DbService   db;
  final CustomerTxn oldTxn;
  const _EditTxnSheet({required this.db, required this.oldTxn});

  @override
  State<_EditTxnSheet> createState() => _EditTxnSheetState();
}

class _EditTxnSheetState extends State<_EditTxnSheet> {
  late String   _type;
  late DateTime _date;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final x   = widget.oldTxn;
    _type     = x.type;
    _date     = x.date;
    _amtCtrl  = TextEditingController(
        text: x.amount.toStringAsFixed(
            x.amount == x.amount.truncateToDouble() ? 0 : 2));
    _descCtrl = TextEditingController(text: x.desc);
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;
    final typeColor = _type == 'credit' ? kRed : kSecondary;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        Row(children: [
          _CircleIcon(icon: Icons.edit_outlined, color: typeColor),
          const SizedBox(width: 12),
          const Text('Edit Entry',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 18, color: kText)),
        ]),
        const SizedBox(height: 20),

        Row(children: [
          Expanded(
            child: _ToggleBtn(
              label: t('credit', l).toUpperCase(),
              active: _type == 'credit',
              activeColor: kRed,
              onTap: () => setState(() => _type = 'credit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ToggleBtn(
              label: t('payment', l).toUpperCase(),
              active: _type == 'payment',
              activeColor: kSecondary,
              onTap: () => setState(() => _type = 'payment'),
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
          decoration: InputDecoration(
              labelText: '${t('amount', l)} ${p.currency.symbol}',
              prefixIcon: const Icon(Icons.payments_outlined)),
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _descCtrl,
          decoration: InputDecoration(
              labelText: '${t('description', l)} (optional)',
              prefixIcon: const Icon(Icons.notes_outlined)),
        ),
        const SizedBox(height: 12),

        _DateField(date: _date, onPick: (d) => setState(() => _date = d)),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    final amount = double.tryParse(_amtCtrl.text.trim());
                    if (amount == null || amount <= 0) return;
                    setState(() => _saving = true);
                    final newTxn = CustomerTxn(
                      id:           widget.oldTxn.id,
                      businessId:   widget.oldTxn.businessId,
                      customerId:   widget.oldTxn.customerId,
                      customerName: widget.oldTxn.customerName,
                      date:         _date,
                      type:         _type,
                      amount:       amount,
                      desc:         _descCtrl.text.trim(),
                    );
                    await widget.db.updateCustomerTxn(widget.oldTxn, newTxn);
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(backgroundColor: typeColor),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(t('save', l),
                    style: const TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────
class _CustomerCard extends StatefulWidget {
  final Customer          customer;
  final List<CustomerTxn> txns;
  final DbService         db;
  final AppProvider       p;
  final String            l;

  const _CustomerCard({
    required this.customer,
    required this.txns,
    required this.db,
    required this.p,
    required this.l,
  });

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {
  bool _expanded = false;

  void _showEditCustomerSheet(BuildContext context) {
    final c         = widget.customer;
    final nameCtrl  = TextEditingController(text: c.name);
    final phoneCtrl = TextEditingController(text: c.phone);
    final l         = widget.l;
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
            const _SheetHandle(),
            const SizedBox(height: 16),
            Row(children: [
              const _CircleIcon(icon: Icons.edit_outlined, color: kPrimary),
              const SizedBox(width: 12),
              const Text('Edit Customer',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: kPrimary)),
            ]),
            const SizedBox(height: 20),
            TextFormField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  labelText: t('customer_name', l),
                  prefixIcon: const Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: '${t('phone', l)} (optional)',
                  prefixIcon: const Icon(Icons.phone_outlined)),
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
                        await widget.db.updateCustomerInfo(
                          c.id,
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
                    : Text(t('save', l),
                        style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showAddTxnHere(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddTxnSheet(
        db:             widget.db,
        p:              widget.p,
        presetCustomer: widget.customer,
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text(
            'This will permanently delete "${widget.customer.name}".\nTransaction history will remain but the customer card will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('cancel', widget.l))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.db.deleteCustomer(widget.customer.id);
            },
            child: Text(t('delete', widget.l),
                style: const TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  void _showEditTxnSheet(BuildContext context, CustomerTxn oldTxn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _EditTxnSheet(db: widget.db, oldTxn: oldTxn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c     = widget.customer;
    final txns  = widget.txns;
    // balance > 0 ⇒ the customer owes the shop ⇒ money to collect (red).
    final toCollect = c.balance > 0;
    final color = toCollect ? kRed : kSecondary;

    final totalCredit = txns
        .where((x) => x.type == 'credit')
        .fold(0.0, (s, x) => s + x.amount);
    final totalPaid = txns
        .where((x) => x.type == 'payment')
        .fold(0.0, (s, x) => s + x.amount);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showAddTxnHere(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: kPrimary.withOpacity(0.1),
                  child: Text(
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
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
                      Text(c.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      if (c.phone.isNotEmpty)
                        Text(c.phone,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rupee(c.balance),
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
                        toCollect
                            ? t('to_collect', widget.l)
                            : t('settled', widget.l),
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: kMuted),
                  onSelected: (v) {
                    if (v == 'edit')   _showEditCustomerSheet(context);
                    if (v == 'txn')    _showAddTxnHere(context);
                    if (v == 'delete') _confirmDelete(context);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: const [
                        Icon(Icons.edit_outlined, size: 16, color: kPrimary),
                        SizedBox(width: 10),
                        Text('Edit Customer'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'txn',
                      child: Row(children: const [
                        Icon(Icons.receipt_long_outlined,
                            size: 16, color: Color(0xFF2563EB)),
                        SizedBox(width: 10),
                        Text('Add Credit / Payment'),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline, size: 16, color: kRed),
                        const SizedBox(width: 10),
                        Text(t('delete', widget.l),
                            style: const TextStyle(color: kRed)),
                      ]),
                    ),
                  ],
                ),
              ]),

              const SizedBox(height: 10),

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
                        label: t('credit', widget.l).toUpperCase(),
                        value: rupee(totalCredit),
                        color: kRed),
                    const _VertDiv(),
                    _StatCol(
                        label: t('paid', widget.l).toUpperCase(),
                        value: rupee(totalPaid),
                        color: kSecondary),
                    const _VertDiv(),
                    _StatCol(
                        label: t('balance', widget.l).toUpperCase(),
                        value: rupee(c.balance),
                        color: color),
                  ]),
                ),
              ),

              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
                  const Spacer(),
                  Text(
                    _expanded
                        ? '▲ Hide history'
                        : '▼ Show history (${txns.length})',
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ]),
              ),

              if (_expanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 6),
                if (txns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        t('no_entries', widget.l),
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12),
                      ),
                    ),
                  )
                else
                  ...txns.map((x) => _TxnRow(
                        txn:    x,
                        db:     widget.db,
                        l:      widget.l,
                        onEdit: () => _showEditTxnSheet(context, x),
                      )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Individual txn row ────────────────────────────────────────────────────────
class _TxnRow extends StatelessWidget {
  final CustomerTxn txn;
  final DbService   db;
  final String      l;
  final VoidCallback onEdit;
  const _TxnRow(
      {required this.txn,
      required this.db,
      required this.l,
      required this.onEdit});

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
            '${txn.type == 'credit' ? t('credit', l) : t('payment', l)} '
            'of ${rupee(txn.amount)}'
            '${txn.desc.isNotEmpty ? ' (${txn.desc})' : ''}\n'
            '${DateFormat('d MMM yyyy').format(txn.date)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('cancel', l))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await db.deleteCustomerTxn(txn);
            },
            child: Text(t('delete', l), style: const TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.type == 'credit';
    final color    = isCredit ? kRed : kSecondary;

    return Dismissible(
      key: Key(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: kRed.withOpacity(0.1),
        child: const Icon(Icons.delete_outline, color: kRed),
      ),
      confirmDismiss: (_) async {
        _confirmDelete(context);
        return false;
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
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.desc.isEmpty
                        ? (isCredit ? t('credit', l) : t('payment', l))
                        : txn.desc,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    DateFormat('d MMM').format(txn.date),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            Text(
              '${isCredit ? '+' : '-'}${rupee(txn.amount)}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onEdit,
              child: const Icon(Icons.edit_outlined, size: 14, color: kMuted),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _confirmDelete(context),
              child: const Icon(Icons.delete_outline, size: 14, color: kRed),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────
class _ToggleBtn extends StatelessWidget {
  final String       label;
  final bool         active;
  final Color        activeColor;
  final VoidCallback onTap;
  const _ToggleBtn(
      {required this.label,
      required this.active,
      required this.activeColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? activeColor : const Color(0xFFE5E7EB)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
}

class _DateField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  const _DateField({required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(primary: kPrimary),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 18, color: kMuted),
            const SizedBox(width: 10),
            Text(
              DateFormat('d MMM yyyy').format(date),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: kMuted),
          ]),
        ),
      );
}

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
            child: const Center(
                child: Text('👥', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 18),
          Text(t('no_customers', l),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 17, color: kPrimary)),
          const SizedBox(height: 8),
          Text('Tap "${t('add_customer', l)}" to get started',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ]),
      );
}
