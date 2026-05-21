import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';

class EntryTab extends StatefulWidget {
  const EntryTab({super.key});
  @override
  State<EntryTab> createState() => _EntryTabState();
}

class _EntryTabState extends State<EntryTab> {
  final _db     = DbService();
  final _amount = TextEditingController();
  final _desc   = TextEditingController();
  final _bill   = TextEditingController();
  final _note   = TextEditingController();

  String   _type   = 'sale';
  DateTime _date   = DateTime.now();
  String   _shopId = '';
  bool     _saving = false;

  static const _typeOptions = [
    {'type': 'sale',    'label': 'Sales / Income', 'icon': '💚', 'color': kSecondary},
    {'type': 'expense', 'label': 'Expense',         'icon': '📉', 'color': kRed},
    {'type': 'payment', 'label': 'Payment',         'icon': '💳', 'color': kAmber},
  ];

  static const _saleCategories    = ['Cash', 'GPay', 'Credit', 'Wholesale', 'Retail'];
  static const _expenseCategories = ['Purchase', 'Rent', 'Labour', 'Transport', 'Misc'];
  static const _paymentCategories = ['Supplier', 'Loan', 'Staff', 'Utility'];

  List<String> get _categories {
    if (_type == 'sale')    return _saleCategories;
    if (_type == 'expense') return _expenseCategories;
    return _paymentCategories;
  }

  Map<String, dynamic> get _selectedTypeConfig =>
      _typeOptions.firstWhere((c) => c['type'] == _type,
          orElse: () => _typeOptions.first);

  Future<void> _save(AppProvider p) async {
    final raw = _amount.text.replaceAll(',', '').trim();
    final amt = double.tryParse(raw);
    if (amt == null || amt <= 0) {
      _snack('Enter a valid amount', error: true);
      return;
    }
    setState(() => _saving = true);

    final shopId = _shopId.isEmpty
        ? (p.shops.values.firstOrNull?.id ?? '')
        : _shopId;
    final shop = p.shops[shopId];

    final description = [
      if (_desc.text.trim().isNotEmpty) _desc.text.trim(),
      if (_bill.text.trim().isNotEmpty) 'Ref: ${_bill.text.trim()}',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ].join(' · ');

    try {
      await _db.addTxn(Txn(
        id:         const Uuid().v4(),
        businessId: p.businessId,
        shop:       shop?.id   ?? '',
        shopName:   shop?.name ?? '',
        date:       _date,
        type:       _type,
        amount:     amt,
        desc:       description,
      ));
      _snack('Entry saved ✅');
      _reset(p);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset(AppProvider p) {
    setState(() {
      _amount.clear();
      _desc.clear();
      _bill.clear();
      _note.clear();
      _type   = 'sale';
      _date   = DateTime.now();
      _shopId = p.shops.values.firstOrNull?.id ?? '';
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? kRed : kSecondary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    if (_shopId.isEmpty && p.shops.isNotEmpty) {
      _shopId = p.shops.values.first.id;
    }

    final typeColor = _selectedTypeConfig['color'] as Color;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Section title ──────────────────────────────────────────────────
          Text(
            '✏️ ${t("add_transaction", l).toUpperCase()}',
            style: const TextStyle(
              color: kPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),

          // ── DATE + SHOP row ────────────────────────────────────────────────
          Row(children: [
            // Date picker
            Expanded(
              child: _LabelField(
                label: 'DATE',
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme:
                              const ColorScheme.light(primary: kPrimary),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null && mounted) {
                      setState(() => _date = picked);
                    }
                  },
                  child: _DropdownBox(
                    child: Text(
                      DateFormat('dd/MM/yyyy').format(_date),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Shop selector
            Expanded(
              child: _LabelField(
                label: 'SHOP',
                child: p.shops.isEmpty
                    ? _DropdownBox(
                        child: Text(
                          'No shops',
                          style: TextStyle(color: kMuted, fontSize: 13),
                        ),
                      )
                    : _DropdownBox(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _shopId.isEmpty ? null : _shopId,
                            isExpanded: true,
                            isDense: true,
                            onChanged: (v) =>
                                setState(() => _shopId = v ?? ''),
                            items: p.shops.values
                                .map((s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(
                                        '${s.icon} ${s.name}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // ── TYPE + AMOUNT row ──────────────────────────────────────────────
          Row(children: [
            // Type dropdown
            Expanded(
              child: _LabelField(
                label: 'TYPE',
                child: _DropdownBox(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _type,
                      isExpanded: true,
                      isDense: true,
                      onChanged: (v) => setState(() => _type = v ?? 'sale'),
                      items: _typeOptions
                          .map((c) => DropdownMenuItem<String>(
                                value: c['type'] as String,
                                child: Row(children: [
                                  Text(
                                    c['icon'] as String,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      c['label'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: c['color'] as Color,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ]),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Amount field
            Expanded(
              child: _LabelField(
                label: 'AMOUNT (₹)',
                child: TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: typeColor,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                        fontSize: 16, color: Colors.grey.shade300),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: typeColor, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // ── Quick select categories ────────────────────────────────────────
          Text(
            'QUICK SELECT ${_type == "sale" ? "INCOME" : _type.toUpperCase()} TYPE',
            style: const TextStyle(
              color: kMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Custom chip (outlined dashed-style)
              GestureDetector(
                onTap: () {
                  _desc.clear();
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFD1D5DB),
                    ),
                  ),
                  child: const Text(
                    '+ Custom',
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Category chips
              ..._categories.map((cat) {
                final isSelected = _desc.text == cat;
                return GestureDetector(
                  onTap: () => setState(() => _desc.text = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? typeColor.withOpacity(0.1)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? typeColor
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color: isSelected ? typeColor : kText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),

          const SizedBox(height: 14),

          // ── Description ────────────────────────────────────────────────────
          const Text(
            'DESCRIPTION',
            style: TextStyle(
              color: kMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _desc,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'What is this entry?',
              isDense: true,
            ),
          ),

          const SizedBox(height: 14),

          // ── BILL/REF + NOTE row ────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: _LabelField(
                label: 'BILL / REF NO',
                child: TextFormField(
                  controller: _bill,
                  decoration: const InputDecoration(
                    hintText: 'Optional',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabelField(
                label: 'NOTE',
                child: TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(
                    hintText: 'Optional',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 22),

          // ── Add Entry button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : () => _save(p),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('+ Add Entry'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    _bill.dispose();
    _note.dispose();
    super.dispose();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _LabelField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: kMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class _DropdownBox extends StatelessWidget {
  final Widget child;
  const _DropdownBox({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: kCardShadow,
        ),
        child: Row(children: [
          Expanded(child: child),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: kMuted),
        ]),
      );
}
