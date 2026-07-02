import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';

/// Opens the "quick expense from a shared GPay/PhonePe receipt" sheet.
/// [imagePath] = a shared receipt screenshot (OCR'd for amount/payee when a
/// Gemini key is set). [sharedText] = shared plain text (amount parsed by regex).
Future<void> showQuickExpenseFromShare(BuildContext context,
    {String? imagePath, String? sharedText}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _QuickExpenseSheet(imagePath: imagePath, sharedText: sharedText),
  );
}

class _QuickExpenseSheet extends StatefulWidget {
  final String? imagePath;
  final String? sharedText;
  const _QuickExpenseSheet({this.imagePath, this.sharedText});
  @override
  State<_QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

class _QuickExpenseSheetState extends State<_QuickExpenseSheet> {
  final _amt  = TextEditingController();
  final _desc = TextEditingController();
  String? _shopId;
  bool _reading = false;   // OCR in progress
  bool _saving  = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // Prefill from shared text immediately (cheap regex).
    if (widget.sharedText != null && widget.sharedText!.trim().isNotEmpty) {
      _parseText(widget.sharedText!);
    }
    // Then, if it's a receipt image, OCR it for amount + payee.
    if (widget.imagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ocrReceipt());
    }
  }

  @override
  void dispose() {
    _amt.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _parseText(String text) {
    // ₹500 / Rs.500 / INR 500 / "500.00"
    final m = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*\.?[0-9]{0,2})',
            caseSensitive: false)
        .firstMatch(text);
    final n = m?.group(1)?.replaceAll(',', '');
    if (n != null && _amt.text.isEmpty) _amt.text = n;
    // "to <name>" / "paid to <name>"
    final p = RegExp(r'(?:paid to|to)\s+([A-Za-z0-9 .&\-]{2,40})',
            caseSensitive: false)
        .firstMatch(text);
    if (p != null && _desc.text.isEmpty) _desc.text = p.group(1)!.trim();
  }

  Future<void> _ocrReceipt() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('slv_gemini_key') ?? '';
    final on  = prefs.getBool('slv_gemini_on') ?? true;
    if (key.isEmpty || !on) return; // no key → user types manually
    setState(() { _reading = true; _status = 'Reading receipt…'; });
    try {
      final bytes = await File(widget.imagePath!).readAsBytes();
      final b64   = base64Encode(bytes);
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$key');
      const prompt =
          'This is a UPI payment receipt screenshot (Google Pay / PhonePe / Paytm). '
          'Return STRICT JSON only, no prose: '
          '{"amount": <number paid, no symbol>, "payee": "<who was paid>"}. '
          'If unknown use null.';
      final resp = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                  {
                    'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
                  }
                ]
              }
            ]
          }));
      if (resp.statusCode == 200) {
        final txt = (jsonDecode(resp.body)['candidates']?[0]?['content']
                ?['parts']?[0]?['text'] as String?) ??
            '';
        final jsonStr = RegExp(r'\{[\s\S]*\}').firstMatch(txt)?.group(0);
        if (jsonStr != null) {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final amt = data['amount'];
          final payee = data['payee'];
          if (amt != null && _amt.text.isEmpty) {
            _amt.text = (amt is num) ? amt.toString() : amt.toString();
          }
          if (payee != null &&
              payee.toString().trim().isNotEmpty &&
              _desc.text.isEmpty) {
            _desc.text = payee.toString().trim();
          }
          _status = '✓ Read from receipt';
        } else {
          _status = 'Could not read — enter amount';
        }
      } else {
        _status = 'Could not read — enter amount';
      }
    } catch (_) {
      _status = 'Could not read — enter amount';
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    final p = context.read<AppProvider>();
    final amount = double.tryParse(_amt.text.trim().replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      setState(() => _status = 'Enter a valid amount');
      return;
    }
    final shops = p.shops;
    final shopId = _shopId ??
        (p.selectedShop.isNotEmpty ? p.selectedShop : (shops.keys.isNotEmpty ? shops.keys.first : ''));
    setState(() => _saving = true);
    final now = DateTime.now();
    final txn = Txn(
      id:         now.millisecondsSinceEpoch.toString(),
      businessId: p.businessId,
      shop:       shopId,
      shopName:   shops[shopId]?.name ?? '',
      date:       DateTime(now.year, now.month, now.day, now.hour, now.minute),
      type:       'expense',
      amount:     amount,
      desc:       _desc.text.trim().isEmpty ? 'UPI payment' : _desc.text.trim(),
      createdAt:  now,
    );
    try {
      await DbService().addTxn(txn);
      if (!mounted) return;
      p.addLocalTxn(txn);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Expense ${p.currency.symbol}${amount.toStringAsFixed(0)} saved'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (mounted) setState(() { _saving = false; _status = 'Save failed — try again'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final shops = p.shops;
    final shopId = _shopId ??
        (p.selectedShop.isNotEmpty ? p.selectedShop : (shops.keys.isNotEmpty ? shops.keys.first : null));
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4))),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(gradient: kGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Add expense from receipt',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
          ),
        ]),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            if (_reading) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
            if (_reading) const SizedBox(width: 8),
            Text(_status, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ],
        const SizedBox(height: 14),
        if (widget.imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(widget.imagePath!),
                height: 120, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _amt,
          autofocus: widget.imagePath == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '${p.currency.symbol} ',
            prefixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary),
            filled: true, fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          decoration: const InputDecoration(
            labelText: 'Paid to / note', filled: true, fillColor: Colors.white),
        ),
        const SizedBox(height: 12),
        if (shops.length > 1)
          DropdownButtonFormField<String>(
            value: shopId,
            decoration: const InputDecoration(labelText: 'Shop', filled: true, fillColor: Colors.white),
            items: shops.entries
                .map((e) => DropdownMenuItem(value: e.key,
                    child: Text('${e.value.icon} ${e.value.name}',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _shopId = v),
          ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Save Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
