import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../l10n.dart';
import 'onboarding_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _auth   = AuthService();
  final _email  = TextEditingController();
  final _pass   = TextEditingController();
  final _name   = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;

  late final AnimationController _logoCtrl;
  late final Animation<double>   _logoAnim;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _logoAnim = CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut);
    _logoCtrl.forward();
  }

  String get _lang => context.read<AppProvider>().lang;

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: kRed,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: kSecondary,
      ),
    );
  }

  Future<void> _navigateAfterLogin(String uid) async {
    final provider = context.read<AppProvider>();
    // If this device was used as a guest, move that local data into the
    // account (and end the guest session) before loading the account.
    await provider.migrateGuestToAccount(uid);
    await provider.init(uid);
    if (!mounted) return;
    if (provider.isOnboarded) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  Future<void> _continueAsGuest() async {
    final provider = context.read<AppProvider>();
    await provider.enableGuestMode();
    await provider.initGuest();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => provider.isOnboarded
            ? const HomeScreen()
            : const OnboardingScreen(),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showErr('Enter your email address first.');
      return;
    }
    try {
      await _auth.sendPasswordReset(email);
      _showSuccess('Password reset email sent to $email');
    } catch (e) {
      _showErr(_friendlyError(e.toString()));
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        final cred = await _auth.signInEmail(
          _email.text.trim(), _pass.text);
        await _navigateAfterLogin(cred.user!.uid);
      } else {
        final cred = await _auth.registerEmail(
          _email.text.trim(), _pass.text);
        await _auth.saveProfile(cred.user!.uid, {
          'uid':        cred.user!.uid,
          'email':      _email.text.trim(),
          'name':       _name.text.trim(),
          'businessId': cred.user!.uid,
          'role':       'owner',
          'onboarded':  false,
        });
        await _navigateAfterLogin(cred.user!.uid);
      }
    } catch (e) {
      _showErr(_friendlyError(e.toString()));
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      final cred = await _auth.signInGoogle();
      if (cred == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final user = cred.user!;
      final existing = await _auth.getProfile(user.uid);
      if (existing == null) {
        await _auth.saveProfile(user.uid, {
          'uid':        user.uid,
          'email':      user.email ?? '',
          'name':       user.displayName ?? '',
          'businessId': user.uid,
          'role':       'owner',
          'onboarded':  false,
        });
      }
      await _navigateAfterLogin(user.uid);
    } catch (e) {
      _showErr(_friendlyError(e.toString()));
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('user-not-found'))      return 'No account found for this email.';
    if (raw.contains('wrong-password'))      return 'Incorrect password. Please try again.';
    if (raw.contains('invalid-email'))       return 'Please enter a valid email address.';
    if (raw.contains('email-already-in-use'))return 'This email is already registered. Please login.';
    if (raw.contains('weak-password'))       return 'Password must be at least 6 characters.';
    if (raw.contains('network-request-failed')) return 'Network error. Check your connection.';
    if (raw.contains('too-many-requests'))   return 'Too many attempts. Please wait and try again.';
    return raw.replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final l = _lang;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // ── Logo ─────────────────────────────────────────────────────
                Center(
                  child: ScaleTransition(
                    scale: _logoAnim,
                    child: Container(
                      width: 92, height: 92,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: kGradient,
                        boxShadow: kBoxShadow,
                      ),
                      child: const Center(
                        child: Text(
                          'AN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Georgia',
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  t('app_name', l),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t('tagline', l),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 36),

                // ── Tab switcher ─────────────────────────────────────────────
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    _tab(t('login', l),    _isLogin,  () => setState(() => _isLogin = true)),
                    _tab(t('register', l), !_isLogin, () => setState(() => _isLogin = false)),
                  ]),
                ),
                const SizedBox(height: 28),

                // ── Fields ───────────────────────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _isLogin ? const SizedBox.shrink() : Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: t('name', l),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (v) => !_isLogin && (v?.trim().isEmpty ?? true)
                            ? 'Please enter your name' : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: t('email', l),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Please enter your email' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: t('password', l),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v?.isEmpty ?? true)
                      ? 'Please enter your password' : null,
                ),
                const SizedBox(height: 28),

                // ── Primary action ───────────────────────────────────────────
                if (_loading)
                  const Center(
                    child: SizedBox(
                      width: 32, height: 32,
                      child: CircularProgressIndicator(
                        color: kPrimary, strokeWidth: 2.5),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                    child: Text(
                      _isLogin ? t('login', l) : t('register', l)),
                  ),
                if (_isLogin && !_loading)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: kPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // ── OR divider ───────────────────────────────────────────────
                Row(children: [
                  Expanded(child: Divider(color: Colors.grey.shade200)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('OR',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      )),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade200)),
                ]),
                const SizedBox(height: 20),

                // ── Google button ────────────────────────────────────────────
                OutlinedButton(
                  onPressed: _loading ? null : _google,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    backgroundColor: Colors.white,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Coloured G
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                          children: [
                            TextSpan(text: 'G', style: TextStyle(color: Color(0xFF4285F4))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        t('google_login', l),
                        style: const TextStyle(
                          color: kText,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Use the app without an account (guest mode). Data stays on the
                // device until the user logs in to back it up.
                TextButton(
                  onPressed: _loading ? null : _continueAsGuest,
                  child: Text(
                    'Skip — continue without login →',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [
            BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
          ] : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.grey.shade500,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    _logoCtrl.dispose();
    super.dispose();
  }
}
