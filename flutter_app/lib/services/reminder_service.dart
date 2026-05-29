import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/payment_reminder.dart';

// ── Keyword detection patterns ─────────────────────────────────────────────

const _kPatterns = <String, List<String>>{
  'credit_card': ['credit card', 'cc payment', 'sbi card', 'hdfc card',
                  'icici card', 'axis card', 'credit bill', 'கிரெடிட்'],
  'gold_loan':   ['gold loan', 'manappuram', 'muthoot', 'நகை கடன்',
                  'தங்க கடன்', 'jewel loan', 'gold interest', 'நகை வட்டி'],
  'loan':        ['emi', 'loan', 'கடன்', 'கடன் தவணை', 'installment',
                  'bank loan', 'home loan', 'vehicle loan', 'bike loan'],
  'rent':        ['rent', 'வாடகை', 'kiraya', 'house rent', 'shop rent'],
  'chit':        ['chit', 'சீட்டு', 'chitty', 'chit fund'],
};

const _kTypeLabels = <String, String>{
  'credit_card': '💳 Credit Card',
  'gold_loan':   '🏆 Gold Loan',
  'loan':        '🏦 Loan / EMI',
  'rent':        '🏠 Rent',
  'chit':        '💰 Chit Fund',
  'other':       '📋 Payment',
};

String reminderTypeLabel(String type) => _kTypeLabels[type] ?? '📋 Payment';

// ── Detected result ────────────────────────────────────────────────────────

class DetectedReminder {
  final String type;
  final String suggestedName;
  final double amount;
  DetectedReminder({required this.type, required this.suggestedName, required this.amount});
}

// ── ReminderService ────────────────────────────────────────────────────────

class ReminderService {
  static const _remindersKey = 'kp_reminders';
  static const _seenCountKey = 'kp_reminder_seen_';   // + type key

  final _notif = FlutterLocalNotificationsPlugin();
  bool _notifReady = false;

  // ── Init ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings();
    await _notif.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotifResponse,
    );
    _notifReady = true;
  }

  void _onNotifResponse(NotificationResponse r) {
    // payload format: "markpaid:<reminderId>"
    final payload = r.payload ?? '';
    if (payload.startsWith('markpaid:')) {
      final id = payload.substring(9);
      markPaid(id, null);
    }
  }

  Future<bool> requestPermission() async {
    final android = _notif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  // ── CRUD ─────────────────────────────────────────────────────────────

  Future<List<PaymentReminder>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_remindersKey);
    if (raw == null) return [];
    final list  = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => PaymentReminder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PaymentReminder>> getActive() async {
    final all = await getAll();
    return all.where((r) => r.isActive).toList()
      ..sort((a, b) => a.daysUntilDue.compareTo(b.daysUntilDue));
  }

  Future<void> _saveAll(List<PaymentReminder> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _remindersKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<PaymentReminder> add(PaymentReminder r) async {
    final list = await getAll();
    list.add(r);
    await _saveAll(list);
    await _scheduleNotification(r);
    return r;
  }

  Future<void> update(PaymentReminder r) async {
    final list = await getAll();
    final idx  = list.indexWhere((e) => e.id == r.id);
    if (idx >= 0) { list[idx] = r; await _saveAll(list); }
    await _cancelNotification(r.id);
    if (r.isActive) await _scheduleNotification(r);
  }

  Future<void> delete(String id) async {
    final list = await getAll();
    list.removeWhere((r) => r.id == id);
    await _saveAll(list);
    await _cancelNotification(id);
  }

  Future<void> markPaid(String id, double? amount) async {
    final list = await getAll();
    final idx  = list.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final r = list[idx];
    r.lastPaidAt = DateTime.now();
    if (amount != null) {
      r.amount = amount;
      r.amountHistory.add(amount);
      if (r.amountHistory.length > 6) r.amountHistory.removeAt(0);
    }
    list[idx] = r;
    await _saveAll(list);
  }

  // ── Pattern detection (L1 + L2) ───────────────────────────────────────

  /// Returns detected type and suggested name, or null if no keyword matched.
  DetectedReminder? detect(String description, double amount) {
    final desc = description.toLowerCase();
    for (final entry in _kPatterns.entries) {
      for (final kw in entry.value) {
        if (desc.contains(kw)) {
          return DetectedReminder(
            type:          entry.key,
            suggestedName: _suggestName(desc, entry.key),
            amount:        amount,
          );
        }
      }
    }
    return null;
  }

  String _suggestName(String desc, String type) {
    // Try to pull bank name from description
    const banks = ['sbi', 'hdfc', 'icici', 'axis', 'kotak', 'idbi', 'bob',
                   'manappuram', 'muthoot'];
    for (final b in banks) {
      if (desc.contains(b)) {
        return '${b[0].toUpperCase()}${b.substring(1)} ${_kTypeLabels[type]?.split(' ').last ?? ''}';
      }
    }
    return _kTypeLabels[type] ?? 'Payment';
  }

  /// Returns how many times this type has been seen (for L2 threshold).
  Future<int> getSeenCount(String type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_seenCountKey$type') ?? 0;
  }

  Future<void> incrementSeenCount(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('$_seenCountKey$type') ?? 0;
    await prefs.setInt('$_seenCountKey$type', count + 1);
  }

  /// Check if a similar reminder already exists.
  Future<PaymentReminder?> findSimilar(String type) async {
    final all = await getActive();
    return all.cast<PaymentReminder?>().firstWhere(
      (r) => r?.type == type, orElse: () => null);
  }

  // ── Auto-mark paid (L4) ───────────────────────────────────────────────

  /// Called after every expense entry save. If amount matches ±30%, marks paid.
  Future<PaymentReminder?> tryAutoMark(String description, double amount) async {
    final detected = detect(description, amount);
    if (detected == null) return null;
    final existing = await findSimilar(detected.type);
    if (existing == null) return null;
    if (existing.isPaidThisMonth) return null;
    final avg   = existing.averageAmount > 0 ? existing.averageAmount : existing.amount;
    final diff  = avg > 0 ? (amount - avg).abs() / avg : 1.0;
    if (diff <= 0.30) {
      await markPaid(existing.id, amount);
      return existing;
    }
    return null;
  }

  // ── Notifications (L3) ───────────────────────────────────────────────

  Future<void> _scheduleNotification(PaymentReminder r) async {
    if (!_notifReady) return;
    final now  = DateTime.now();
    // Schedule at 9 AM on (dueDay - 3) and on dueDay itself
    for (final dayOffset in [3, 0]) {
      var target = DateTime(now.year, now.month, r.dueDay, 9, 0)
          .subtract(Duration(days: dayOffset));
      if (target.isBefore(now)) {
        target = DateTime(now.year, now.month + 1, r.dueDay, 9, 0)
            .subtract(Duration(days: dayOffset));
      }
      final notifId = _notifId(r.id, dayOffset);
      final title   = dayOffset == 0
          ? '${reminderTypeLabel(r.type)} due today!'
          : '${reminderTypeLabel(r.type)} due in $dayOffset days';
      final body = '₹${r.amount.toStringAsFixed(0)} — ${r.name}';

      await _notif.zonedSchedule(
        notifId,
        title,
        body,
        tz.TZDateTime.from(target, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'payment_reminders', 'Payment Reminders',
            channelDescription: 'Alerts for upcoming loan and credit card payments',
            importance: Importance.high,
            priority: Priority.high,
            actions: [
              const AndroidNotificationAction('mark_paid', '✓ Mark Paid'),
              const AndroidNotificationAction('snooze', '⏰ Tomorrow'),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexact,
        payload: 'markpaid:${r.id}',
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
    }
  }

  Future<void> _cancelNotification(String reminderId) async {
    await _notif.cancel(_notifId(reminderId, 0));
    await _notif.cancel(_notifId(reminderId, 3));
  }

  int _notifId(String id, int offset) {
    var h = id.hashCode ^ (offset * 31);
    return h.abs() % 100000;
  }

  // ── WhatsApp Share (L5) ──────────────────────────────────────────────

  Future<void> shareWhatsApp(PaymentReminder r) async {
    final days = r.daysUntilDue;
    final due  = days == 0
        ? 'today'
        : days == 1 ? 'tomorrow' : 'in $days days (${r.dueDay}${_ordinal(r.dueDay)})';
    final text = Uri.encodeComponent(
      '🔔 Payment Reminder\n\n'
      '${reminderTypeLabel(r.type)}: ${r.name}\n'
      'Amount: ₹${r.amount.toStringAsFixed(0)}\n'
      'Due: $due\n\n'
      '— Sent from ArthaNote',
    );
    final uri = Uri.parse('https://wa.me/?text=$text');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
}
