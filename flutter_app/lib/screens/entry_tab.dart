import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../models/payment_reminder.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/pattern_service.dart';
import '../services/reminder_service.dart';
import 'dashboard_tab.dart' show rupee;
import 'reminder_detect_sheet.dart';
import 'reminders_screen.dart';
import 'upgrade_screen.dart';

class EntryTab extends StatefulWidget {
  const EntryTab({super.key});
  @override
  State<EntryTab> createState() => _EntryTabState();
}

class _EntryTabState extends State<EntryTab> {
  final _db            = DbService();
  final _ai            = PatternService();
  final _reminderSvc   = ReminderService();
  final _amount  = TextEditingController();
  final _desc    = TextEditingController();
  final _bill    = TextEditingController();
  final _note    = TextEditingController();
  final _contact = TextEditingController();
  final _amountFocus = FocusNode(); // re-focused after save for fast entry

  String        _type       = 'sale';
  DateTime      _date       = DateTime.now();
  String        _shopId     = '';
  bool          _saving     = false;
  AiPrediction  _prediction = AiPrediction.empty();
  Timer?        _debounce;
  bool          _gstOn      = false;
  double        _gstRate    = 18.0;

  @override
  void initState() {
    super.initState();
    _desc.addListener(_onDescChanged);
    _amount.addListener(_onAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPatterns();
      _loadGstSettings();
    });
  }

  Future<void> _loadPatterns() async {
    final p    = context.read<AppProvider>();
    final txns = p.txns.isNotEmpty
        ? p.txns
        : await _db.loadLocalCache(p.businessId);
    _ai.learnFromTxns(txns);
  }

  Future<void> _loadGstSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _gstOn   = prefs.getBool('slv_gst')      ?? false;
        _gstRate = prefs.getDouble('slv_gstrate') ?? 18.0;
      });
    }
  }

  void _onAmountChanged() {
    if (_gstOn) setState(() {});
  }

  void _onDescChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final pred = _ai.predict(_desc.text);
      setState(() {
        _prediction = pred;
        // Do NOT auto-switch type — only show suggestion banner, user decides
      });
    });
  }

  // 'payment' removed from manual entry to keep the form simple — supplier
  // payments are recorded from the Suppliers tab; old payment entries still
  // display fine in ledger/reports.
  static const _typeOptions = [
    {'type': 'sale',    'label': 'Sales / Income', 'icon': '💚', 'color': kSecondary},
    {'type': 'expense', 'label': 'Expense',         'icon': '📉', 'color': kRed},
  ];

  bool _isPersonalShop(AppProvider p) =>
      (p.shops[_shopId]?.type ?? '') == 'personal';

  List<String> _getCategories(AppProvider p) {
    // Personal mode now also offers quick-select chips + Custom (same source
    // categories as business mode — Cash/GPay/Card/… plus any custom ones).
    if (_type == 'sale')     return p.salesCats(_shopId);
    if (_type == 'expense')  return p.expenseCats(_shopId);
    return p.paymentCats(_shopId);
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
        ? (p.visibleShops.values.firstOrNull?.id ?? '')
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
      final txn = Txn(
        id:         const Uuid().v4(),
        businessId: p.businessId,
        shop:       shop?.id   ?? '',
        shopName:   shop?.name ?? '',
        date:       _date,
        type:       _type,
        amount:     amt,
        desc:       description,
        contact:    _isPersonalShop(p) ? _contact.text.trim() : '',
        enteredBy:  FirebaseAuth.instance.currentUser?.email ?? '',
        createdAt:  DateTime.now(), // real entry time for the per-row stamp
      );
      // Update UI immediately before the Firestore write so addLocalTxn populates
      // _txns before _startLiveSync snapshot fires — prevents the duplicate where
      // the listener sees the doc before addLocalTxn and adds it a second time.
      if (mounted) context.read<AppProvider>().addLocalTxn(txn);
      // Guests have no auth → save to the on-device cache only (no Firestore).
      if (p.isGuest) {
        await _db.addTxnLocal(txn);
      } else {
        await _db.addTxn(txn);
      }
      _snack('Entry saved');
      // Fire-and-forget: logs this save's time (for the daily reminder's
      // personal-time detection) and refreshes today's streak in the
      // scheduled notification — never blocks the UI on it.
      _reminderSvc.recordEntrySaved();
      // Teach the AI about this entry before resetting
      _ai.learn(description, savedType, savedDesc);
      _reset(p);
      // Return the cursor to Amount so the next entry can be typed immediately.
      if (mounted) _amountFocus.requestFocus();

      // AI reminder detection for expense entries (all shop types)
      if (txn.type == 'expense') {
        _detectAndShowReminder(txn.desc, txn.amount);
      }

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

  Future<void> _detectAndShowReminder(String desc, double amount) async {
    final detected = _reminderSvc.detect(desc, amount);
    if (detected == null) return;

    // L4: Try auto-mark first (if a reminder already exists for this type)
    final autoMarked = await _reminderSvc.tryAutoMark(desc, amount);
    if (autoMarked != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ ${autoMarked.name} marked as paid'),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }

    // L2: Check seen count — if seen 2+ times, auto-create silently
    await _reminderSvc.incrementSeenCount(detected.type);
    final seenCount = await _reminderSvc.getSeenCount(detected.type);
    final existing  = await _reminderSvc.findSimilar(detected.type);
    if (existing != null) return; // already has reminder

    if (seenCount >= 2) {
      // Auto-create with default due day 5
      final r = PaymentReminder(
        id:        const Uuid().v4(),
        name:      detected.suggestedName,
        type:      detected.type,
        amount:    amount,
        dueDay:    5,
        createdAt: DateTime.now(),
      );
      await _reminderSvc.add(r);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🔔 Reminder set automatically for ${r.name}'),
          backgroundColor: const Color(0xFF065F46),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Edit',
            textColor: Colors.white,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RemindersScreen())),
          ),
        ));
      }
      return;
    }

    // L1: First time — show the one-tap sheet
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReminderDetectSheet(
        detectedType:  detected.type,
        suggestedName: detected.suggestedName,
        amount:        amount,
        onSaved: (r) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('🔔 Reminder set for ${r.name}'),
              backgroundColor: const Color(0xFF065F46),
            ));
          }
        },
      ),
    );
  }

  void _reset(AppProvider p) {
    setState(() {
      _amount.clear();
      _desc.clear();
      _bill.clear();
      _note.clear();
      _contact.clear();
      // Keep _type, _date, _shopId so the next entry pre-fills with last-used values.
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

    if (_shopId.isEmpty && p.visibleShops.isNotEmpty) {
      _shopId = p.visibleShops.values.first.id;
    }

    final isPersonalMode = _isPersonalShop(p);
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

          // Type selector
          if (isPersonalMode)
            Row(children: [
              for (final cfg in [
                {'type': 'sale',    'label': 'I Received', 'icon': '💰', 'color': kSecondary},
                {'type': 'expense', 'label': 'I Paid',     'icon': '💸', 'color': kRed},
              ]) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() { _type = cfg['type'] as String; _desc.clear(); }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _type == cfg['type']
                            ? (cfg['color'] as Color).withOpacity(0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _type == cfg['type']
                              ? cfg['color'] as Color
                              : const Color(0xFFE5E7EB),
                          width: _type == cfg['type'] ? 2 : 1,
                        ),
                        boxShadow: kCardShadow,
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(cfg['icon'] as String, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(
                          cfg['label'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _type == cfg['type'] ? cfg['color'] as Color : kMuted,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                if (cfg['type'] == 'sale') const SizedBox(width: 10),
              ],
            ])
          else
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
                      final now = DateTime.now();
                      setState(() => _date = DateTime(
                            picked.year, picked.month, picked.day,
                            now.hour, now.minute, now.second,
                          ));
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
                child: p.visibleShops.isEmpty
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
                            items: p.visibleShops.values
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
            label: 'AMOUNT (${p.currency.symbol})',
            child: TextFormField(
              controller: _amount,
              focusNode: _amountFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: typeColor,
              ),
              decoration: InputDecoration(
                hintText: '0',
                prefixText: '${p.currency.symbol} ',
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

          // GST Preview
          if (_gstOn) Builder(builder: (context) {
            final raw = _amount.text.replaceAll(',', '').trim();
            final amt = double.tryParse(raw) ?? 0;
            if (amt <= 0) return const SizedBox.shrink();
            final gstAmt  = amt * _gstRate / 100;
            final total   = amt + gstAmt;
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kSecondary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kSecondary.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.receipt_outlined, size: 14, color: kSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'GST (${_gstRate.toStringAsFixed(0)}%): ${rupee(gstAmt)}  |  Total: ${rupee(total)}',
                  style: const TextStyle(fontSize: 12, color: kSecondary, fontWeight: FontWeight.w600),
                )),
              ]),
            );
          }),

          // Contact name (personal mode only)
          if (isPersonalMode) ...[
            const SizedBox(height: 14),
            _LabelField(
              label: 'CONTACT NAME',
              child: TextFormField(
                controller: _contact,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Who is this with? (optional)',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Quick categories + Custom — shown in both business and personal
          // (I Received / I Paid) modes.
          ...[
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
                  onTap: () async {
                    // "+ Custom" is a Pro/trial feature. Free tier (after the
                    // trial) is sent to the paywall instead.
                    if (!p.canUseCustomEntry) {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              const UpgradeScreen(source: 'custom-entry')));
                      return;
                    }
                    final ctrl = TextEditingController();
                    final result = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Custom Description',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        content: TextField(
                          controller: ctrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Enter description...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                            child: const Text('Use', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (result != null && result.isNotEmpty) {
                      setState(() => _desc.text = result);
                      p.addCustomCategory(_shopId, _type, result);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: Text(
                      p.canUseCustomEntry ? '+ Custom' : '🔒 Custom',
                      style: const TextStyle(
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
          ],

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
    _amount.removeListener(_onAmountChanged);
    _amount.dispose();
    _desc.dispose();
    _bill.dispose();
    _note.dispose();
    _contact.dispose();
    _amountFocus.dispose();
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
