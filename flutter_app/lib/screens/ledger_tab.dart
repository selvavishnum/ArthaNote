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
  @override
  State<LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<LedgerTab> {
  final _db     = DbService();
  final _search = TextEditingController();
  String _filter = 'all';

  static const _filters = [
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
      // ── Search bar ────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextFormField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: t('search_hint', l),
            prefixIcon: const Icon(Icons.search_outlined, color: kPrimary),
            suffixIcon: _search.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () { _search.clear(); setState(() {}); })
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ),

      // ── Type filter chips ─────────────────────────────────────────────────
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          children: _filters.map((f) {
            final active = _filter == f['key'];
            return GestureDetector(
              onTap: () => setState(() => _filter = f['key']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? kPrimary : const Color(0xFFE5E7EB)),
                ),
                child: Center(
                  child: Text(
                    f['label']!,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),

      // ── Transaction list ──────────────────────────────────────────────────
      Expanded(
        child: StreamBuilder<List<Txn>>(
          stream: _db.txnStream(p.businessId),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: kPrimary));
            }

            var txns = snap.data ?? [];

            // Apply type filter
            if (_filter != 'all') {
              txns = txns.where((tx) => tx.type == _filter).toList();
            }

            // Apply search
            final q = _search.text.toLowerCase().trim();
            if (q.isNotEmpty) {
              txns = txns.where((tx) =>
                  tx.desc.toLowerCase().contains(q) ||
                  tx.shopName.toLowerCase().contains(q) ||
                  tx.type.contains(q)).toList();
            }

            if (txns.isEmpty) {
              return Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🔍', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    t('no_entries', l),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16, color: kPrimary)),
                ]),
              );
            }

            // Group by date
            final groups = <String, List<Txn>>{};
            for (final txn in txns) {
              final key = DateFormat('dd MMM yyyy').format(txn.date);
              groups.putIfAbsent(key, () => []).add(txn);
            }
            final keys = groups.keys.toList();

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: keys.length,
              itemBuilder: (_, i) {
                final key   = keys[i];
                final items = groups[key]!;
                final dayNet = items.fold(0.0, (s, tx) {
                  if (tx.type == 'sale') return s + tx.amount;
                  if (tx.type == 'expense') return s - tx.amount;
                  return s;
                });

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                              fontSize: 12,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: (dayNet >= 0 ? kSecondary : kRed)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${dayNet >= 0 ? "+" : ""}${rupee(dayNet)}',
                              style: TextStyle(
                                color: dayNet >= 0 ? kSecondary : kRed,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...items.map((txn) => _LedgerTile(txn: txn)),
                  ],
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

// ── Ledger tile with swipe-to-delete ─────────────────────────────────────────
class _LedgerTile extends StatelessWidget {
  final Txn txn;
  const _LedgerTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isIncome = txn.type == 'sale' || txn.type == 'payment';
    final color    = txn.type == 'expense' ? kRed : kSecondary;
    final icon     = txn.type == 'sale' ? '📈' : txn.type == 'expense' ? '📉' : '💳';

    return Dismissible(
      key: Key(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: kRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.delete_outline, color: kRed, size: 22),
          SizedBox(height: 2),
          Text('Delete', style: TextStyle(color: kRed, fontSize: 10, fontWeight: FontWeight.w600)),
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
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: kRed),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => DbService().deleteTxn(txn.id),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
          ),
          title: Text(
            txn.desc.isEmpty ? txn.type.toUpperCase() : txn.desc,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${txn.shopName.isNotEmpty ? "${txn.shopName} · " : ""}${DateFormat("hh:mm a").format(txn.date)}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
          trailing: Text(
            '${isIncome ? "+" : "−"}${rupee(txn.amount)}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
