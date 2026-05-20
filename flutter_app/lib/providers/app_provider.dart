import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';

class AppProvider extends ChangeNotifier {
  final _auth = AuthService();

  String _lang = 'en';
  String _businessId = '';
  String _selectedShop = '';
  Map<String, Shop> _shops = {};
  Map<String, dynamic> _profile = {};
  bool _loaded = false;

  String get lang         => _lang;
  String get businessId   => _businessId;
  String get selectedShop => _selectedShop;
  Map<String, Shop> get shops => _shops;
  Map<String, dynamic> get profile => _profile;
  bool get loaded         => _loaded;

  Future<void> init(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString('lang') ?? 'en';

    final profileData = await _auth.getProfile(uid);
    if (profileData != null) {
      _profile    = profileData;
      _businessId = profileData['businessId'] ?? uid;

      final configData = await _auth.getConfig(_businessId);
      if (configData != null) {
        final shopsMap = configData['shops'] as Map<String, dynamic>? ?? {};
        _shops = shopsMap.map((k, v) => MapEntry(k, Shop.fromMap(k, v as Map<String, dynamic>)));
      }
    } else {
      _businessId = uid;
    }

    _loaded = true;
    notifyListeners();
  }

  void setLang(String l) async {
    _lang = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
    notifyListeners();
  }

  void setSelectedShop(String s) {
    _selectedShop = s;
    notifyListeners();
  }

  void addShop(String id, Shop shop) {
    _shops[id] = shop;
    notifyListeners();
    _saveShops();
  }

  Future<void> _saveShops() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final shopsMap = _shops.map((k, v) => MapEntry(k, v.toMap()));
    await _auth.saveConfig(_businessId, {'shops': shopsMap});
  }

  void reset() {
    _businessId   = '';
    _selectedShop = '';
    _shops        = {};
    _profile      = {};
    _loaded       = false;
    notifyListeners();
  }
}
