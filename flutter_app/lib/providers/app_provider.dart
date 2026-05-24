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
  Map<String, Map<String, List<String>>> _cats = {};
  String             _bizType      = '';

  // ── Getters ───────────────────────────────────────────────────────────────
  String             get lang         => _lang;
  String             get businessId   => _businessId;
  String             get selectedShop => _selectedShop;
  Map<String, Shop>  get shops        => Map.unmodifiable(_shops);
  Map<String, dynamic> get profile    => Map.unmodifiable(_profile);
  bool               get loaded       => _loaded;
  Map<String, Map<String, List<String>>> get cats => Map.unmodifiable(_cats);
  String             get bizType      => _bizType;

  // Finance tab shows only when the currently selected shop is finance/chit type.
  // When "All" is selected (selectedShop empty), Finance tab is hidden.
  bool get isSelectedShopFinance {
    if (_selectedShop.isEmpty) return false;
    final t = _shops[_selectedShop]?.type.toLowerCase() ?? '';
    return t == 'finance' || t == 'chit';
  }

  // Also treat as onboarded when shops exist in config — covers accounts
  // registered on the website where 'onboarded' flag wasn't set in Firestore.
  bool get isOnboarded => _profile['onboarded'] == true || _shops.isNotEmpty;
  bool get isAdmin     => ((_profile['email'] as String?) ?? '') == 'selvavishnu.m@gmail.com';

  // ── init ──────────────────────────────────────────────────────────────────
  Future<void> init(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString('lang') ?? 'en';

    try {
      Map<String, dynamic>? profileData = await _auth.getProfile(uid);
      final email = _auth.currentUser?.email ?? '';

      // Always try email lookup — handles UID mismatch when the same email
      // signs in via different auth methods (e.g. email/password on web vs
      // Google on Android creates a different Firebase UID).
      // Pass skipUid so the lookup prefers the ORIGINAL account's doc
      // (businessId ≠ current uid) over any newly-created duplicate.
      if (email.isNotEmpty) {
        final emailProfile = await _auth.getProfileByEmail(email, skipUid: uid);
        if (emailProfile != null) {
          final emailBid = (emailProfile['businessId'] as String?)?.trim() ?? '';
          // Use the email-found profile only if it points to a DIFFERENT businessId
          // (the original account), not the current UID.
          if (emailBid.isNotEmpty && emailBid != uid) {
            profileData = emailProfile;
          }
        }
      }

      if (profileData != null) {
        _profile    = profileData;
        _businessId = ((profileData['businessId'] as String?)?.trim().isNotEmpty == true)
            ? (profileData['businessId'] as String).trim()
            : uid;

        final configData = await _auth.getConfig(_businessId);
        if (configData != null) {
          final rawShops = configData['shops'] as Map<String, dynamic>? ?? {};
          _shops = rawShops.map(
            (k, v) => MapEntry(k, Shop.fromMap(k, v as Map<String, dynamic>)),
          );
          _bizType = (configData['bizType'] as String?)?.toLowerCase().trim() ?? '';
          final rawCats = configData['cats'] as Map<String, dynamic>? ?? {};
          _cats = rawCats.map((k, v) {
            final vMap = v as Map<String, dynamic>? ?? {};
            return MapEntry(k, {
              'sales':   List<String>.from(vMap['sales']   as List? ?? []),
              'expense': List<String>.from(vMap['expense'] as List? ?? []),
            });
          });
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

  void removeShop(String id) {
    _shops = Map.from(_shops)..remove(id);
    _cats  = Map.from(_cats)..remove(id);
    if (_selectedShop == id) _selectedShop = '';
    notifyListeners();
    _persistShops();
    _persistCats();
  }

  List<String> salesCats(String shopId) {
    final custom = _cats[shopId]?['sales'];
    if (custom != null && custom.isNotEmpty) return List.from(custom);
    final shop = _shops[shopId];
    if (shop != null) {
      final bc = kBizCats[shop.type];
      if (bc != null) return List.from(bc['sales']!);
    }
    return ['Cash', 'GPay', 'Card', 'Other'];
  }

  List<String> expenseCats(String shopId) {
    final custom = _cats[shopId]?['expense'];
    if (custom != null && custom.isNotEmpty) return List.from(custom);
    final shop = _shops[shopId];
    if (shop != null) {
      final bc = kBizCats[shop.type];
      if (bc != null) return List.from(bc['expense']!);
    }
    return ['Purchase', 'Salary', 'Rent/EB', 'Other'];
  }

  void updateShopCats(String shopId, List<String> sales, List<String> expense) {
    _cats = Map.from(_cats)..[shopId] = {'sales': sales, 'expense': expense};
    notifyListeners();
    _persistCats();
  }

  void updateProfileField(String key, dynamic value) {
    _profile = Map<String, dynamic>.from(_profile)..[key] = value;
    notifyListeners();
  }

  Future<void> _persistShops() async {
    if (_businessId.isEmpty) return;
    final shopsMap = _shops.map((k, v) => MapEntry(k, v.toMap()));
    // Use saveShops (update) so deleted shop keys are actually removed.
    // saveConfig with merge:true only adds/updates — it never removes map keys.
    await _auth.saveShops(_businessId, shopsMap);
  }

  Future<void> _persistCats() async {
    if (_businessId.isEmpty) return;
    final catsMap = _cats.map((k, v) => MapEntry(k, {
      'sales':   v['sales']   ?? [],
      'expense': v['expense'] ?? [],
    }));
    await _auth.saveConfig(_businessId, {'cats': catsMap});
  }

  // ── Reset (on logout) ─────────────────────────────────────────────────────
  void reset() {
    _businessId   = '';
    _selectedShop = '';
    _shops        = {};
    _profile      = {};
    _cats         = {};
    _bizType      = '';
    _loaded       = false;
    notifyListeners();
  }
}
