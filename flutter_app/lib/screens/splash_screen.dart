import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    _anim.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _goto(const LoginScreen());
      return;
    }
    final p = context.read<AppProvider>();
    await p.init(user.uid);
    if (!mounted) return;
    final profile = p.profile;
    if (profile.isEmpty || profile['onboarded'] != true) {
      _goto(const OnboardingScreen());
    } else {
      _goto(const HomeScreen());
    }
  }

  void _goto(Widget screen) => Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => screen,
      transitionDuration: const Duration(milliseconds: 400),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kPrimary,
    body: Center(
      child: ScaleTransition(
        scale: _scale,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white30, width: 2),
            ),
            child: const Center(
              child: Text('AN', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, fontFamily: 'Georgia')),
            ),
          ),
          const SizedBox(height: 20),
          const Text('ArthaNote', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, fontFamily: 'Georgia')),
          const SizedBox(height: 6),
          Text('Shop Ledger', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, fontWeight: FontWeight.w500)),
        ]),
      ),
    ),
  );

  @override
  void dispose() { _anim.dispose(); super.dispose(); }
}
