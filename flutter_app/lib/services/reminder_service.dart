import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/currency.dart';
import '../models/payment_reminder.dart';
import '../models/txn.dart';
import '../navigation.dart';
import '../screens/qr_scan_screen.dart';
import 'db_service.dart';

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

/// Consecutive-day entry streak + days since the most recent entry, used to
/// personalize the daily reminder's text (see ReminderService._dailyReminderText).
class _StreakInfo {
  final int streak;
  final int daysSinceLastEntry;
  const _StreakInfo(this.streak, this.daysSinceLastEntry);
}

/// Title/body pair for a scheduled notification.
class _ReminderText {
  final String title;
  final String body;
  const _ReminderText(this.title, this.body);
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
    final payload = r.payload ?? '';
    if (payload.startsWith('markpaid:')) {
      final id = payload.substring(9);
      // Dispatch on r.actionId, not just the payload — the payload alone
      // can't distinguish which of the two action buttons (or a plain tap
      // on the notification body) was pressed, since it's the same string
      // either way. This used to mean tapping "⏰ Tomorrow" (snooze) also
      // silently marked the reminder paid, same as "✓ Mark Paid" — fixed
      // here by branching on the actual action that fired.
      if (r.actionId == 'mark_paid') {
        _handleMarkPaidTapped(id);
      } else if (r.actionId == 'snooze') {
        _handleSnoozeTapped(id);
      }
      // A plain tap on the notification body (actionId == null) just opens
      // the app, with no reminder state change — the user may only want to
      // look, not confirm payment.
    } else if (payload == 'openqr:attendance') {
      _openQrScanner();
    }
  }

  Future<PaymentReminder?> _findReminder(String id) async {
    final list = await getAll();
    for (final r in list) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _handleMarkPaidTapped(String id) async {
    final r = await _findReminder(id);
    await markPaid(id, null);
    if (r != null) await _autoSaveReminderEntry(r);
  }

  Future<void> _handleSnoozeTapped(String id) async {
    final r = await _findReminder(id);
    if (r != null) await _scheduleSnoozeNotification(r);
  }

  /// Auto-creates a ledger entry for a reminder marked paid from a
  /// notification tap, so the retailer doesn't have to separately re-enter
  /// it by hand. Reads the businessId/shop cached by AppProvider (see
  /// app_provider.dart's _cacheIdentityForNotifications) since this runs
  /// with no BuildContext/live AppProvider — best-effort: if nothing is
  /// cached yet (e.g. before the app has ever fully loaded), it's skipped
  /// silently and the reminder is still correctly marked paid regardless.
  Future<void> _autoSaveReminderEntry(PaymentReminder r) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('kp_notif_business_id') ?? '';
      if (businessId.isEmpty) return;
      final shopId   = prefs.getString('kp_notif_shop_id')   ?? '';
      final shopName = prefs.getString('kp_notif_shop_name') ?? '';
      final txn = Txn(
        id:         const Uuid().v4(),
        businessId: businessId,
        shop:       shopId,
        shopName:   shopName,
        date:       DateTime.now(),
        type:       'expense',
        amount:     r.amount,
        desc:       '${reminderTypeLabel(r.type)} — ${r.name}',
        enteredBy:  'reminder_notification',
        createdAt:  DateTime.now(),
      );
      await DbService().addTxn(txn);
    } catch (_) {
      // Auto-save is a convenience on top of markPaid() — if it fails, the
      // reminder itself is still correctly marked paid; the retailer can
      // add the ledger entry by hand as before.
    }
  }

  Future<void> _openQrScanner() async {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
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
      final body = '${Currency.active.symbol}${r.amount.toStringAsFixed(0)} — ${r.name}';

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

  /// One-time follow-up fired when "⏰ Tomorrow" (snooze) is tapped — the
  /// regular day-3/day-0 alarms above are fixed to the due date and don't
  /// move, so snoozing needs its own separate, non-repeating notification
  /// rather than touching those.
  Future<void> _scheduleSnoozeNotification(PaymentReminder r) async {
    if (!_notifReady) return;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final target = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);
    final title = '${reminderTypeLabel(r.type)} — reminder snoozed';
    final body  = '${Currency.active.symbol}${r.amount.toStringAsFixed(0)} — ${r.name}';

    await _notif.zonedSchedule(
      _notifId(r.id, 999),
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
    );
  }

  /// Daily nudge to record the day's entries — replaces the old "no entries"
  /// dashboard banner with an app notification. Uses a fixed id so
  /// re-scheduling (on every app launch and after every entry save, via
  /// recordEntrySaved()) just overwrites the existing one rather than
  /// stacking duplicates.
  ///
  /// Time and text are personalized from the retailer's own history:
  /// - Fires at THEIR usual entry-saving hour (see _personalReminderHour),
  ///   not a fixed 8 PM for everyone.
  /// - Text escalates with days-of-silence, and celebrates an active streak
  ///   when there's nothing to escalate (see _dailyReminderText).
  /// Because this is a single repeating alarm (matchDateTimeComponents:
  /// DateTimeComponents.time), its title/body are fixed at schedule time —
  /// they don't recompute at the moment it actually fires. So the streak/
  /// silence text shown is accurate as of the last time this was called
  /// (app launch or an entry save), not perfectly live. That's an accepted
  /// tradeoff of staying 100% on-device with no server component.
  Future<void> scheduleDailyEntryReminder() async {
    if (!_notifReady) return;
    final hour = await _personalReminderHour();
    final streakInfo = await _fetchStreakInfo();
    final text = _dailyReminderText(streakInfo.streak, streakInfo.daysSinceLastEntry);

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, 0);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));
    await _notif.zonedSchedule(
      900001,
      text.title,
      text.body,
      tz.TZDateTime.from(target, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_entry', 'Daily Entry Reminder',
          channelDescription: 'Daily nudge to record the day\'s ledger entries',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static const _entryTimeLogKey = 'kp_entry_time_log';

  /// Records that an entry was just saved, and refreshes the scheduled
  /// daily reminder so its time/text reflect today's activity right away
  /// instead of only at the next app cold start. Call this from wherever a
  /// sale/expense/payment entry is actually saved (entry_tab.dart).
  Future<void> recordEntrySaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final log = prefs.getStringList(_entryTimeLogKey) ?? [];
      log.add(DateTime.now().toIso8601String());
      // Keep the last 20 saves — enough to detect a stable daily pattern
      // without the log growing without bound.
      final trimmed = log.length > 20 ? log.sublist(log.length - 20) : log;
      await prefs.setStringList(_entryTimeLogKey, trimmed);
    } catch (_) {}
    await scheduleDailyEntryReminder();
  }

  /// The retailer's usual entry-saving hour, as the most common hour-of-day
  /// across their last 20 saves (see recordEntrySaved). Falls back to 8 PM
  /// when there isn't enough history yet (fewer than 5 saves recorded).
  Future<int> _personalReminderHour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final log = prefs.getStringList(_entryTimeLogKey) ?? [];
      if (log.length < 5) return 20;
      final hourCounts = <int, int>{};
      for (final iso in log) {
        final dt = DateTime.tryParse(iso);
        if (dt == null) continue;
        hourCounts[dt.hour] = (hourCounts[dt.hour] ?? 0) + 1;
      }
      if (hourCounts.isEmpty) return 20;
      var bestHour = 20, bestCount = 0;
      hourCounts.forEach((hour, count) {
        if (count > bestCount) {
          bestHour = hour;
          bestCount = count;
        }
      });
      return bestHour;
    } catch (_) {
      return 20;
    }
  }

  /// Given the dates (any DateTime; only year/month/day matter) on which at
  /// least one entry was recorded, returns the current consecutive-day
  /// streak ending today — or yesterday, if today's entry hasn't been added
  /// yet, so the streak isn't considered "broken" until a full day passes
  /// with zero entries. Pure/static so the dashboard UI can reuse it
  /// directly against AppProvider's already-loaded txns, without a second
  /// Firestore read.
  static int computeStreak(Iterable<DateTime> entryDates) {
    final days = entryDates.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    if (days.isEmpty) return 0;
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    if (!days.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Streak + days-since-last-entry, computed via a direct Firestore query
  /// against the businessId cached by AppProvider (see
  /// app_provider.dart's _cacheIdentityForNotifications) — this runs with
  /// no BuildContext/live AppProvider, so it can't reuse the in-memory txns
  /// list the way the dashboard UI does. Best-effort: any failure (no
  /// cached businessId yet, offline with nothing in the Firestore cache,
  /// etc.) falls back to "no streak, escalate as if long-silent" so the
  /// daily reminder still fires with a sensible generic message rather
  /// than crashing or silently not scheduling at all.
  Future<_StreakInfo> _fetchStreakInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('kp_notif_business_id') ?? '';
      if (businessId.isEmpty) return const _StreakInfo(0, 999);
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: true)
          .limit(60)
          .get();
      final dates = snap.docs
          .map((d) {
            final raw = d.data()['date'];
            return raw is String ? DateTime.tryParse(raw) : null;
          })
          .whereType<DateTime>()
          .toList();
      if (dates.isEmpty) return const _StreakInfo(0, 999);
      final streak = computeStreak(dates);
      final lastEntry = dates.reduce((a, b) => a.isAfter(b) ? a : b);
      final today = DateTime.now();
      final daysSince = DateTime(today.year, today.month, today.day)
          .difference(DateTime(lastEntry.year, lastEntry.month, lastEntry.day))
          .inDays;
      return _StreakInfo(streak, daysSince);
    } catch (_) {
      return const _StreakInfo(0, 999);
    }
  }

  /// Picks the daily reminder's title/body from streak + days-of-silence —
  /// escalates once entries have actually been missed, and celebrates an
  /// active streak otherwise.
  _ReminderText _dailyReminderText(int streak, int daysSinceLastEntry) {
    if (daysSinceLastEntry >= 7) {
      return const _ReminderText(
        'நாங்க miss பண்றோம்! 🥺',
        'It\'s been a week — come back and catch up your ledger.',
      );
    }
    if (daysSinceLastEntry >= 3) {
      return _ReminderText(
        'Your ledger misses you 📒',
        'No entries in $daysSinceLastEntry days — a quick update keeps your records accurate.',
      );
    }
    if (daysSinceLastEntry >= 1) {
      return const _ReminderText(
        'Add today\'s entries 📒',
        'Keep your ledger up to date — record today\'s sales & expenses.',
      );
    }
    if (streak >= 2) {
      return _ReminderText(
        '🔥 $streak-day streak!',
        'Keep it going — add today\'s entries to make it ${streak + 1}.',
      );
    }
    return const _ReminderText(
      'Add today\'s entries 📒',
      'Keep your ledger up to date — record today\'s sales & expenses.',
    );
  }

  /// Detects the staff's usual daily attendance check-in time from the last
  /// 21 days of 'in'-type attendance records (see qr_scan_screen.dart),
  /// and schedules a daily notification at that time with a "📷 Scan QR"
  /// action that opens the QR scanner directly (see _openQrScanner). Needs
  /// at least 3 data points before trusting a "usual time" — skips
  /// scheduling entirely otherwise, rather than guessing off one noisy
  /// early sample.
  Future<void> scheduleAttendanceReminder() async {
    if (!_notifReady) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('kp_notif_business_id') ?? '';
      if (businessId.isEmpty) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 21));
      final snap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('type', isEqualTo: 'in')
          .orderBy('timeRaw', descending: true)
          .limit(60)
          .get();

      final minutesOfDay = <int>[];
      for (final doc in snap.docs) {
        final raw = doc.data()['timeRaw'];
        if (raw is! int) continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(raw);
        if (dt.isBefore(cutoff)) continue;
        minutesOfDay.add(dt.hour * 60 + dt.minute);
      }
      if (minutesOfDay.length < 3) return;

      minutesOfDay.sort();
      final medianMinutes = minutesOfDay[minutesOfDay.length ~/ 2];
      final hour   = medianMinutes ~/ 60;
      final minute = medianMinutes % 60;

      final now = DateTime.now();
      var target = DateTime(now.year, now.month, now.day, hour, minute);
      if (target.isBefore(now)) target = target.add(const Duration(days: 1));

      await _notif.zonedSchedule(
        900002,
        'Mark today\'s attendance 📷',
        'Your usual check-in time — tap to scan the QR code.',
        tz.TZDateTime.from(target, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'attendance_reminder', 'Attendance Reminder',
            channelDescription: 'Daily nudge at your usual staff check-in time',
            importance: Importance.high,
            priority: Priority.high,
            actions: [
              AndroidNotificationAction('scan_qr', '📷 Scan QR'),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexact,
        payload: 'openqr:attendance',
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      // Not enough data, offline, or the query failed — skip silently.
      // Best-effort, matching this service's fail-safe pattern elsewhere:
      // never let a notification-scheduling problem disrupt app startup.
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
      'Amount: ${Currency.active.symbol}${r.amount.toStringAsFixed(0)}\n'
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
