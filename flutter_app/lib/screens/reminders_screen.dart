import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/currency.dart';
import '../models/payment_reminder.dart';
import '../services/reminder_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _svc = ReminderService();
  List<PaymentReminder> _reminders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _svc.getActive();
    if (mounted) setState(() => _reminders = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Payment Reminders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF111827))),
        elevation: 0,
      ),
      body: _reminders.isEmpty
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.notifications_none, size: 56, color: Color(0xFFD1D5DB)),
              SizedBox(height: 12),
              Text('No reminders yet', style: TextStyle(color: Color(0xFF9CA3AF))),
              SizedBox(height: 6),
              Text('Add entries like "gold loan" or "credit card"\nto get smart reminders.',
                  style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 12), textAlign: TextAlign.center),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reminders.length,
              itemBuilder: (ctx, i) => _ReminderCard(
                reminder: _reminders[i],
                svc: _svc,
                onChanged: _load,
              ),
            ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final PaymentReminder  reminder;
  final ReminderService  svc;
  final VoidCallback     onChanged;
  const _ReminderCard({required this.reminder, required this.svc, required this.onChanged});

  Color get _urgencyColor {
    final d = reminder.daysUntilDue;
    if (d == 0) return const Color(0xFFEF4444);
    if (d <= 3) return const Color(0xFFF97316);
    return const Color(0xFF065F46);
  }

  @override
  Widget build(BuildContext context) {
    final r     = reminder;
    final days  = r.daysUntilDue;
    final label = days == 0 ? 'Due TODAY' : days == 1 ? 'Due tomorrow' : 'Due in $days days';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: days <= 3 ? Border.all(color: _urgencyColor.withOpacity(0.3)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            // Left: icon + name
            Expanded(child: Row(children: [
              Text(reminderTypeLabel(r.type).split(' ').first,
                  style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Text('Every ${r.dueDay}${_ordinal(r.dueDay)} of the month',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ])),
            ])),
            // Right: amount + urgency
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${Currency.active.symbol}${r.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _urgencyColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _urgencyColor)),
              ),
            ]),
          ]),
        ),
        // Action row
        if (!r.isPaidThisMonth)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              // Mark Paid
              Expanded(child: ElevatedButton.icon(
                onPressed: () async {
                  await svc.markPaid(r.id, null);
                  onChanged();
                },
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Mark Paid', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF065F46),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              )),
              const SizedBox(width: 8),
              // WhatsApp share
              OutlinedButton(
                onPressed: () => svc.shareWhatsApp(r),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: const Text('📱', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              // Delete
              OutlinedButton(
                onPressed: () async {
                  await svc.delete(r.id);
                  onChanged();
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF9CA3AF)),
              ),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 16, color: Color(0xFF059669)),
              const SizedBox(width: 6),
              Text('Paid this month${r.lastPaidAt != null ? " · ${DateFormat("d MMM").format(r.lastPaidAt!)}" : ""}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st'; case 2: return 'nd'; case 3: return 'rd'; default: return 'th';
    }
  }
}
