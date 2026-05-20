import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});
  @override State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _db     = DbService();
  final _amount = TextEditingController();
  final _desc   = TextEditingController();

  String _type = 'sale';
  DateTime _date = DateTime.now();
  String _shopId = '';
  bool _saving   = false;

  String get lang => context.read<AppProvider>().lang;

  static const _types = [
    {'type': 'sale',    'label': 'Sale',    'icon': '📈', 'color': kSecondary},
    {'type': 'expense', 'label': 'Expense', 'icon': '📉', 'color': kRed},
    {'type': 'payment', 'label': 'Payment', 'icon': '💳', 'color': kAmber},
  ];

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.replaceAll(',', ''));
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid amount'), backgroundColor: kRed));
      return;
    }
    setState(() => _saving = true);
    final p = context.read<AppProvider>();
    final shop = _shopId.isEmpty ? p.shops.values.firstOrNull : p.shops[_shopId];
    try {
      await _db.addTxn(Txn(
        id: const Uuid().v4(),
        businessId: p.businessId,
        shop: shop?.id ?? '',
        shopName: shop?.name ?? '',
        date: _date,
        type: _type,
        amount: amt,
        desc: _desc.text.trim(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Entry saved!'), backgroundColor: kSecondary));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = lang;

    return Scaffold(
      appBar: AppBar(title: Text(t('add_entry', l))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Type selector
          Row(children: _types.map((tp) {
            final active = _type == tp['type'];
            final color  = tp['color'] as Color;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _type = tp['type'] as String),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: active ? color : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: active ? color : Colors.grey.shade200, width: active ? 2 : 1),
                  ),
                  child: Column(children: [
                    Text(tp['icon'] as String, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(tp['label'] as String, style: TextStyle(color: active ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 24),

          // Amount
          Text(t('amount', l), style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kPrimary),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              prefixStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kPrimary),
              hintText: '0',
              hintStyle: TextStyle(fontSize: 28, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),

          // Description
          Text(t('description', l), style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _desc,
            decoration: InputDecoration(hintText: _type == 'sale' ? 'e.g. Cash sales, GPay, Wholesale' : _type == 'expense' ? 'e.g. Purchase, Rent, Labour' : 'e.g. Supplier payment'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),

          // Shop selector
          if (p.shops.length > 1) ...[
            Text(t('select_shop', l), style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _shopId.isEmpty ? null : _shopId,
              decoration: const InputDecoration(hintText: 'Select shop'),
              items: p.shops.values.map((s) => DropdownMenuItem(value: s.id, child: Text('${s.icon} ${s.name}'))).toList(),
              onChanged: (v) => setState(() => _shopId = v ?? ''),
            ),
            const SizedBox(height: 20),
          ],

          // Date
          Text(t('date', l), style: const TextStyle(fontWeight: FontWeight.w700, color: kPrimary)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: _date,
                  firstDate: DateTime(2020), lastDate: DateTime.now());
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300)),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 18, color: kPrimary),
                const SizedBox(width: 10),
                Text('${_date.day}/${_date.month}/${_date.year}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ]),
            ),
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(t('save', l)),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() { _amount.dispose(); _desc.dispose(); super.dispose(); }
}
