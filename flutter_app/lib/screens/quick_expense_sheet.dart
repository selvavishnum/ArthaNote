import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/receipt_ocr.dart';

/// Opens the "add expense from a shared receipt" sheet, pre-filled with
/// whatever the on-device OCR could read ([parsed]). Used as a review/edit
/// step (auto-save handles the confident case directly).
Future<void> showQuickExpenseFromShare(BuildContext context,
    {String? imagePath, ReceiptData? parsed}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickExpenseSheet(imagePath: imagePath, parsed: parsed),
  );
}

class _QuickExpenseSheet extends StatefulWidget {
  final String? imagePath;
  final ReceiptData? parsed;
  const _QuickExpenseSheet({this.imagePath, this.parsed});
  @override
  State<_QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

class _QuickExpenseSheetState extends State<_QuickExpenseSheet> {
  final _amt  = TextEditingController();
  final _desc = TextEditingController();
  String? _shopId;
  String? _txnId;
  DateTime? _date;
  bool _saving = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final d = widget.parsed;
    if (d != null) {
      if (d.amount != null) _amt.text = d.amount!.toStringAsFixed(d.amount! % 1 == 0 ? 0 : 2);
      if (d.payee != null)  _desc.text = d.payee!;
      _txnId = d.txnId;
      _date  = d.date;
      if (!d.hasAmount) _status = 'Couldn\'t read the amount — enter it below';
    }
  }

  @override
  void dispose() {
    _amt.dispose();
    _desc.dispose();
    super.dispose();
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
        (p.selectedShop.isNotEmpty ? p.selectedShop
                                   : (shops.keys.isNotEmpty ? shops.keys.first : ''));
    setState(() => _saving = true);
    final now = DateTime.now();
    final day = _date ?? now;
    final txn = Txn(
      id:         now.millisecondsSinceEpoch.toString(),
      businessId: p.businessId,
      shop:       shopId,
      shopName:   shops[shopId]?.name ?? '',
      date:       DateTime(day.year, day.month, day.day, now.hour, now.minute),
      type:       'expense',
      amount:     amount,
      desc:       _desc.text.trim().isEmpty ? 'UPI payment' : _desc.text.trim(),
      contact:    _txnId ?? '',
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
        (p.selectedShop.isNotEmpty ? p.selectedShop
                                   : (shops.keys.isNotEmpty ? shops.keys.first : null));
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
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(fontSize: 12, color: kMuted)),
        ],
        const SizedBox(height: 14),
        if (widget.imagePath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(widget.imagePath!),
                height: 110, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _amt,
          autofocus: widget.parsed?.hasAmount != true,
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
        if (_txnId != null && _txnId!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('UPI Ref: $_txnId', style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
        if (_date != null) ...[
          const SizedBox(height: 4),
          Text('Date: ${_date!.day}/${_date!.month}/${_date!.year}',
              style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
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
