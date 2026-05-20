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
        final suppliers = snap.data ?? [];

        return Scaffold(
          backgroundColor: kBg,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddSheet(context, p, db),
            backgroundColor: kPrimary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(t('add_supplier', l), style: const TextStyle(color: Colors.white)),
          ),
          body: suppliers.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🤝', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(t('no_suppliers', l), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kPrimary)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                  itemCount: suppliers.length,
                  itemBuilder: (_, i) => _supplierCard(context, suppliers[i], db, l),
                ),
        );
      },
    );
  }

  Widget _supplierCard(BuildContext context, Supplier s, DbService db, String l) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: kPrimary.withOpacity(0.1),
        child: Text(s.name[0].toUpperCase(), style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w800)),
      ),
      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: s.phone.isNotEmpty ? Text(s.phone, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)) : null,
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(rupee(s.balance), style: TextStyle(color: s.balance > 0 ? kRed : kSecondary, fontWeight: FontWeight.w800, fontSize: 15)),
        Text(s.balance > 0 ? t('due', l) : t('paid', l), style: TextStyle(color: s.balance > 0 ? kRed : kSecondary, fontSize: 10)),
      ]),
      onTap: () => _showPaymentSheet(context, s, db),
    ),
  );

  void _showAddSheet(BuildContext context, AppProvider p, DbService db) {
    final name  = TextEditingController();
    final phone = TextEditingController();
    final bal   = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Add Supplier', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: kPrimary)),
          const SizedBox(height: 16),
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Supplier Name', prefixIcon: Icon(Icons.store))),
          const SizedBox(height: 12),
          TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone))),
          const SizedBox(height: 12),
          TextFormField(controller: bal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening balance ₹ (amount you owe)', prefixIcon: Icon(Icons.account_balance_wallet))),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await db.addSupplier(Supplier(
                id: '', businessId: p.businessId,
                name: name.text.trim(), phone: phone.text.trim(),
                balance: double.tryParse(bal.text) ?? 0,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Supplier'),
          ),
        ]),
      ),
    );
  }

  void _showPaymentSheet(BuildContext context, Supplier s, DbService db) {
    final amt = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: kPrimary)),
          const SizedBox(height: 4),
          Text('Balance: ${rupee(s.balance)}', style: TextStyle(color: s.balance > 0 ? kRed : kSecondary)),
          const SizedBox(height: 16),
          TextFormField(controller: amt, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Payment amount ₹', prefixIcon: Icon(Icons.payments))),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              final a = double.tryParse(amt.text);
              if (a == null) return;
              await db.updateSupplierBalance(s.id, -a);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Record Payment'),
          ),
        ]),
      ),
    );
  }
}
