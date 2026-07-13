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
///
/// When [editTxn] is given (the "Edit" action after an auto-save), the sheet
/// UPDATES that already-saved entry in place instead of inserting a new one.
Future<void> showQuickExpenseFromShare(BuildContext context,
    {String? imagePath, ReceiptData? parsed, Txn? editTxn}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickExpenseSheet(
        imagePath: imagePath, parsed: parsed, editTxn: editTxn),
  );
}

class _QuickExpenseSheet extends StatefulWidget {
  final String? imagePath;
  final ReceiptData? parsed;
  final Txn? editTxn;
  const _QuickExpenseSheet({this.imagePath, this.parsed, this.editTxn});
  @override
  State<_QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

class _QuickExpenseSheetState extends State<_QuickExpenseSheet> {
  final _amt  = TextEditingController();
  final _desc = TextEditingController();
  String? _shopId;
  String? _txnId;
  DateTime? _date;
  String _type = 'expense'; // 'expense' (paid) | 'sale' (received)
  bool _saving = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final e = widget.editTxn;
    if (e != null) {
      // Editing the entry auto-save just wrote — prefill from the saved
      // record itself, not the parse.
      _type = e.type;
      _amt.text = e.amount.toStringAsFixed(e.amount % 1 == 0 ? 0 : 2);
      _desc.text = e.desc;
      _shopId = e.shop.isEmpty ? null : e.shop;
      _txnId = e.contact.isEmpty ? null : e.contact;
      _date  = e.date;
      return;
    }
    final d = widget.parsed;
    if (d != null) {
      _type = d.txnType;
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
    final isIncome = _type == 'sale';
    final editing = widget.editTxn;
    // Edit mode reuses the saved entry's identity so we UPDATE it in place —
    // a fresh id here is what caused the double-save bug.
    final txn = Txn(
      id:         editing?.id ?? now.millisecondsSinceEpoch.toString(),
      businessId: editing?.businessId ?? p.businessId,
      shop:       shopId,
      shopName:   shops[shopId]?.name ?? editing?.shopName ?? '',
      date:       editing?.date ??
          DateTime(day.year, day.month, day.day, now.hour, now.minute),
      type:       _type,
      amount:     amount,
      desc:       _desc.text.trim().isEmpty
          ? (isIncome ? 'UPI received' : 'UPI payment')
          : _desc.text.trim(),
      contact:    _txnId ?? '',
      createdAt:  editing?.createdAt ?? now,
    );
    try {
      if (editing != null) {
        await DbService().updateTxn(txn);
        if (!mounted) return;
        p.updateLocalTxn(txn);
      } else {
        await DbService().addTxn(txn);
        if (!mounted) return;
        p.addLocalTxn(txn);
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${isIncome ? "Received" : "Expense"} ${p.currency.symbol}${amount.toStringAsFixed(0)} '
            '${editing != null ? "updated" : "saved"}'),
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
          Expanded(
            child: Text(
                widget.editTxn != null
                    ? 'Edit saved entry'
                    : 'Add entry from receipt',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
          ),
        ]),
        const SizedBox(height: 12),
        // Direction toggle — pre-set by OCR ("Paid to" → Paid, "From X" →
        // Received), user can flip if the receipt was read wrong.
        Row(children: [
          for (final opt in const [
            ('expense', '💸 Paid', kRed),
            ('sale', '💰 Received', kSecondary),
          ])
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _type = opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _type == opt.$1
                        ? opt.$3.withOpacity(0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _type == opt.$1 ? opt.$3 : const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    opt.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _type == opt.$1 ? opt.$3 : kMuted,
                    ),
                  ),
                ),
              ),
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
            // cacheHeight downsamples at decode time — the shared GPay/
            // PhonePe screenshot arrives full-resolution (often 1080×2400+),
            // and decoding it whole just for a 110dp-tall preview is what
            // trips Android's "BitmapFactory without downsampling" warning.
            child: Image.file(File(widget.imagePath!),
                height: 110, width: double.infinity, fit: BoxFit.cover,
                cacheHeight: 330,
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
          decoration: InputDecoration(
            labelText: _type == 'sale' ? 'Received from / note' : 'Paid to / note',
            filled: true,
            fillColor: Colors.white,
          ),
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
                : Text(
                    widget.editTxn != null
                        ? 'Update Entry'
                        : (_type == 'sale' ? 'Save Received' : 'Save Expense'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
