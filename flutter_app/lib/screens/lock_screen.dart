import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/lock_service.dart';

class LockScreen extends StatefulWidget {
  /// Called after successful unlock. If null, Navigator.pop is used.
  final VoidCallback? onUnlocked;
  /// If true, user is setting a new PIN (confirm flow)
  final bool settingPin;

  const LockScreen({super.key, this.onUnlocked, this.settingPin = false});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _svc     = LockService();
  String _pin    = '';
  String _confirm = '';
  bool   _confirming = false;
  String _error  = '';
  bool   _biometricAvail = false;
  bool   _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final avail   = await _svc.isBiometricAvailable();
    final enabled = await _svc.isBiometricEnabled();
    if (mounted) setState(() { _biometricAvail = avail; _biometricEnabled = enabled; });
    if (!widget.settingPin && avail && enabled) {
      await Future.delayed(const Duration(milliseconds: 300));
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final ok = await _svc.authenticateBiometric();
    if (ok && mounted) _unlock();
  }

  void _onKey(String digit) {
    if (_pin.length >= 4) return;
    setState(() { _pin += digit; _error = ''; });
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 100), _submit);
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (widget.settingPin) {
      if (!_confirming) {
        setState(() { _confirming = true; _confirm = _pin; _pin = ''; });
      } else {
        if (_pin == _confirm) {
          await _svc.enablePin(_pin);
          if (mounted) _unlock();
        } else {
          setState(() { _pin = ''; _confirming = false; _confirm = ''; _error = 'PINs do not match. Try again.'; });
        }
      }
      return;
    }
    final ok = await _svc.verifyPin(_pin);
    if (ok) {
      _unlock();
    } else {
      HapticFeedback.heavyImpact();
      setState(() { _pin = ''; _error = 'Wrong PIN. Try again.'; });
    }
  }

  void _unlock() {
    _svc.updateLastActive();
    if (widget.onUnlocked != null) {
      widget.onUnlocked!();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.settingPin
        ? (_confirming ? 'Confirm PIN' : 'Set New PIN')
        : 'Enter PIN';
    final subtitle = widget.settingPin
        ? (_confirming ? 'Enter PIN again to confirm' : 'Choose a 4-digit PIN')
        : 'Enter your 4-digit PIN to unlock';

    return Scaffold(
      backgroundColor: const Color(0xFF065F46),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 48),
          const Icon(Icons.lock_outline, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text('ArthaNote', style: const TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 12)),
          const SizedBox(height: 40),

          // PIN dots
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
            final filled = i < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? Colors.white : Colors.transparent,
                border: Border.all(color: Colors.white.withOpacity(0.6), width: 2),
              ),
            );
          })),

          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_error, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
          ],

          const Spacer(),

          // Keypad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(children: [
              _KeyRow(['1', '2', '3']),
              const SizedBox(height: 16),
              _KeyRow(['4', '5', '6']),
              const SizedBox(height: 16),
              _KeyRow(['7', '8', '9']),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                // Biometric button (only on unlock screen when available)
                SizedBox(
                  width: 72, height: 72,
                  child: (!widget.settingPin && _biometricAvail && _biometricEnabled)
                      ? _KeyButton(
                          child: const Icon(Icons.fingerprint, color: Colors.white, size: 28),
                          onTap: _tryBiometric,
                        )
                      : const SizedBox(),
                ),
                _KeyButton(
                  child: const Text('0', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                  onTap: () => _onKey('0'),
                ),
                _KeyButton(
                  child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 22),
                  onTap: _onBackspace,
                ),
              ]),
              const SizedBox(height: 32),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _KeyRow(List<String> digits) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: digits.map((d) => _KeyButton(
      child: Text(d, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
      onTap: () => _onKey(d),
    )).toList(),
  );
}

class _KeyButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _KeyButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.12),
      ),
      child: Center(child: child),
    ),
  );
}
