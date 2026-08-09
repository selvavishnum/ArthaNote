import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'navigation.dart';
import 'providers/app_provider.dart';
import 'screens/splash_screen.dart';
import 'services/reminder_service.dart';
import 'services/billing_service.dart';

Future<void> storeCrashLog(String error) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final logs  = prefs.getStringList('kp_crash_log') ?? [];
    logs.insert(0, '${DateTime.now().toIso8601String()}: $error');
    if (logs.length > 20) logs.removeRange(20, logs.length);
    await prefs.setStringList('kp_crash_log', logs);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Edge-to-edge: transparent bars, let Android 15 handle insets natively
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Catch Flutter framework errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    storeCrashLog(details.exceptionAsString());
  };
  // Catch async / platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    storeCrashLog('$error\n${stack.toString().split('\n').take(8).join('\n')}');
    return false;
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable Firestore offline persistence with unlimited cache. Must happen
  // before ANY other Firestore operation — Firestore throws if .settings is
  // assigned after the first read/write — which is why this now sits above
  // ReminderService's fire-and-forget calls below (they do Firestore reads
  // of their own for streak/attendance detection, and being unawaited,
  // relying on their async timing to stay "naturally" after this line would
  // be a fragile assumption rather than a guarantee).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes:     Settings.CACHE_SIZE_UNLIMITED,
  );

  // Init reminder notifications
  await ReminderService().init();
  await ReminderService().requestPermission();
  // Daily nudge to record entries (replaces the dashboard "no entries"
  // banner) — personalizes timing/text from the retailer's own streak and
  // recent activity, which now involves a Firestore read, so this and the
  // attendance reminder below are fire-and-forget rather than awaited, to
  // keep first paint fast regardless of query latency.
  ReminderService().scheduleDailyEntryReminder();
  // Daily nudge at the staff's usual check-in time, with a QR-scan action —
  // no-ops silently until there's enough attendance history to detect a
  // usual time.
  ReminderService().scheduleAttendanceReminder();

  final appProvider = AppProvider();
  // Fire-and-forget: Billing availability check + product query shouldn't
  // block first paint. The purchase stream listener is what matters being
  // attached early (it can fire for a purchase made before this launch,
  // e.g. resumed after the app was killed mid-flow).
  BillingService().init(onGranted: appProvider.refreshProfile);

  runApp(
    ChangeNotifierProvider.value(
      value: appProvider,
      child: const ArthaNote(),
    ),
  );
}

class ArthaNote extends StatelessWidget {
  const ArthaNote({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'ArthaNote',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: const SplashScreen(),
  );
}
