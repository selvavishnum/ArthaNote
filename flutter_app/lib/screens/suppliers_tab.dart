import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/supplier.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

class SuppliersTab extends StatelessWidget {
  const SuppliersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final p  = context.watch<AppProvider>();
    final l  = p.lang;
    final db = DbService();

    return StreamBuilder<List<Supplier>>(
      stream: db.supplierStream(p.businessId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kPrimary));
        }

        final suppliers = snap.data ?? [];

        return Stack(children: [
          suppliers.isEmpty
              ? _EmptySuppliers(l: l)
              : _SupplierList(suppliers: suppliers, db: db, l: l),

          // FAB: Add Supplier
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'suppliers_fab_add',
              onPressed: () => _showAddSheet(context, p, db),
              backgroundColor: kPrimary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                t('add_supplier', l),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]);
      },
    );
  }

  void _showAddSheet(BuildContext context, AppProvider p, DbService db) {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final balCtrl   = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),

            // Header
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  shape: BoxShape.circle),
                child: const Icon(Icons.store_outlined, color: kPrimary, size: 20),
              ),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening Balance ₹ (amount you owe)',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setModalState(() => saving = true);
                      await db.addSupplier(Supplier(
                        id:         '',
                        businessId: p.businessId,
                        name:       nameCtrl.text.trim(),
                        phone:      phoneCtrl.text.trim(),
                        balance:    double.tryParse(balCtrl.text) ?? 0,
                      ));
                      nameCtrl.dispose();
                      phoneCtrl.dispose();
                      balCtrl.dispose();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
              child: saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Save Supplier'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptySuppliers extends StatelessWidget {
  final String l;
  const _EmptySuppliers({required this.l});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🤝', style: TextStyle(fontSize: 36)),
        ),
      ),
      const SizedBox(height: 18),
      Text(t('no_suppliers', l),
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 17, color: kPrimary)),
      const SizedBox(height: 8),
      Text('Add your first supplier to track dues',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ]),
  );
}

// ── Supplier list ─────────────────────────────────────────────────────────────
class _SupplierList extends StatelessWidget {
  final List<Supplier> suppliers;
  final DbService      db;
  final String         l;
  const _SupplierList({
    required this.suppliers,
    required this.db,
    required this.l,
  });

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
    itemCount: suppliers.length,
    itemBuilder: (_, i) => _SupplierCard(
      supplier: suppliers[i],
      db: db,
      l: l,
    ),
  );
}

// ── Supplier card ─────────────────────────────────────────────────────────────
class _SupplierCard extends StatelessWidget {
  final Supplier  supplier;
  final DbService db;
  final String    l;
  const _SupplierCard({
    required this.supplier,
    required this.db,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final isDue   = supplier.balance > 0;
    final color   = isDue ? kRed : kSecondary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPaymentSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: kPrimary.withOpacity(0.1),
              child: Text(
                supplier.name[0].toUpperCase(),
                style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + phone
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(supplier.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if (supplier.phone.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(supplier.phone,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ],
              ),
            ),

            // Balance + Due/Paid label
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                rupee(supplier.balance),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isDue ? t('due', l) : t('paid', l),
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showPaymentSheet(BuildContext context) {
    final amtCtrl = TextEditingController();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),

            // Supplier info
            CircleAvatar(
              radius: 28,
              backgroundColor: kPrimary.withOpacity(0.1),
              child: Text(supplier.name[0].toUpperCase(),
                  style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22)),
            ),
            const SizedBox(height: 10),
            Text(supplier.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: kPrimary)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: (supplier.balance > 0 ? kRed : kSecondary)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Balance: ${rupee(supplier.balance)}',
                style: TextStyle(
                  color: supplier.balance > 0 ? kRed : kSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: amtCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary),
              decoration: const InputDecoration(
                labelText: 'Payment Amount ₹',
                prefixIcon: Icon(Icons.payments_outlined),
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final a = double.tryParse(amtCtrl.text.trim());
                      if (a == null || a <= 0) return;
                      setModalState(() => saving = true);
                      await db.updateSupplierBalance(supplier.id, -a);
                      amtCtrl.dispose();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
              child: saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Record Payment'),
            ),
          ]),
        ),
      ),
    );
  }
}
