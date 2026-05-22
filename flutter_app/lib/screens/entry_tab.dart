import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/pattern_service.dart';

class EntryTab extends StatefulWidget {
  const EntryTab({super.key});
  @override
  State<EntryTab> createState() => _EntryTabState();
}

class _EntryTabState extends State<EntryTab> {
  final _db     = DbService();
  final _ai     = PatternService();
  final _amount = TextEditingController();
  final _desc   = TextEditingController();
  final _bill   = TextEditingController();
  final _note   = TextEditingController();

  String        _type       = 'sale';
  DateTime      _date       = DateTime.now();
  String        _shopId     = '';
  bool          _saving     = false;
  AiPrediction  _prediction = AiPrediction.empty();
  Timer?        _debounce;

  @override
  void initState() {
    super.initState();
    _desc.addListener(_onDescChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPatterns());
  }

  Future<void> _loadPatterns() async {
    final p    = context.read<AppProvider>();
    final txns = await _db.loadLocalCache(p.businessId);
    _ai.learnFromTxns(txns);
  }

  void _onDescChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final pred = _ai.predict(_desc.text);
      setState(() {
        _prediction = pred;
        // Auto-switch type when strongly predicted (≥70 % confidence, ≥2 past entries)
        if (pred.isStrong) _type = pred.type;
      });
    });
  }

  static const _typeOptions = [
    {'type': 'sale',    'label': 'Sales / Income', 'icon': '💚', 'color': kSecondary},
    {'type': 'expense', 'label': 'Expense',         'icon': '📉', 'color': kRed},
    {'type': 'payment', 'label': 'Payment',         'icon': '💳', 'color': kAmber},
  ];

  static const _paymentCategories = ['Supplier', 'Loan', 'Staff', 'Utility'];

  List<String> _getCategories(AppProvider p) {
    if (_type == 'sale')    return p.salesCats(_shopId);
    if (_type == 'expense') return p.expenseCats(_shopId);
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

    // Capture values BEFORE reset
    final savedType   = _type;
    final savedShopId = shopId;
    final savedDesc   = _desc.text.trim();

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
      _snack('Entry saved');
      // Teach the AI about this entry before resetting
      _ai.learn(description, savedType, savedDesc);
      _reset(p);

      // Track custom categories
      if (savedDesc.isNotEmpty && savedType != 'payment') {
        final defaultCats = savedType == 'sale'
            ? p.salesCats(savedShopId)
            : p.expenseCats(savedShopId);
        if (!defaultCats.contains(savedDesc)) {
          final prefs2 = await SharedPreferences.getInstance();
          final key = 'kp_custom_${savedShopId}_$savedType';
          final existing = prefs2.getStringList(key) ?? [];
          if (!existing.contains(savedDesc)) {
            await prefs2.setStringList(key, [...existing, savedDesc]);
          }
        }
      }
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
      // Keep _type, _date, _shopId so the next entry pre-fills with last-used values.
      // User can still change them if needed.
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

          Text(
            '${t("add_transaction", l).toUpperCase()}',
            style: const TextStyle(
              color: kPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),

          // Type selector — 3 tap cards (no Expanded inside DropdownMenuItem)
          Row(
            children: _typeOptions.map((cfg) {
              final active = _type == cfg['type'];
              final c      = cfg['color'] as Color;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = cfg['type'] as String;
                    _desc.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: active ? c.withOpacity(0.12) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active ? c : const Color(0xFFE5E7EB),
                        width: active ? 2 : 1,
                      ),
                      boxShadow: kCardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cfg['icon'] as String,
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(
                          (cfg['label'] as String).split('/').first.trim(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: active ? c : kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // DATE + SHOP row
          Row(children: [
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
                  child: _FieldBox(
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 14, color: kPrimary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          DateFormat('dd/MM/yyyy').format(_date),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down,
                          size: 18, color: kMuted),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabelField(
                label: 'SHOP',
                child: p.shops.isEmpty
                    ? _FieldBox(
                        child: Text(
                          'No shops',
                          style: TextStyle(color: kMuted, fontSize: 13),
                        ),
                      )
                    : _FieldBox(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _shopId.isEmpty ? null : _shopId,
                            isExpanded: true,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down,
                                size: 18, color: kMuted),
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

          // AMOUNT
          _LabelField(
            label: 'AMOUNT (${t("amount", l).split(" ").last})',
            child: TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: typeColor,
              ),
              decoration: InputDecoration(
                hintText: '0',
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: typeColor),
                hintStyle: TextStyle(
                    fontSize: 22, color: Colors.grey.shade300),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: typeColor, width: 2),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Quick categories
          const Text(
            'QUICK SELECT',
            style: TextStyle(
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
              GestureDetector(
                onTap: () { _desc.clear(); setState(() {}); },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD1D5DB)),
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
              ..._getCategories(p).map((cat) {
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

          // AI suggestion banner
          if (_prediction.isGood) ...[
            const SizedBox(height: 10),
            _AiSuggestionBanner(
              prediction: _prediction,
              currentType: _type,
              onApplyType: () => setState(() => _type = _prediction.type),
              onApplyCategory: _prediction.category.isNotEmpty
                  ? () => setState(() => _desc.text = _prediction.category)
                  : null,
            ),
          ],

          const SizedBox(height: 14),

          // Description
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

          // BILL/REF + NOTE
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
                  : Text('+ ${t("add_entry", l)}'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _desc.removeListener(_onDescChanged);
    _amount.dispose();
    _desc.dispose();
    _bill.dispose();
    _note.dispose();
    super.dispose();
  }
}

// ── AI Suggestion Banner ───────────────────────────────────────────────────

class _AiSuggestionBanner extends StatelessWidget {
  final AiPrediction prediction;
  final String       currentType;
  final VoidCallback onApplyType;
  final VoidCallback? onApplyCategory;

  const _AiSuggestionBanner({
    required this.prediction,
    required this.currentType,
    required this.onApplyType,
    this.onApplyCategory,
  });

  static const _typeLabel = {'sale': 'Sale', 'expense': 'Expense', 'payment': 'Payment'};
  static const _typeColor = {
    'sale':    Color(0xFF059669),
    'expense': Color(0xFFDC2626),
    'payment': Color(0xFFD97706),
  };

  @override
  Widget build(BuildContext context) {
    final typeLabel = _typeLabel[prediction.type] ?? prediction.type;
    final typeColor = _typeColor[prediction.type] ?? kPrimary;
    final alreadyApplied = currentType == prediction.type;
    final pct = (prediction.confidence * 100).round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: typeColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Text('🤖', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: kText),
                children: [
                  TextSpan(
                    text: '$typeLabel',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: typeColor,
                    ),
                  ),
                  if (prediction.category.isNotEmpty &&
                      prediction.category != prediction.type) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: prediction.category,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                  TextSpan(
                    text: '  $pct% · ${prediction.count}× past entries',
                    style: const TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!alreadyApplied)
            GestureDetector(
              onTap: onApplyType,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Apply',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            Icon(Icons.check_circle, size: 16, color: typeColor),
        ],
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

class _LabelField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                color: kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class _FieldBox extends StatelessWidget {
  final Widget child;
  const _FieldBox({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: kCardShadow,
        ),
        child: child,
      );
}
