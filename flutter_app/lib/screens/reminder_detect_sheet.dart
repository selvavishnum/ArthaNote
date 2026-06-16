import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/currency.dart';
import '../models/payment_reminder.dart';
import '../services/reminder_service.dart';

class ReminderDetectSheet extends StatefulWidget {
  final String  detectedType;
  final String  suggestedName;
  final double  amount;
  final void Function(PaymentReminder) onSaved;

  const ReminderDetectSheet({
    super.key,
    required this.detectedType,
    required this.suggestedName,
    required this.amount,
    required this.onSaved,
  });

  @override
  State<ReminderDetectSheet> createState() => _ReminderDetectSheetState();
}

class _ReminderDetectSheetState extends State<ReminderDetectSheet> {
  final _svc  = ReminderService();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  int    _dueDay  = 5;
  bool   _saving  = false;

  static const _quickDays = [1, 5, 10, 15, 20, 25];

  @override
  void initState() {
    super.initState();
    _name   = TextEditingController(text: widget.suggestedName);
    _amount = TextEditingController(
        text: widget.amount > 0 ? widget.amount.toStringAsFixed(0) : '');
  }

  @override
  void dispose() { _name.dispose(); _amount.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final r = PaymentReminder(
      id:        const Uuid().v4(),
      name:      _name.text.trim().isEmpty ? widget.suggestedName : _name.text.trim(),
      type:      widget.detectedType,
      amount:    double.tryParse(_amount.text) ?? widget.amount,
      dueDay:    _dueDay,
      createdAt: DateTime.now(),
    );
    await _svc.add(r);
    widget.onSaved(r);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = reminderTypeLabel(widget.detectedType);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),

        // Header
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
            child: Text(typeLabel, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Set monthly reminder?', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
        const SizedBox(height: 16),

        // Name field
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: widget.suggestedName,
            filled: true, fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),

        // Amount field
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Amount (${Currency.active.symbol})',
            prefixText: '${Currency.active.symbol} ',
            filled: true, fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),

        // Due day chips
        const Text('Due date every month', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ..._quickDays.map((d) => _DayChip(
            day: d, selected: _dueDay == d,
            onTap: () => setState(() => _dueDay = d),
          )),
          _DayChip(
            day: _dueDay,
            label: _quickDays.contains(_dueDay) ? 'Other' : '${_dueDay}th',
            selected: !_quickDays.contains(_dueDay),
            onTap: () async {
              final picked = await _pickDay(context);
              if (picked != null) setState(() => _dueDay = picked);
            },
          ),
        ]),
        const SizedBox(height: 20),

        // Save button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF065F46),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('✓ Yes, remind me every month', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Future<int?> _pickDay(BuildContext context) async {
    int? result;
    await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick due date', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 280,
          height: 200,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: 28,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () { result = i + 1; Navigator.pop(ctx); },
              child: Container(
                decoration: BoxDecoration(
                  color: _dueDay == i + 1 ? const Color(0xFF065F46) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(child: Text('${i + 1}', style: TextStyle(
                    fontSize: 12,
                    color: _dueDay == i + 1 ? Colors.white : const Color(0xFF374151)))),
              ),
            ),
          ),
        ),
      ),
    );
    return result;
  }
}

class _DayChip extends StatelessWidget {
  final int    day;
  final String? label;
  final bool   selected;
  final VoidCallback onTap;
  const _DayChip({required this.day, this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF065F46) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label ?? '${day}th', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF6B7280))),
    ),
  );
}
