import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PBKDF2-HMAC-SHA256 (single 32-byte derived key). Top-level so it can run
/// inside a background isolate via [compute] — 50k iterations would jank the
/// UI thread otherwise.
List<int> pbkdf2Sha256(Map<String, Object> args) {
  final password   = args['password'] as List<int>;
  final salt       = args['salt'] as List<int>;
  final iterations = args['iterations'] as int;
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return t;
}

class LockService {
  static const _pinKey        = 'kp_pin_hash';
  static const _enabledKey    = 'kp_lock_enabled';
  static const _biometricKey  = 'kp_biometric_enabled';
  static const _autoLockKey   = 'kp_autolock_minutes';
  static const _lastActiveKey = 'kp_last_active_ts';

  // Work factor for the PIN hash (equivalent intent to bcrypt cost ≥ 12 for
  // this on-device gate). Stored per-hash so it can be raised later without
  // breaking existing PINs.
  static const _iterations = 50000;

  final _auth = LocalAuthentication();
  static final _rng = Random.secure();

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
    await prefs.setString(_pinKey, await _hashV2(pin));
    await prefs.setBool(_enabledKey, true);
    await updateLastActive();
  }

  Future<void> disableLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.remove(_pinKey);
  }

  /// Verifies the PIN with a constant-time comparison.
  ///
  /// Storage format v2: `v2$<iterations>$<saltB64>$<hashB64>` — salted
  /// PBKDF2-HMAC-SHA256. Legacy hashes (unsalted 32-bit djb2 from older
  /// builds) are still accepted once and transparently RE-HASHED to v2 on
  /// the next successful unlock (migration-on-login).
  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pinKey);
    if (stored == null) return false;

    if (stored.startsWith('v2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;
      final iter = int.tryParse(parts[1]) ?? _iterations;
      final salt = base64Decode(parts[2]);
      final derived = await compute(pbkdf2Sha256, <String, Object>{
        'password': utf8.encode(pin),
        'salt': salt,
        'iterations': iter,
      });
      return _constTimeEquals(base64Encode(derived), parts[3]);
    }

    // Legacy djb2 hash — verify, then migrate to v2 immediately.
    final ok = _constTimeEquals(stored, _legacyHash(pin));
    if (ok) {
      await prefs.setString(_pinKey, await _hashV2(pin));
    }
    return ok;
  }

  Future<String> _hashV2(String pin) async {
    final salt = List<int>.generate(16, (_) => _rng.nextInt(256));
    final derived = await compute(pbkdf2Sha256, <String, Object>{
      'password': utf8.encode(pin),
      'salt': salt,
      'iterations': _iterations,
    });
    return 'v2\$$_iterations\$${base64Encode(salt)}\$${base64Encode(derived)}';
  }

  /// Constant-time string comparison — never early-exits on a mismatch, so
  /// timing can't leak how many leading characters matched.
  bool _constTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
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

  /// Old unsalted 32-bit djb2 hash — kept ONLY to verify pre-migration PINs.
  /// Never used for new storage.
  String _legacyHash(String pin) {
    var h = 5381;
    for (final c in pin.runes) {
      h = ((h << 5) + h + c) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}
