import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _db     = DbService();
  final _amount = TextEditingController();
  final _desc   = TextEditingController();

  String   _type   = 'sale';
  DateTime _date   = DateTime.now();
  String   _shopId = '';
  bool     _saving = false;

  static const _typeConfig = [
    {
      'type':  'sale',
      'label': 'Sale',
      'icon':  '📈',
      'color': kSecondary,
      'hint':  'e.g. Cash sales, GPay, Wholesale',
    },
    {
      'type':  'expense',
      'label': 'Expense',
      'icon':  '📉',
      'color': kRed,
      'hint':  'e.g. Purchase, Rent, Labour',
    },
    {
      'type':  'payment',
      'label': 'Payment',
      'icon':  '💳',
      'color': kAmber,
      'hint':  'e.g. Supplier payment',
    },
  ];

  Map<String, dynamic> get _current =>
      _typeConfig.firstWhere((c) => c['type'] == _type);

  Future<void> _save() async {
    final raw = _amount.text.replaceAll(',', '').trim();
    final amt = double.tryParse(raw);
    if (amt == null || amt <= 0) {
      _showSnack('Enter a valid amount', error: true);
      return;
    }
    setState(() => _saving = true);

    final p    = context.read<AppProvider>();
    final shop = _shopId.isEmpty
        ? p.shops.values.firstOrNull
        : p.shops[_shopId];

    try {
      await _db.addTxn(Txn(
        id:         const Uuid().v4(),
        businessId: p.businessId,
        shop:       shop?.id   ?? '',
        shopName:   shop?.name ?? '',
        date:       _date,
        type:       _type,
        amount:     amt,
        desc:       _desc.text.trim(),
      ));
      if (mounted) {
        _showSnack('Entry saved successfully');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _showSnack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? kRed : kSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p      = context.watch<AppProvider>();
    final l      = p.lang;
    final color  = _current['color'] as Color;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('add_entry', l)),
        flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: kGradient)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Type selector ───────────────────────────────────────────────
          Row(
            children: _typeConfig.map((cfg) {
              final active = _type == cfg['type'];
              final c      = cfg['color'] as Color;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _type = cfg['type'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: active ? c : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? c : const Color(0xFFE5E7EB),
                        width: active ? 2 : 1,
                      ),
                      boxShadow: active ? [
                        BoxShadow(
                          color: c.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ] : kCardShadow,
                    ),
                    child: Column(children: [
                      Text(cfg['icon'] as String,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 5),
                      Text(
                        cfg['label'] as String,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.grey.shade600,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // ── Amount ──────────────────────────────────────────────────────
          Text(t('amount', l),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: kPrimary, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: color),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w800, color: color),
              hintText: '0',
              hintStyle: TextStyle(fontSize: 32, color: Colors.grey.shade300),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Description ─────────────────────────────────────────────────
          Text(t('description', l),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: kPrimary, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _desc,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: _current['hint'] as String,
            ),
          ),
          const SizedBox(height: 20),

          // ── Shop selector (only if >1 shop) ─────────────────────────────
          if (p.shops.length > 1) ...[
            Text(t('select_shop', l),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: kPrimary, fontSize: 13)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _shopId.isEmpty ? null : _shopId,
              decoration: InputDecoration(
                hintText: t('select_shop', l),
                prefixIcon: const Icon(Icons.store_outlined),
              ),
              items: p.shops.values
                  .map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.icon} ${s.name}'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _shopId = v ?? ''),
            ),
            const SizedBox(height: 20),
          ],

          // ── Date ─────────────────────────────────────────────────────────
          Text(t('date', l),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: kPrimary, fontSize: 13)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.light(primary: kPrimary),
                  ),
                  child: child!,
                ),
              );
              if (picked != null && mounted) {
                setState(() => _date = picked);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: kCardShadow,
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: kPrimary),
                const SizedBox(width: 10),
                Text(
                  DateFormat('dd MMMM yyyy').format(_date),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14, color: kText),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: kMuted),
              ]),
            ),
          ),
          const SizedBox(height: 36),

          // ── Save button ──────────────────────────────────────────────────
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            child: _saving
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(t('save', l)),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }
}
