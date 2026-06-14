import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'providers/app_provider.dart';
import 'screens/splash_screen.dart';
import 'services/reminder_service.dart';

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

  // Init reminder notifications
  await ReminderService().init();
  await ReminderService().requestPermission();

  // Enable Firestore offline persistence with unlimited cache
  // This makes all reads instant on re-open — no network round-trip needed
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes:     Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const ArthaNote(),
    ),
  );
}

class ArthaNote extends StatelessWidget {
  const ArthaNote({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ArthaNote',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: const SplashScreen(),
  );
}
