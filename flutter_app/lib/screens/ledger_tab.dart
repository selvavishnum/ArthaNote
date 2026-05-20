import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import 'dashboard_tab.dart' show rupee;

class LedgerTab extends StatefulWidget {
  const LedgerTab({super.key});
  @override State<LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<LedgerTab> {
  final _db = DbService();
  String _filterType = 'all';
  final _search = TextEditingController();

  static const _typeFilters = [
    {'key': 'all',     'label': 'All'},
    {'key': 'sale',    'label': 'Sales'},
    {'key': 'expense', 'label': 'Expenses'},
    {'key': 'payment', 'label': 'Payments'},
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    return Column(children: [
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextFormField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search entries...',
            prefixIcon: const Icon(Icons.search, color: kPrimary),
            suffixIcon: _search.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); setState(() {}); })
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
      // Type filter
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
          children: _typeFilters.map((f) {
            final active = _filterType == f['key'];
            return GestureDetector(
              onTap: () => setState(() => _filterType = f['key']!),
              child: Container(
                margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? kPrimary : Colors.grey.shade200),
                ),
                child: Center(child: Text(f['label']!,
                  style: TextStyle(color: active ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 13))),
              ),
            );
          }).toList()),
      ),
      // Transactions list
      Expanded(
        child: StreamBuilder<List<Txn>>(
          stream: _db.txnStream(p.businessId),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: kPrimary));
            }
            var txns = snap.data ?? [];
            if (_filterType != 'all') txns = txns.where((t) => t.type == _filterType).toList();
            if (_search.text.isNotEmpty) {
              final q = _search.text.toLowerCase();
              txns = txns.where((t) => t.desc.toLowerCase().contains(q) || t.shopName.toLowerCase().contains(q)).toList();
            }
            if (txns.isEmpty) return Center(child: Text(t('no_entries', l), style: TextStyle(color: Colors.grey.shade500)));

            // Group by date
            final groups = <String, List<Txn>>{};
            for (final txn in txns) {
              final key = DateFormat('dd MMM yyyy').format(txn.date);
              groups.putIfAbsent(key, () => []).add(txn);
            }
            final keys = groups.keys.toList();

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: keys.length,
              itemBuilder: (_, i) {
                final key = keys[i];
                final items = groups[key]!;
                final dayTotal = items.fold(0.0, (s, t) => t.type == 'sale' ? s + t.amount : t.type == 'expense' ? s - t.amount : s);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(key, style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary, fontSize: 13)),
                      Text(rupee(dayTotal), style: TextStyle(fontWeight: FontWeight.w700, color: dayTotal >= 0 ? kSecondary : kRed, fontSize: 13)),
                    ]),
                  ),
                  ...items.map((txn) => _tile(txn)),
                ]);
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _tile(Txn txn) {
    final isIncome = txn.type == 'sale' || txn.type == 'payment';
    final color    = isIncome ? kSecondary : kRed;
    final icon     = txn.type == 'sale' ? '📈' : txn.type == 'expense' ? '📉' : '💳';
    return Dismissible(
      key: Key(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: kRed.withOpacity(0.15),
        child: const Icon(Icons.delete_outline, color: kRed),
      ),
      confirmDismiss: (_) async => await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete entry?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kRed))),
          ],
        ),
      ),
      onDismissed: (_) => DbService().deleteTxn(txn.id),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: ListTile(
          leading: Text(icon, style: const TextStyle(fontSize: 22)),
          title: Text(txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis),
          subtitle: Text('${txn.shopName.isNotEmpty ? "${txn.shopName} · " : ""}${DateFormat('hh:mm a').format(txn.date)}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          trailing: Text('${isIncome ? "+" : "−"}${rupee(txn.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      ),
    );
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }
}
