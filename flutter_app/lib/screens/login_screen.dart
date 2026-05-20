import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../l10n.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth   = AuthService();
  final _email  = TextEditingController();
  final _pass   = TextEditingController();
  final _name   = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;

  String get lang => context.read<AppProvider>().lang;

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: kRed));
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      _showErr('Please fill all fields'); return;
    }
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await _auth.signInEmail(_email.text.trim(), _pass.text);
      } else {
        final cred = await _auth.registerEmail(_email.text.trim(), _pass.text);
        await _auth.saveProfile(cred.user!.uid, {
          'uid': cred.user!.uid,
          'email': _email.text.trim(),
          'name': _name.text.trim(),
          'businessId': cred.user!.uid,
          'role': 'owner',
        });
      }
    } catch (e) {
      _showErr(e.toString().replaceAll('Exception: ', ''));
    } finally {
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
          'uid': user.uid,
          'email': user.email ?? '',
          'name': user.displayName ?? '',
          'businessId': user.uid,
          'role': 'owner',
        });
      }
    } catch (e) {
      _showErr(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = lang;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 32),
            Container(
              width: 90, height: 90,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [kSecondary, kPrimary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Text('AN', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, fontFamily: 'Georgia')),
              ),
            ),
            const SizedBox(height: 16),
            Text(t('app_name', l), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kPrimary)),
            Text(t('tagline', l), style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            const SizedBox(height: 40),
            Row(children: [
              _tab(t('login', l), _isLogin, () => setState(() => _isLogin = true)),
              const SizedBox(width: 12),
              _tab(t('register', l), !_isLogin, () => setState(() => _isLogin = false)),
            ]),
            const SizedBox(height: 24),
            if (!_isLogin) ...[
              TextFormField(controller: _name, decoration: InputDecoration(labelText: t('name', l), prefixIcon: const Icon(Icons.person_outline))),
              const SizedBox(height: 14),
            ],
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t('email', l), prefixIcon: const Icon(Icons.email_outlined))),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pass, obscureText: _obscure,
              decoration: InputDecoration(
                labelText: t('password', l),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
            ),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator(color: kPrimary)
                : ElevatedButton(onPressed: _submit, child: Text(_isLogin ? t('login', l) : t('register', l))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: TextStyle(color: Colors.grey.shade500))),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ]),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loading ? null : _google,
              icon: const Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
              label: Text(t('google_login', l)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? kPrimary : Colors.grey.shade300),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: active ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.w700)),
      ),
    ),
  );

  @override
  void dispose() { _email.dispose(); _pass.dispose(); _name.dispose(); super.dispose(); }
}
