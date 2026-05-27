import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockService {
  static const _pinKey        = 'kp_pin_hash';
  static const _enabledKey    = 'kp_lock_enabled';
  static const _biometricKey  = 'kp_biometric_enabled';
  static const _autoLockKey   = 'kp_autolock_minutes';
  static const _lastActiveKey = 'kp_last_active_ts';

  final _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<bool> isBiometricAvailable() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
  }

  Future<void> enablePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, _hash(pin));
    await prefs.setBool(_enabledKey, true);
    await updateLastActive();
  }

  Future<void> disableLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.remove(_pinKey);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinKey);
    return stored != null && stored == _hash(pin);
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock ArthaNote',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> isLocked() async {
    if (!await isEnabled()) return false;
    final prefs       = await SharedPreferences.getInstance();
    final lastActive  = prefs.getInt(_lastActiveKey) ?? 0;
    final autoLockMin = prefs.getInt(_autoLockKey) ?? 5;
    final elapsed     = DateTime.now().millisecondsSinceEpoch - lastActive;
    return elapsed > autoLockMin * 60 * 1000;
  }

  Future<void> updateLastActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastActiveKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<int> getAutoLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoLockKey) ?? 5;
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoLockKey, minutes);
  }

  String _hash(String pin) {
    var h = 5381;
    for (final c in pin.runes) {
      h = ((h << 5) + h + c) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}
