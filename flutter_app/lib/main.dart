import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'providers/app_provider.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
