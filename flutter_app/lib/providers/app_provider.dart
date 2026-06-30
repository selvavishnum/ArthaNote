import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/currency.dart';
import '../models/shop.dart';
import '../models/txn.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';

class AppProvider extends ChangeNotifier {
  final _auth  = AuthService();
  final _dbSvc = DbService();

  // 'system' | 'en' | 'ta' — "system" follows the device's language setting.
  String             _langMode     = 'system';
  // 'system' | ISO 4217 code — "system" follows the device's region.
  String             _currencyMode = 'system';
  // Resolved value of "system" mode — locale-based instantly, refined to the
  // more accurate timezone-based detection once init()/setCurrency() resolve.
  Currency           _systemCurrency = detectSystemCurrencyFromLocale();
  String             _businessId   = '';
  String             _selectedShop = '';
  Map<String, Shop>  _shops        = {};
  Map<String, dynamic> _profile    = {};
  bool               _loaded       = false;
  // Guest mode: app used without login. Data lives only on this device until
  // the user logs in (migration handled in a later step). Fixed local id keeps
  // the cache/config files separate from any future logged-in account.
  bool               _isGuest      = false;
  static const String guestBusinessId = 'guest_local';
  Map<String, Map<String, List<String>>> _cats = {};
  String             _bizType      = '';
  List<Txn>          _txns         = [];
  bool               _syncing      = false;
  DateTime?          _lastSynced;
  // Account-deletion grace period (set when config.status == pending_deletion)
  bool               _pendingDeletion     = false;
  DateTime?          _deletionScheduledAt;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveSyncSub;
  // Debounce for file-cache saves triggered by the live listener.
  // A batch of 50 Firestore events → 1 file write instead of 50.
  Timer? _saveCacheDebounce;

  // ── Own Mode — staff user views their OWN business data ───────────────────
  // Saved employer state while in own mode; restored on exit.
  bool               _ownMode            = false;
  String             _employerBusinessId = '';
  Map<String, Shop>  _employerShops      = {};
  Map<String, dynamic> _employerProfile  = {};
  String             _employerBizType    = '';
  Map<String, Map<String, List<String>>> _employerCats = {};
  List<Txn>          _employerTxns       = [];

  // ── Getters ───────────────────────────────────────────────────────────────
  // Effective language — resolved from the device locale when mode is 'system'.
  String get lang {
    if (_langMode == 'system') {
      switch (ui.PlatformDispatcher.instance.locale.languageCode) {
        case 'ta': return 'ta';
        case 'hi': return 'hi';
        default:   return 'en';
      }
    }
    return _langMode;
  }
  String get langMode => _langMode;

  // Effective currency — resolved from the device region when mode is 'system'.
  Currency get currency {
    final c = _currencyMode == 'system' ? _systemCurrency : currencyByCode(_currencyMode);
    Currency.active = c;
    return c;
  }
  String get currencyMode => _currencyMode;

  // What "System" currently resolves to — shown in the Settings picker even
  // when the user has manually overridden it to a fixed currency.
  Currency get systemCurrency => _systemCurrency;

  String             get businessId   => _businessId;
  String             get selectedShop => _selectedShop;
  Map<String, Shop>  get shops        => Map.unmodifiable(_shops);

  /// Shops the current user may access.
  /// Cashier with an assigned shop → only that shop.
  /// Owner / Manager / Admin → all shops.
  Map<String, Shop> get visibleShops {
    if (isCashier && staffShop.isNotEmpty && _shops.containsKey(staffShop)) {
      return {staffShop: _shops[staffShop]!};
    }
    return Map.unmodifiable(_shops);
  }
  Map<String, dynamic> get profile    => Map.unmodifiable(_profile);
  bool               get loaded       => _loaded;
  Map<String, Map<String, List<String>>> get cats => Map.unmodifiable(_cats);
  String             get bizType      => _bizType;
  // Free tier (after trial) can access only the last [dataRetentionYears] of
  // history; full-access users see everything. Short-circuit for full access —
  // the "unlimited" retention value would overflow a Duration otherwise.
  List<Txn> get txns {
    if (hasFullAccess) return List.unmodifiable(_txns);
    final cutoff =
        DateTime.now().subtract(Duration(days: 365 * dataRetentionYears));
    return List.unmodifiable(_txns.where((t) => !t.date.isBefore(cutoff)));
  }
  bool               get syncing      => _syncing;
  DateTime?          get lastSynced   => _lastSynced;
  bool               get pendingDeletion     => _pendingDeletion;
  DateTime?          get deletionScheduledAt => _deletionScheduledAt;

  /// Cancels a scheduled account deletion during the 30-day grace window
  /// (called from the recovery banner when the owner logs back in).
  Future<void> cancelPendingDeletion() async {
    try {
      await _auth.cancelAccountDeletion(_businessId);
    } catch (_) {}
    _pendingDeletion = false;
    _deletionScheduledAt = null;
    notifyListeners();
  }

  // Finance tab shows only when the currently selected shop is finance/chit type.
  // When "All" is selected (selectedShop empty), Finance tab is hidden.
  bool get isSelectedShopFinance {
    if (_selectedShop.isEmpty) return false;
    final t = _shops[_selectedShop]?.type.toLowerCase() ?? '';
    return t == 'finance' || t == 'chit';
  }

  // Onboarded if: explicit flag set, OR shops exist and the profile belongs to
  // this user's own business (businessId == profile uid). The second condition
  // covers website accounts that never set the 'onboarded' flag. We do NOT
  // treat _shops.isNotEmpty alone as onboarded when the profile was found via
  // email-lookup linking (businessId != profile uid) — that would skip
  // onboarding for new users whose email matches a staff record in another
  // business.
  bool get isOnboarded {
    // In own mode the user is viewing their own account — skip onboarding.
    if (_ownMode) return true;
    // Cashier staff are assigned to a shop by the owner — skip onboarding entirely
    if (isCashier) return true;
    if (_profile['onboarded'] == true) return true;
    if (_shops.isNotEmpty) {
      final profileUid = (_profile['uid'] as String?)?.trim() ?? '';
      // Only treat shops as proof of onboarding when this is the user's own account
      if (profileUid.isEmpty || profileUid == _businessId) return true;
    }
    return false;
  }
  bool get isAdmin     => ((_profile['email'] as String?) ?? '') == 'selvavishnu.m@gmail.com';
  bool get isOwnMode   => _ownMode;
  bool get isGuest     => _isGuest;

  /// True when the user's Firestore role is cashier — regardless of own mode.
  /// Use this to decide UI chrome that belongs to the staff identity (e.g. the
  /// profile panel icon).  Use [isCashier] for data-access / navigation guards.
  bool get isStaffRole {
    final role = (_profile['role'] as String?)?.toLowerCase() ?? '';
    return role == 'cashier' && !isAdmin;
  }

  // ── Monetization / Entitlements ────────────────────────────────────────────
  // Single source of truth for Pro access and free-tier limits. Every paywalled
  // feature MUST read [hasFullAccess] / the gate getters — never profile['pro']
  // directly — so billing only has to flip one place.
  //
  // Access model:
  //   • New users get a FREE 3-month trial (full Pro access) from signup.
  //   • Paid Pro is active when profile['pro'] == true and not expired.
  //   • Lifetime plans store planType == 'lifetime' with no proExpiry.
  //   • After the trial ends and with no paid plan → free-tier limits apply.
  static const int _unlimited = 1 << 30;
  static const int trialDays  = 90; // ~3 months full-access trial

  bool get isPro {
    if (isAdmin) return true; // owner/admin always has full access
    if (_profile['pro'] != true) return false;
    final exp = _profile['proExpiry'];
    if (exp is Timestamp) return exp.toDate().isAfter(DateTime.now());
    return true; // lifetime / no-expiry pro
  }

  /// When the trial clock started: an explicit profile['trialStartedAt'] if set,
  /// otherwise the Firebase account creation time (no migration needed).
  DateTime? get _trialStart {
    final ts = _profile['trialStartedAt'];
    if (ts is Timestamp) return ts.toDate();
    return _auth.currentUser?.metadata.creationTime;
  }

  DateTime? get trialEndsAt =>
      _trialStart?.add(const Duration(days: trialDays));

  /// Whether the user is inside their free full-access trial window.
  bool get isInTrial {
    if (isPro) return false; // paid users don't need the trial
    final end = trialEndsAt;
    return end != null && DateTime.now().isBefore(end);
  }

  /// Whole days remaining in the trial (0 once expired).
  int get trialDaysLeft {
    final end = trialEndsAt;
    if (end == null) return 0;
    final left = end.difference(DateTime.now()).inDays;
    return left > 0 ? left : 0;
  }

  /// True when the trial has run out and there is no paid plan — this is when
  /// the Pro recommendation / paywall should be surfaced.
  bool get trialExpired => !isPro && !isInTrial && _trialStart != null;

  /// THE access switch every paywalled feature reads: paid Pro OR active trial.
  bool get hasFullAccess => isPro || isInTrial;

  /// 'admin' | 'lifetime' | 'yearly' | 'monthly' | 'pro' | 'trial' | 'free'
  String get planType {
    if (isAdmin) return 'admin';
    final pt = (_profile['planType'] as String?)?.trim();
    if (pt != null && pt.isNotEmpty && isPro) return pt;
    if (isPro) return 'pro';
    if (isInTrial) return 'trial';
    return 'free';
  }

  DateTime? get proExpiry {
    final exp = _profile['proExpiry'];
    return exp is Timestamp ? exp.toDate() : null;
  }

  // Free-tier limits (full access = unlimited)
  int get maxShops           => hasFullAccess ? _unlimited : 1;  // + 1 personal
  int get maxStaff           => hasFullAccess ? _unlimited : 10;
  int get dataRetentionYears => hasFullAccess ? _unlimited : 2;

  // Feature gates — true means the user may use the feature
  bool get canUseReports        => hasFullAccess;
  bool get canUseFinanceModule  => hasFullAccess;
  bool get canUseAiAlerts       => hasFullAccess;
  bool get canUseDuplicateAlert => hasFullAccess;
  bool get canUseReminders      => hasFullAccess;
  bool get canUseCustomEntry    => hasFullAccess; // the "+ Custom" quick button

  /// Business shops currently set up (excludes the implicit personal shop).
  int get businessShopCount =>
      _shops.values.where((s) => s.type.toLowerCase() != 'personal').length;

  /// Whether the user may add another (business) shop under their plan.
  bool get canAddShop => hasFullAccess || businessShopCount < maxShops;

  bool get isPersonal {
    if (_selectedShop.isNotEmpty) {
      return _shops[_selectedShop]?.type == 'personal';
    }
    return _bizType == 'personal';
  }
  bool get isCashier => isStaffRole && !_ownMode;
  String get staffShop => (_profile['shop'] as String?) ?? '';

  // ── init ──────────────────────────────────────────────────────────────────
  Future<void> init(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    // Preserve a pre-existing explicit language choice (no 'lang_mode' yet,
    // but a legacy 'lang' value) so this feature doesn't silently change a
    // returning user's language. Brand-new installs default to 'system'.
    _langMode     = prefs.getString('lang_mode') ?? prefs.getString('lang') ?? 'system';
    _currencyMode = prefs.getString('currency_mode') ?? 'system';
    _systemCurrency = await detectSystemCurrency();
    currency; // sync Currency.active immediately, before any widget reads it

    try {
      // Resolve strictly by uid — staff/{uid} is this device's own account.
      // (Cross-account linking is handled only via the explicit "Connect to
      // Employer" flow in setManualBusinessId, which requires the staff
      // member to paste a businessId they were given — never an automatic
      // email match, which could silently pull in an unrelated account's
      // business data if any other staff doc happens to share the email.)
      final profileData = await _auth.getProfile(uid);

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
              'payment': List<String>.from(vMap['payment'] as List? ?? []),
            });
          });
          // Detect a scheduled (recoverable) account deletion so the UI can
          // offer the owner a chance to cancel within the 30-day grace window.
          _pendingDeletion = configData['status'] == 'pending_deletion';
          final sched = configData['deletionScheduledAt'];
          _deletionScheduledAt = sched is Timestamp ? sched.toDate() : null;
        }
      } else {
        _businessId = uid;
      }
    } catch (_) {
      _businessId = uid;
    }

    _loaded = true;
    // Auto-select assigned shop for cashier staff
    if (isCashier && staffShop.isNotEmpty && _shops.containsKey(staffShop)) {
      _selectedShop = staffShop;
    }
    notifyListeners();

    // Non-blocking — loads txns in background (fast file read + optional daily sync)
    _loadTxns();
  }

  // ── Guest init (no login) ───────────────────────────────────────────────────
  /// Initialises the app for a guest (not logged in). Everything is local:
  /// config (shops/cats/bizType) is read from SharedPreferences and txns from
  /// the on-device cache — no Firestore. Guest = free tier (isInTrial/isPro are
  /// false because there is no auth user), so the free limits apply from start.
  Future<void> initGuest() async {
    final prefs = await SharedPreferences.getInstance();
    _langMode     = prefs.getString('lang_mode') ?? prefs.getString('lang') ?? 'system';
    _currencyMode = prefs.getString('currency_mode') ?? 'system';
    _systemCurrency = await detectSystemCurrency();
    currency;

    _isGuest    = true;
    _ownMode    = false;
    _profile    = {};
    _businessId = guestBusinessId;
    await _loadConfigLocal();

    _loaded = true;
    notifyListeners();
    _loadTxns(); // guest branch skips Firestore sync (see _loadTxns)
  }

  static const guestModeFlag = 'kp_guest_mode';

  /// Marks this device as a guest session (persisted) so the splash screen
  /// routes straight to the app on subsequent launches.
  Future<void> enableGuestMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(guestModeFlag, true);
  }

  /// Migrates a guest's on-device data into a real account when they log in.
  /// Uploads guest shops/cats/bizType to the account's Firestore config (merged
  /// with any existing data) and re-saves each guest transaction under the new
  /// businessId, then clears the guest session. Safe no-op if not a guest.
  /// Call this BEFORE init(uid) in the login flow.
  Future<void> migrateGuestToAccount(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(guestModeFlag) != true) return; // not a guest session

    // 1. Load guest config + txns from on-device storage.
    await _loadConfigLocal();
    final guestShops = Map<String, Shop>.from(_shops);
    final guestCats  = Map<String, Map<String, List<String>>>.from(_cats);
    final guestBiz   = _bizType;
    final guestTxns  = await _dbSvc.loadAllTxns(guestBusinessId);

    // 2. Resolve the target businessId (the account's own id).
    String targetBid = uid;
    try {
      final profile = await _auth.getProfile(uid);
      final pBid = (profile?['businessId'] as String?)?.trim();
      if (pBid != null && pBid.isNotEmpty) targetBid = pBid;
    } catch (_) {}

    // 3. Upload guest config (merged with any existing account config).
    if (guestShops.isNotEmpty || guestBiz.isNotEmpty) {
      try {
        await _auth.saveConfig(targetBid, {
          if (guestShops.isNotEmpty)
            'shops': guestShops.map((k, v) => MapEntry(k, v.toMap())),
          if (guestCats.isNotEmpty)
            'cats': guestCats.map((k, v) => MapEntry(k, {
                  'sales':   v['sales']   ?? [],
                  'expense': v['expense'] ?? [],
                  'payment': v['payment'] ?? [],
                })),
          if (guestBiz.isNotEmpty) 'bizType': guestBiz,
          'onboarded': true,
        });
      } catch (_) {}
    }

    // 4. Re-save each guest transaction under the account's businessId
    //    (writes to Firestore + the account's local cache).
    for (final t in guestTxns) {
      try {
        await _dbSvc.addTxn(t.copyWith(businessId: targetBid));
      } catch (_) {}
    }

    // Mark the account synced so the first post-login load reads the cache we
    // just populated (with the migrated entries) instead of racing a full
    // Firestore sync whose writes are still in flight. The live listener then
    // reconciles once the writes land.
    if (guestTxns.isNotEmpty) {
      await _dbSvc.markSynced(targetBid);
    }

    // 5. Tear down the guest session.
    await prefs.remove(guestModeFlag);
    await prefs.remove(_guestConfigKey);
    await _dbSvc.saveTxnsToCache(guestBusinessId, []);
    _isGuest = false;
  }

  static const _guestConfigKey = 'kp_guest_config';

  Future<void> _saveConfigLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'shops':   _shops.map((k, v) => MapEntry(k, v.toMap())),
      'cats':    _cats,
      'bizType': _bizType,
    };
    await prefs.setString(_guestConfigKey, jsonEncode(data));
  }

  Future<void> _loadConfigLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guestConfigKey);
    if (raw == null) { _shops = {}; _cats = {}; _bizType = ''; return; }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final rawShops = data['shops'] as Map<String, dynamic>? ?? {};
      _shops = rawShops.map(
        (k, v) => MapEntry(k, Shop.fromMap(k, v as Map<String, dynamic>)),
      );
      final rawCats = data['cats'] as Map<String, dynamic>? ?? {};
      _cats = rawCats.map((k, v) {
        final vMap = v as Map<String, dynamic>? ?? {};
        return MapEntry(k, {
          'sales':   List<String>.from(vMap['sales']   as List? ?? []),
          'expense': List<String>.from(vMap['expense'] as List? ?? []),
          'payment': List<String>.from(vMap['payment'] as List? ?? []),
        });
      });
      _bizType = (data['bizType'] as String?) ?? '';
    } catch (_) {
      _shops = {}; _cats = {}; _bizType = '';
    }
  }

  /// Sets the business type during onboarding and persists it (guest = local).
  Future<void> setBizType(String type) async {
    _bizType = type;
    notifyListeners();
    if (_isGuest) {
      await _saveConfigLocal();
    } else {
      await _auth.saveConfig(_businessId, {'bizType': type, 'onboarded': true});
    }
  }

  // ── Language ──────────────────────────────────────────────────────────────
  // l: 'system' | 'en' | 'ta'
  void setLang(String l) async {
    _langMode = l;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang_mode', l);
  }

  // ── Currency ──────────────────────────────────────────────────────────────
  // code: 'system' | ISO 4217 code (e.g. 'USD')
  void setCurrency(String code) async {
    _currencyMode = code;
    if (code == 'system') _systemCurrency = await detectSystemCurrency();
    currency; // sync Currency.active immediately
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency_mode', code);
  }

  // ── Shop selection ────────────────────────────────────────────────────────
  void setSelectedShop(String shopId) {
    // Cashier is locked to their assigned shop — ignore any other selection.
    if (isCashier && staffShop.isNotEmpty && shopId != staffShop) return;
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

  /// Raw (retention-unfiltered) count of entries for a shop — used by the
  /// shop-delete confirmation to warn how many entries will be lost.
  int shopEntryCount(String id) =>
      _txns.where((t) => t.shop == id).length;

  /// Deletes a shop AND all its transactions permanently (no orphaned entries
  /// left behind). Updates local cache + memory immediately, then removes the
  /// docs server-side (which also catches any entries not in the local cache).
  /// Returns the number of entries removed from memory.
  Future<int> deleteShopWithEntries(String id) async {
    final bid     = _businessId;
    final before  = _txns.length;
    _txns = _txns.where((t) => t.shop != id).toList();
    final removed = before - _txns.length;
    _shops = Map.from(_shops)..remove(id);
    _cats  = Map.from(_cats)..remove(id);
    if (_selectedShop == id) _selectedShop = '';
    notifyListeners();
    _persistShops();
    _persistCats();
    // Server delete + cache file rewrite.
    await _dbSvc.deleteShopTxns(bid, id);
    return removed;
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

  List<String> paymentCats(String shopId) {
    final custom = _cats[shopId]?['payment'];
    if (custom != null && custom.isNotEmpty) return List.from(custom);
    return const ['Supplier', 'Loan', 'Staff', 'Utility'];
  }

  void updateShopCats(String shopId, List<String> sales, List<String> expense) {
    final shopCats = Map<String, List<String>>.from(_cats[shopId] ?? {});
    shopCats['sales']   = sales;
    shopCats['expense'] = expense;
    _cats = Map.from(_cats)..[shopId] = shopCats;
    notifyListeners();
    _persistCats();
  }

  /// Permanently adds a quick-select category for [shopId]/[type] (sale,
  /// expense or payment) — e.g. when the user types a "+ Custom" entry
  /// description, it's saved here so it appears as a chip next time.
  void addCustomCategory(String shopId, String type, String category) {
    if (category.trim().isEmpty) return;
    final key = type == 'sale' ? 'sales' : (type == 'expense' ? 'expense' : 'payment');
    final current = List<String>.from(
      key == 'sales' ? salesCats(shopId) : (key == 'expense' ? expenseCats(shopId) : paymentCats(shopId)),
    );
    if (current.contains(category)) return;
    current.add(category);
    final shopCats = Map<String, List<String>>.from(_cats[shopId] ?? {});
    shopCats[key] = current;
    _cats = Map.from(_cats)..[shopId] = shopCats;
    notifyListeners();
    _persistCats();
  }

  void updateProfileField(String key, dynamic value) {
    _profile = Map<String, dynamic>.from(_profile)..[key] = value;
    notifyListeners();
  }

  Future<void> _persistShops() async {
    if (_businessId.isEmpty) return;
    if (_isGuest) { await _saveConfigLocal(); return; } // local-only for guests
    final shopsMap = _shops.map((k, v) => MapEntry(k, v.toMap()));
    // Use saveShops (update) so deleted shop keys are actually removed.
    // saveConfig with merge:true only adds/updates — it never removes map keys.
    await _auth.saveShops(_businessId, shopsMap);
  }

  Future<void> _persistCats() async {
    if (_businessId.isEmpty) return;
    if (_isGuest) { await _saveConfigLocal(); return; } // local-only for guests
    final catsMap = _cats.map((k, v) => MapEntry(k, {
      'sales':   v['sales']   ?? [],
      'expense': v['expense'] ?? [],
      'payment': v['payment'] ?? [],
    }));
    await _auth.saveConfig(_businessId, {'cats': catsMap});
  }

  // ── Txn management ────────────────────────────────────────────────────────

  Future<void> _loadTxns() async {
    if (_businessId.isEmpty) return;

    // 1. Load from file cache immediately
    final cached = await _dbSvc.loadAllTxns(_businessId);
    _txns = cached;
    notifyListeners();

    // Guests have no Firestore — local cache is the whole story.
    if (_isGuest) return;

    // 2. Sync from Firebase if needed (once per day)
    if (await _dbSvc.needsSync(_businessId)) {
      _syncing = true;
      notifyListeners();
      try {
        // Flush any offline-pending entries first so they are included in the
        // fresh fetch below. This recovers entries whose Firestore writes failed
        // (e.g. a payment saved while briefly offline).
        await _dbSvc.syncPending();
        final fresh = await _dbSvc.syncFromFirebase(_businessId);
        // Merge: preserve any in-memory entries that aren't in fresh yet
        // (entries added since this sync started whose Firestore write is
        // still in-flight). This prevents them from briefly disappearing.
        final freshIds = {for (final t in fresh) t.id};
        final localOnly = _txns.where((t) => !freshIds.contains(t.id)).toList();
        if (localOnly.isNotEmpty) {
          final merged = [...localOnly, ...fresh];
          merged.sort((a, b) => b.date.compareTo(a.date));
          _txns = merged;
        } else {
          _txns = fresh;
        }
        // Persist the MERGED list (not just `fresh`) so entries whose Firestore
        // write is still in flight — e.g. freshly migrated guest entries — are
        // kept in the cache instead of being wiped by an empty/partial sync.
        await _dbSvc.saveTxnsToCache(_businessId, _txns);
        await _dbSvc.markSynced(_businessId);
        _lastSynced = DateTime.now();
      } catch (_) {}
      _syncing = false;
      notifyListeners();
    } else {
      _lastSynced = await _dbSvc.getLastSyncTime(_businessId);
    }

    // 3. Start real-time listener for new entries from other devices
    _startLiveSync();
  }

  void _startLiveSync() {
    _liveSyncSub?.cancel();
    if (_businessId.isEmpty) return;

    // Single-field equality query — no composite index required.
    // Avoids the Timestamp vs. String date type mismatch that caused compound
    // queries to silently miss Flutter-app entries (which store date as Timestamp
    // while website entries store it as a "YYYY-MM-DD" string).
    _liveSyncSub = FirebaseFirestore.instance
        .collection('transactions')
        .where('businessId', isEqualTo: _businessId)
        .snapshots()
        .listen((snap) {
      if (snap.docChanges.isEmpty) return;

      final existingIds = {for (final t in _txns) t.id};
      var changed = false;

      for (final change in snap.docChanges) {
        // hasPendingWrites = true means this is OUR write, already added via
        // addLocalTxn(). Only process changes from other devices (server-confirmed).
        if (change.doc.metadata.hasPendingWrites) continue;

        if (change.type == DocumentChangeType.removed) {
          final before = _txns.length;
          _txns = _txns.where((t) => t.id != change.doc.id).toList();
          if (_txns.length != before) changed = true;
        } else if (change.type == DocumentChangeType.added) {
          if (!existingIds.contains(change.doc.id)) {
            _txns = [Txn.fromFirestore(change.doc), ..._txns];
            existingIds.add(change.doc.id);
            changed = true;
          }
        } else if (change.type == DocumentChangeType.modified) {
          final txn = Txn.fromFirestore(change.doc);
          final idx = _txns.indexWhere((t) => t.id == txn.id);
          if (idx != -1) {
            _txns[idx] = txn;
            changed = true;
          }
        }
      }

      if (changed) {
        _txns.sort((a, b) => b.date.compareTo(a.date));
        notifyListeners();
        // Debounce cache writes — a burst of 50 events becomes 1 file write.
        _saveCacheDebounce?.cancel();
        _saveCacheDebounce = Timer(const Duration(milliseconds: 800), () {
          _dbSvc.saveTxnsToCache(_businessId, _txns);
        });
      }
    }, onError: (_) {});
  }

  Future<void> syncNow() async {
    if (_businessId.isEmpty || _syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      // Flush offline-pending entries before fetching so they appear in fresh data.
      await _dbSvc.syncPending();

      // Clear cursor so syncFromFirebase does a full paginated sync.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('kp_sync_cursor_$_businessId');

      final fresh = await _dbSvc.syncFromFirebase(_businessId);
      // Preserve in-memory entries not yet confirmed by Firestore.
      final freshIds = {for (final t in fresh) t.id};
      final localOnly = _txns.where((t) => !freshIds.contains(t.id)).toList();
      if (localOnly.isNotEmpty) {
        final merged = [...localOnly, ...fresh];
        merged.sort((a, b) => b.date.compareTo(a.date));
        _txns = merged;
      } else {
        _txns = fresh;
      }
      await _dbSvc.saveTxnsToCache(_businessId, fresh);
      await _dbSvc.markSynced(_businessId);
      _lastSynced = DateTime.now();
    } catch (_) {}
    _syncing = false;
    notifyListeners();
  }

  // ── Manual business ID (staff fallback) ──────────────────────────────────
  // Called when staff enters their employer's business ID manually.
  // Requires a matching owner-granted staff doc (auto-ID doc created by
  // grantStaffAccess / the Add Staff dialog) with that email + businessId —
  // otherwise this would let anyone link their account to any business ID
  // they happen to type in. Throws if no grant is found.
  Future<void> setManualBusinessId(String bid) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || bid.trim().isEmpty) return;
    final email = _auth.currentUser?.email ?? '';

    // Find the owner-granted doc (auto-ID doc created by grantStaffAccess)
    // which holds the assigned shop. A grant doc never carries a 'uid' field
    // (only real self-profiles do), so this also can't match another
    // person's own profile doc.
    String shopId = '';
    bool granted = false;
    final snap = await FirebaseFirestore.instance
        .collection('staff')
        .where('email', isEqualTo: email.toLowerCase())
        .where('businessId', isEqualTo: bid.trim())
        .limit(3)
        .get();
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d.containsKey('uid')) continue;
      granted = true;
      final s = (d['shop'] as String?)?.trim() ?? '';
      if (s.isNotEmpty) { shopId = s; break; }
    }

    if (!granted) {
      throw Exception(
          'No staff access has been granted to $email for this business ID. '
          'Ask the shop owner to add you as staff first.');
    }

    await _auth.saveProfile(uid, {
      'uid':        uid,
      'email':      email,
      'businessId': bid.trim(),
      'role':       'cashier',
      'shop':       shopId,
      'onboarded':  true,
    });
    _loaded      = false;
    _txns        = [];
    _shops       = {};
    _profile     = {};
    _businessId  = '';
    _liveSyncSub?.cancel();
    _liveSyncSub = null;
    notifyListeners();
    await init(uid);
  }

  // ── Own Mode toggle ───────────────────────────────────────────────────────
  /// Switches between employer's data (staff mode) and the user's own business
  /// data (own mode) without signing out.
  Future<void> toggleOwnMode() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (!_ownMode) {
      // — Enter own mode: save employer state, switch to own UID —
      _employerBusinessId = _businessId;
      _employerShops      = Map.from(_shops);
      _employerProfile    = Map.from(_profile);
      _employerBizType    = _bizType;
      _employerCats       = Map.from(_cats);
      _employerTxns       = List.from(_txns);

      _liveSyncSub?.cancel();
      _liveSyncSub = null;
      _saveCacheDebounce?.cancel();
      _saveCacheDebounce = null;

      _ownMode      = true;
      _businessId   = uid;
      _selectedShop = '';
      _txns         = [];
      _shops        = {};
      _cats         = {};
      _bizType      = '';

      // Load own config from Firestore
      try {
        final configData = await _auth.getConfig(uid);
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
              'payment': List<String>.from(vMap['payment'] as List? ?? []),
            });
          });
        }
      } catch (_) {}

      notifyListeners();
      _loadTxns();
    } else {
      // — Exit own mode: restore employer state —
      _liveSyncSub?.cancel();
      _liveSyncSub = null;
      _saveCacheDebounce?.cancel();
      _saveCacheDebounce = null;

      _ownMode    = false;
      _businessId = _employerBusinessId;
      _shops      = _employerShops;
      _profile    = _employerProfile;
      _bizType    = _employerBizType;
      _cats       = _employerCats;
      _txns       = _employerTxns;

      final assignedShop = staffShop;
      _selectedShop = assignedShop.isNotEmpty && _shops.containsKey(assignedShop)
          ? assignedShop
          : '';

      _employerBusinessId = '';
      _employerShops      = {};
      _employerProfile    = {};
      _employerBizType    = '';
      _employerCats       = {};
      _employerTxns       = [];

      notifyListeners();
      _startLiveSync();
    }
  }

  void addLocalTxn(Txn t) {
    // Upsert — remove any existing entry with the same ID before prepending,
    // so a race condition that calls addLocalTxn twice never creates a duplicate.
    _txns = [t, ..._txns.where((e) => e.id != t.id)];
    notifyListeners();
  }

  void removeLocalTxn(String id) {
    _txns = _txns.where((t) => t.id != id).toList();
    notifyListeners();
  }

  void updateLocalTxn(Txn updated) {
    _txns = [
      for (final t in _txns)
        if (t.id == updated.id) updated else t,
    ];
    notifyListeners();
  }

  // ── Reset (on logout) ─────────────────────────────────────────────────────
  void reset() {
    _liveSyncSub?.cancel();
    _liveSyncSub  = null;
    _saveCacheDebounce?.cancel();
    _saveCacheDebounce = null;
    _ownMode            = false;
    _employerBusinessId = '';
    _employerShops      = {};
    _employerProfile    = {};
    _employerBizType    = '';
    _employerCats       = {};
    _employerTxns       = [];
    _businessId   = '';
    _selectedShop = '';
    _shops        = {};
    _profile      = {};
    _cats         = {};
    _bizType      = '';
    _loaded       = false;
    _txns         = [];
    _syncing      = false;
    _lastSynced   = null;
    notifyListeners();
  }
}
