import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';

class AppProvider extends ChangeNotifier {
  final _auth = AuthService();

  String             _lang         = 'en';
  String             _businessId   = '';
  String             _selectedShop = '';
  Map<String, Shop>  _shops        = {};
  Map<String, dynamic> _profile    = {};
  bool               _loaded       = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  String             get lang         => _lang;
  String             get businessId   => _businessId;
  String             get selectedShop => _selectedShop;
  Map<String, Shop>  get shops        => Map.unmodifiable(_shops);
  Map<String, dynamic> get profile    => Map.unmodifiable(_profile);
  bool               get loaded       => _loaded;

  bool get isOnboarded => _profile['onboarded'] == true;
  bool get isAdmin     => ((_profile['email'] as String?) ?? '') == 'selvavishnu.m@gmail.com';

  // ── init ──────────────────────────────────────────────────────────────────
  Future<void> init(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString('lang') ?? 'en';

    try {
      Map<String, dynamic>? profileData = await _auth.getProfile(uid);

      // If no staff doc, or businessId is just the current UID (new/wrong account),
      // do a secondary email lookup to find the original account's businessId.
      final bid = profileData?['businessId'] as String?;
      if (bid == null || bid.isEmpty || bid == uid) {
        final email = _auth.currentUser?.email ?? '';
        if (email.isNotEmpty) {
          final emailProfile = await _auth.getProfileByEmail(email);
          if (emailProfile != null) {
            final emailBid = emailProfile['businessId'] as String?;
            // Only switch if we found a DIFFERENT businessId (the original account)
            if (emailBid != null && emailBid.isNotEmpty && emailBid != uid) {
              profileData = emailProfile;
            }
          }
        }
      }

      if (profileData != null) {
        _profile    = profileData;
        _businessId = (profileData['businessId'] as String?)?.isNotEmpty == true
            ? profileData['businessId'] as String
            : uid;

        final configData = await _auth.getConfig(_businessId);
        if (configData != null) {
          final rawShops = configData['shops'] as Map<String, dynamic>? ?? {};
          _shops = rawShops.map(
            (k, v) => MapEntry(k, Shop.fromMap(k, v as Map<String, dynamic>)),
          );
        }
      } else {
        _businessId = uid;
      }
    } catch (_) {
      _businessId = uid;
    }

    _loaded = true;
    notifyListeners();
  }

  // ── Language ──────────────────────────────────────────────────────────────
  void setLang(String l) async {
    _lang = l;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
  }

  // ── Shop selection ────────────────────────────────────────────────────────
  void setSelectedShop(String shopId) {
    _selectedShop = shopId;
    notifyListeners();
  }

  // ── Add shop ──────────────────────────────────────────────────────────────
  void addShop(String id, Shop shop) {
    _shops = Map.from(_shops)..[id] = shop;
    notifyListeners();
    _persistShops();
  }

  void updateShop(String id, Shop shop) {
    _shops = Map.from(_shops)..[id] = shop;
    notifyListeners();
    _persistShops();
  }

  void updateProfileField(String key, dynamic value) {
    _profile = Map<String, dynamic>.from(_profile)..[key] = value;
    notifyListeners();
  }

  Future<void> _persistShops() async {
    if (_businessId.isEmpty) return;
    final shopsMap = _shops.map((k, v) => MapEntry(k, v.toMap()));
    await _auth.saveConfig(_businessId, {'shops': shopsMap});
  }

  // ── Reset (on logout) ─────────────────────────────────────────────────────
  void reset() {
    _businessId   = '';
    _selectedShop = '';
    _shops        = {};
    _profile      = {};
    _loaded       = false;
    notifyListeners();
  }
}
