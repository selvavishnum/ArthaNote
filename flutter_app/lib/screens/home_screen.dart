import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../widgets/nav_icons.dart';
import '../l10n.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';
import '../models/currency.dart';
import '../models/txn.dart';
import '../models/shop.dart';
import 'dashboard_tab.dart';
import 'scan_tab.dart';
import 'entry_tab.dart';
import 'ledger_tab.dart';
import 'suppliers_tab.dart';
import 'customers_screen.dart';
import 'reports_tab.dart';
import 'finance_tab.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'upgrade_screen.dart';
import 'construction_screen.dart';
import 'qr_scan_screen.dart';
import '../services/lock_service.dart';
import 'lock_screen.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quick_expense_sheet.dart';
import '../services/receipt_ocr.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  final _db     = DbService();
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initShareIntake();
    // Sync any pending offline entries when connectivity returns
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        final p = context.read<AppProvider>();
        if (p.businessId.isNotEmpty) _db.syncPending();
      }
    });
    // Also try on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<AppProvider>();
      if (p.businessId.isNotEmpty) _db.syncPending();
    });
  }

  // ── Receive shared GPay/PhonePe receipts → quick expense ──────────────────
  void _initShareIntake() {
    // Warm start: app already open when a receipt is shared.
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) { if (files.isNotEmpty) _handleShared(files); },
      onError: (_) {},
    );
    // Cold start: app launched from the share sheet.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        _handleShared(files);
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  void _handleShared(List<SharedMediaFile> files) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // GPay shares the receipt image AND a caption text in one intent —
      // parse every part and merge, image first (it carries the details).
      // On-device OCR runs invisibly (no API). Image → ML Kit; text → regex.
      final images = files
          .where((f) => f.type == SharedMediaType.image)
          .toList();
      final others = files
          .where((f) => f.type != SharedMediaType.image)
          .toList();
      ReceiptData? data;
      for (final f in images) {
        final d = await ReceiptOcr.extractFromImage(f.path);
        data = data == null ? d : ReceiptData.merge(data, d);
      }
      for (final f in others) {
        final d = ReceiptParser.parse(f.path);
        data = data == null ? d : ReceiptData.merge(data, d);
      }
      if (data == null || !mounted) return;
      final imagePath = images.isNotEmpty ? images.first.path : null;
      if (data.hasAmount) {
        // Confident read → save automatically, with an Edit action.
        await _autoSaveReceipt(data, imagePath: imagePath);
      } else {
        // Couldn't read the amount → open the sheet for a quick manual finish.
        showQuickExpenseFromShare(context, imagePath: imagePath, parsed: data);
      }
    });
  }

  Future<void> _autoSaveReceipt(ReceiptData d, {String? imagePath}) async {
    final p = context.read<AppProvider>();
    if (p.businessId.isEmpty) {
      showQuickExpenseFromShare(context, imagePath: imagePath, parsed: d);
      return;
    }
    final shopId = p.selectedShop.isNotEmpty
        ? p.selectedShop
        : (p.shops.keys.isNotEmpty ? p.shops.keys.first : '');
    final now = DateTime.now();
    final day = d.date ?? now;
    final isIncome = d.isIncome;
    final txn = Txn(
      id:         now.millisecondsSinceEpoch.toString(),
      businessId: p.businessId,
      shop:       shopId,
      shopName:   p.shops[shopId]?.name ?? '',
      date:       DateTime(day.year, day.month, day.day, now.hour, now.minute),
      type:       d.txnType, // 'expense' (paid) or 'sale' (received)
      amount:     d.amount!,
      desc:       (d.payee == null || d.payee!.isEmpty)
          ? (isIncome ? 'UPI received' : 'UPI payment')
          : d.payee!,
      contact:    d.txnId ?? '',
      createdAt:  now,
    );
    try {
      await _db.addTxn(txn);
      if (!mounted) return;
      p.addLocalTxn(txn);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isIncome
            ? '✓ ${p.currency.symbol}${d.amount!.toStringAsFixed(0)} '
                'from ${d.payee ?? "UPI"} received'
            : '✓ ${p.currency.symbol}${d.amount!.toStringAsFixed(0)} '
                'to ${d.payee ?? "UPI"} saved'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Edit',
          textColor: Colors.white,
          // Pass the SAVED txn so the sheet updates it in place — reopening
          // with only the parsed data would insert a second entry on save.
          onPressed: () => showQuickExpenseFromShare(context,
              imagePath: imagePath, parsed: d, editTxn: txn),
        ),
      ));
    } catch (_) {
      if (mounted) {
        showQuickExpenseFromShare(context, imagePath: imagePath, parsed: d);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.cancel();
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      LockService().updateLastActive();
    } else if (state == AppLifecycleState.resumed) {
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    if (!mounted) return;
    final locked = await LockService().isLocked();
    if (locked && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LockScreen()),
      );
    }
  }

  List<Widget> _bodies(bool isAdmin, bool isCashier) => [
    const DashboardTab(),
    if (isAdmin) const ScanTab(),
    const EntryTab(),
    const LedgerTab(),
    const SuppliersTab(),
    if (!isCashier) const ReportsTab(),
  ];

  void _showAiFab(BuildContext context, bool isAdmin) {
    final p          = context.read<AppProvider>();
    final isCashier  = p.isCashier;
    final entryIdx   = isAdmin ? 2 : 1;
    final reportsIdx = isCashier ? -1 : (isAdmin ? 5 : 4);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('Quick Actions',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _FabChip(
              label: '➕ Quick Entry',
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _tab = entryIdx);
              },
            ),
            _FabChip(
              label: '👥 ${t('customers', p.lang)}',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CustomersScreen()),
                );
              },
            ),
            if (!isCashier)
              _FabChip(
                label: '📊 Quick Report',
                onTap: () {
                  Navigator.pop(ctx);
                  _showQuickReport(context, p);
                },
              ),
            if (!isCashier)
              _FabChip(
                label: '📋 Full Reports',
                onTap: () {
                  Navigator.pop(ctx);
                  if (reportsIdx >= 0) setState(() => _tab = reportsIdx);
                },
              ),
            _FabChip(
              label: '↻ Sync Data',
              onTap: () {
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data refreshed'), behavior: SnackBarBehavior.floating),
                );
              },
            ),
            _FabChip(
              label: '💼 Finance',
              onTap: () {
                Navigator.pop(ctx);
                // Finance & Chit are fully native — always open in-app,
                // same as Construction below (no website fallback).
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FinanceTab()),
                );
              },
            ),
            _FabChip(
              label: '🏗️ Construction',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConstructionScreen()),
                );
              },
            ),
          ]),
        ]),
      ),
    );
  }

  void _showQuickReport(BuildContext context, AppProvider p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _QuickReportSheet(
          businessId: p.businessId,
          shops: Map<String, Shop>.from(p.shops)),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService().signOut();
    if (!mounted) return;
    context.read<AppProvider>().reset();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();

    final isAdmin    = p.isAdmin;
    final isCashier  = p.isCashier;
    final bodies     = _bodies(isAdmin, isCashier);
    final safeTab    = _tab.clamp(0, bodies.length - 1);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        final now = DateTime.now();
        final isSecondPress = _lastBackPress != null &&
            now.difference(_lastBackPress!) <= const Duration(seconds: 2);
        if (isSecondPress) {
          SystemNavigator.pop();
        } else {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: kBg,
        // No AppBar — we render a custom header inside the body column
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomHeader(context, p),
            _buildDeletionBanner(context, p),
            _buildProBanner(context, p),
            _buildGuestBackupBanner(context, p),
            _buildShopChipsRow(context, p),
            Expanded(
              child: IndexedStack(
                index: safeTab,
                children: bodies,
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(p, p.lang, isAdmin, isCashier),
        floatingActionButton: FloatingActionButton(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.bolt_rounded),
          onPressed: () => _showAiFab(context, isAdmin),
        ),
      ),
    );
  }

  // ── Custom white header ────────────────────────────────────────────────────
  Widget _buildCustomHeader(BuildContext context, AppProvider p) {
    final l       = p.lang;
    final profile = p.profile;
    final name    = (profile['name']  as String?) ?? 'User';
    final role    = (profile['role']  as String?) ?? 'owner';

    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // AN logo
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827), // black square (Serif Ledger)
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'AN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // App name + username
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ArthaNote',
                    style: TextStyle(
                      color: kText,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      fontFamily: kSerif,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: kMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Sync button
              Consumer<AppProvider>(builder: (ctx, ap, _) {
                final lastSync = ap.lastSynced;
                final syncAgo = lastSync == null
                    ? null
                    : DateTime.now().difference(lastSync);
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: ap.syncing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))
                      : Icon(Icons.sync,
                          color: syncAgo != null && syncAgo.inHours < 1
                              ? kSecondary
                              : Colors.grey.shade400,
                          size: 18),
                  tooltip: syncAgo == null
                      ? 'Sync data'
                      : syncAgo.inHours < 1
                          ? 'Synced ${syncAgo.inMinutes}m ago'
                          : 'Synced ${syncAgo.inHours}h ago',
                  onPressed: ap.syncing ? null : () => ap.syncNow(),
                );
              }),
              // Own Mode indicator — amber badge replaces the plan badge to avoid overflow
              if (p.isOwnMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Own Mode',
                    style: TextStyle(
                      color: Color(0xFFD97706),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                // Plan badge: Admin / Pro / Free
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _badgeBg(p),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _badgeLabel(p),
                    style: TextStyle(
                      color: _badgeFg(p),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // Green online dot
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: kSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              // QR attendance scanner icon
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrScanScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.qr_code_scanner_rounded, color: kPrimary, size: 22),
                ),
              ),
              const SizedBox(width: 6),
              // Settings: cashier panel in staff mode; full settings for own mode / owner / admin
              if (p.isStaffRole && !p.isOwnMode)
                GestureDetector(
                  onTap: () => _showCashierSettings(context, p),
                  child: const Icon(Icons.person_outline_rounded, color: kText, size: 22),
                )
              else
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: const Icon(Icons.menu, color: kText, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shop chips row ─────────────────────────────────────────────────────────
  // Guest backup banner — shown only in guest mode. Data lives on-device
  // until the user logs in, so this nudges them to log in and back it up.
  Widget _buildGuestBackupBanner(BuildContext context, AppProvider p) {
    if (!p.isGuest) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen())),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCD34D)),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFD97706), size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your data is only on this phone',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF92400E))),
                SizedBox(height: 2),
                Text('Log in to back it up & sync across devices.',
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF92400E), height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Log in',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  // Pro / trial recommendation banner.
  //  • Hidden for paid Pro, admin and staff.
  //  • During the trial's final stretch (<= 14 days) → soft reminder.
  //  • After the trial ends (or free user) → prominent upgrade prompt.
  Widget _buildProBanner(BuildContext context, AppProvider p) {
    // Guests see the "back up your data" banner instead of the Pro prompt.
    if (p.isAdmin || p.isPro || p.isGuest || (p.isStaffRole && !p.isOwnMode)) {
      return const SizedBox.shrink();
    }
    final expired = !p.isInTrial; // trial over (or none) → free with limits
    final daysLeft = p.trialDaysLeft;
    // While comfortably inside the trial, don't nag.
    if (!expired && daysLeft > 14) return const SizedBox.shrink();

    final title = expired
        ? 'Your free trial has ended'
        : 'Trial ends in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}';
    final sub = expired
        ? 'Upgrade to Pro to unlock unlimited shops, reports & more.'
        : 'Upgrade now to keep all features without interruption.';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UpgradeScreen())),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: kGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: kCardShadow,
        ),
        child: Row(children: [
          const Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Upgrade',
                style: TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  // Recovery banner shown when the account is in its 30-day deletion grace
  // window — lets the owner cancel and keep all their data.
  Widget _buildDeletionBanner(BuildContext context, AppProvider p) {
    if (!p.pendingDeletion) return const SizedBox.shrink();
    final d = p.deletionScheduledAt;
    final dateStr =
        d != null ? '${d.day}/${d.month}/${d.year}' : 'soon';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFDC2626), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Account scheduled for deletion',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFFDC2626))),
              Text(
                  'All data is erased on $dateStr. Tap to cancel and keep it.',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      height: 1.3)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () async {
            await p.cancelPendingDeletion();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Deletion cancelled. Your data is safe.'),
                backgroundColor: Color(0xFF065F46),
              ));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF065F46),
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Keep\naccount',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildShopChipsRow(BuildContext context, AppProvider p) {
    final l = p.lang;

    // Cashier: show only their assigned shop chip, no "All" chip, no other shops
    if (p.isCashier && p.staffShop.isNotEmpty) {
      final assignedShop = p.shops[p.staffShop];
      if (assignedShop != null) {
        return Container(
          color: Colors.white,
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              children: [
                _ShopChip(
                  label: assignedShop.name,
                  active: true,
                  isAllChip: false,
                  onTap: () {},
                ),
              ],
            ),
          ),
        );
      }
    }

    return Container(
      color: Colors.white,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          children: [
            // "All" chip
            _ShopChip(
              label: t("all", l),
              active: p.selectedShop.isEmpty,
              isAllChip: true,
              onTap: () => p.setSelectedShop(''),
            ),
            // Individual shop chips. Selecting a Finance/Chit/Construction
            // shop reveals its module as the 2nd bottom-nav tab (next to
            // Dashboard); a one-time coach sheet guides first-time users.
            ...p.shops.values.map((s) {
              final type = s.type.toLowerCase();
              final isModule =
                  type == 'finance' || type == 'chit' || type == 'construction';
              return _ShopChip(
                label: s.name,
                active: p.selectedShop == s.id,
                isAllChip: false,
                onTap: () {
                  p.setSelectedShop(s.id);
                  if (isModule) _maybeShowModuleGuide(type);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── First-time module guide ────────────────────────────────────────────────
  // Shown ONCE per module type, the first time the user selects that shop
  // chip — tells them the module now lives in the bottom bar (2nd tab, next
  // to Dashboard) and how to use it in 3 steps.
  Future<void> _maybeShowModuleGuide(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'slv_mguide_$type';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    if (!mounted) return;

    final (title, steps) = switch (type) {
      'construction' => (
          '🏗️ Construction Ledger',
          [
            '1️⃣  Material & labour செலவுகளை பதிவு செய்யுங்கள்',
            '2️⃣  Site (project) வாரியாக செலவு பாருங்கள்',
            '3️⃣  360° report-ல் மொத்த கணக்கு பாருங்கள்',
          ],
        ),
      'chit' => (
          '🎰 Chit Fund Module',
          [
            '1️⃣  Members-ஐ சேருங்கள்',
            '2️⃣  Monthly collection பதிவு செய்யுங்கள்',
            '3️⃣  Chit auction & defaulters கண்காணியுங்கள்',
          ],
        ),
      _ => (
          '💰 Finance Module',
          [
            '1️⃣  Members-ஐ சேருங்கள்',
            '2️⃣  Monthly collection பதிவு செய்யுங்கள்',
            '3️⃣  Reports & defaulter alerts பாருங்கள்',
          ],
        ),
    };

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  fontFamily: 'serif', color: kText)),
          const SizedBox(height: 6),
          const Text(
            'இந்த module இப்போ கீழே உள்ள bar-ல, Dashboard-க்கு அடுத்த இடத்துல இருக்கு 👇\nIt now sits in the bottom bar — right next to Dashboard.',
            style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 14),
          ...steps.map((st) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(st,
                    style: const TextStyle(
                        fontSize: 13, color: kText, height: 1.4)),
              )),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kMuted,
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('புரிந்தது · Got it',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => type == 'construction'
                          ? const ConstructionScreen()
                          : const FinanceTab()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text('Open now →',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Bottom navigation ──────────────────────────────────────────────────────
  /// 'finance' | 'chit' | 'construction' when the selected shop chip is a
  /// module-type shop — its module then appears as the SECOND nav tab
  /// (Dashboard → Module → …). Null hides the tab (All / normal shops).
  String? _selectedModuleType(AppProvider p) {
    if (p.selectedShop.isEmpty) return null;
    final ty = p.shops[p.selectedShop]?.type.toLowerCase() ?? '';
    return (ty == 'finance' || ty == 'chit' || ty == 'construction') ? ty : null;
  }

  Widget _buildBottomNav(AppProvider p, String l, bool isAdmin, bool isCashier) {
    // Context-aware nav: selecting a Finance/Chit/Construction shop chip
    // surfaces its module right after Dashboard, so the module is always one
    // thumb-tap away while that shop is the user's current "identity".
    final modType   = _selectedModuleType(p);
    final hasModule = modType != null;
    final maxIdx = isCashier ? 3 : (isAdmin ? 5 : 4);
    final bodyTab = _tab.clamp(0, maxIdx);
    // _tab indexes the BODY list; the module tab (nav slot 1) pushes a screen
    // instead, so map body index → nav index around it.
    final navIdx = (hasModule && bodyTab >= 1) ? bodyTab + 1 : bodyTab;

    BottomNavigationBarItem _item(NavIconType type, String label) =>
        BottomNavigationBarItem(
          icon: NavIcon(type: type, active: false),
          activeIcon: NavIcon(type: type, active: true),
          label: label,
        );

    final items = <BottomNavigationBarItem>[
      _item(NavIconType.dashboard, t('dashboard', l)),
      if (hasModule)
        _item(
          modType == 'construction'
              ? NavIconType.construction
              : NavIconType.finance,
          modType == 'construction'
              ? 'Site'
              : (modType == 'chit' ? 'Chit' : 'Finance'),
        ),
      if (isAdmin) _item(NavIconType.scan, t('scan', l)),
      _item(NavIconType.entry, t('entry', l)),
      _item(NavIconType.ledger, t('ledger', l)),
      _item(NavIconType.suppliers, t('suppliers', l)),
      if (!isCashier) _item(NavIconType.reports, t('reports', l)),
    ];

    return BottomNavigationBar(
      currentIndex: navIdx.clamp(0, items.length - 1),
      onTap: (i) {
        if (hasModule && i == 1) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => modType == 'construction'
                  ? const ConstructionScreen()
                  : const FinanceTab()));
          return;
        }
        setState(() => _tab = (hasModule && i > 1) ? i - 1 : i);
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFFA16207), // Serif Ledger gold accent
      unselectedItemColor: const Color(0xFF9CA3AF),
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
      unselectedLabelStyle: const TextStyle(fontSize: 10),
      elevation: 16,
      items: items,
    );
  }

  String _badgeLabel(AppProvider p) {
    if (p.isAdmin) return 'Admin';
    if (p.isStaffRole && !p.isOwnMode) return 'Staff';
    if (p.isPro) return 'Pro';
    if (p.isInTrial) return 'Trial';
    return 'Free';
  }

  Color _badgeBg(AppProvider p) {
    if (p.isAdmin) return const Color(0xFFF3E8FF);
    if (p.isStaffRole && !p.isOwnMode) return const Color(0xFFDBEAFE);
    if (p.isPro) return const Color(0xFFFEF3C7);
    if (p.isInTrial) return const Color(0xFFE0E7FF);
    return const Color(0xFFDCFCE7);
  }

  Color _badgeFg(AppProvider p) {
    if (p.isAdmin) return const Color(0xFF7C3AED);
    if (p.isStaffRole && !p.isOwnMode) return const Color(0xFF1D4ED8);
    if (p.isPro) return const Color(0xFFD97706);
    if (p.isInTrial) return const Color(0xFF4F46E5);
    return const Color(0xFF16A34A);
  }

  void _showCashierSettings(BuildContext context, AppProvider p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CashierSettingsSheet(provider: p, onLogout: _logout),
    );
  }
}

// ── Quick Report Sheet ────────────────────────────────────────────────────────
class _QuickReportSheet extends StatelessWidget {
  final String businessId;
  final Map<String, Shop> shops;
  const _QuickReportSheet({required this.businessId, required this.shops});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Consumer<AppProvider>(
        builder: (ctx, p, _) {
          final all = p.txns;
          final now = DateTime.now();
          final today = DateFormat('yyyy-MM-dd').format(now);
          final weekStart = DateFormat('yyyy-MM-dd')
              .format(now.subtract(Duration(days: now.weekday - 1)));
          final monthStart = DateFormat('yyyy-MM-dd')
              .format(DateTime(now.year, now.month, 1));

          double calcSales(List<Txn> txs) =>
              txs.where((t) => t.type == 'sale').fold(0.0, (s, t) => s + t.amount);
          double calcExp(List<Txn> txs) =>
              txs.where((t) => t.type == 'expense').fold(0.0, (s, t) => s + t.amount);

          final todayTxs  = all.where((t) => DateFormat('yyyy-MM-dd').format(t.date) == today).toList();
          final weekTxs   = all.where((t) => DateFormat('yyyy-MM-dd').format(t.date).compareTo(weekStart) >= 0).toList();
          final monthTxs  = all.where((t) => DateFormat('yyyy-MM-dd').format(t.date).compareTo(monthStart) >= 0).toList();

          final todaySales = calcSales(todayTxs), todayExp = calcExp(todayTxs);
          final weekSales  = calcSales(weekTxs),  weekExp  = calcExp(weekTxs);
          final monthSales = calcSales(monthTxs), monthExp = calcExp(monthTxs);
          final todayNet = todaySales - todayExp;
          final weekNet  = weekSales  - weekExp;
          final monthNet = monthSales - monthExp;

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)),
              ),
              Container(
                color: kPrimary,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  const Icon(Icons.bar_chart, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Quick Report',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                  if (p.syncing)
                    const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text('${all.length} entries', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Period summary grid
                    Row(children: [
                      _PeriodCard('Today', todaySales, todayExp, todayNet, const Color(0xFF065F46), const Color(0xFFF0FDF4), p.currency),
                      const SizedBox(width: 8),
                      _PeriodCard('This Week', weekSales, weekExp, weekNet, const Color(0xFF1D4ED8), const Color(0xFFEFF6FF), p.currency),
                      const SizedBox(width: 8),
                      _PeriodCard('Month', monthSales, monthExp, monthNet, const Color(0xFF7C3AED), const Color(0xFFFDF4FF), p.currency),
                    ]),
                    const SizedBox(height: 16),
                    // Today by shop
                    const Text('Today by Shop',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
                    const SizedBox(height: 8),
                    ...shops.entries.map((e) {
                      final shopId = e.key;
                      final shop   = e.value;
                      final name   = shop.name;
                      final icon   = shop.icon;
                      final stxs   = todayTxs.where((t) => t.shop == shopId).toList();
                      final ss     = calcSales(stxs), se = calcExp(stxs), sn = ss - se;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(children: [
                          Text('$icon', style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: kText, fontSize: 13))),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(p.currency.compact(ss),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kText)),
                            Text('Net ${sn >= 0 ? '+' : ''}${p.currency.compact(sn)}',
                                style: TextStyle(fontSize: 10,
                                    color: sn >= 0 ? kPrimary : kRed,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ]),
                      );
                    }),
                    if (all.isEmpty && !p.syncing)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No data yet. Add entries to see your report.',
                            style: TextStyle(color: kMuted), textAlign: TextAlign.center),
                      )),
                  ],
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final String label;
  final double sales, exp, net;
  final Color accentColor, bgColor;
  final Currency currency;
  const _PeriodCard(this.label, this.sales, this.exp, this.net, this.accentColor, this.bgColor, this.currency);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
            color: accentColor, letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(currency.compact(sales), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: accentColor)),
        Text('Exp: ${currency.compact(exp)}', style: const TextStyle(fontSize: 9, color: kMuted)),
        const SizedBox(height: 2),
        Text('Net ${net >= 0 ? '+' : ''}${currency.compact(net)}',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: net >= 0 ? const Color(0xFF059669) : kRed)),
      ]),
    ),
  );
}

// ── FAB quick-action chip ─────────────────────────────────────────────────────
class _FabChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FabChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: kPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
  );
}

// ── Shop chip widget ──────────────────────────────────────────────────────────
class _ShopChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool isAllChip;
  final VoidCallback onTap;

  const _ShopChip({
    required this.label,
    required this.active,
    required this.isAllChip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: active
            ? (isAllChip ? const Color(0xFF111827) : kPrimary)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? (isAllChip ? const Color(0xFF111827) : kPrimary)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.grey.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

// ── Cashier Settings Sheet ────────────────────────────────────────────────────
class _CashierSettingsSheet extends StatelessWidget {
  final AppProvider provider;
  final VoidCallback onLogout;
  const _CashierSettingsSheet({required this.provider, required this.onLogout});

  static void _showConnectDialog(BuildContext context, AppProvider p) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          bool saving = false;
          return AlertDialog(
            title: const Text('Connect to Employer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'Ask your employer for their Business ID.\n'
                'Owner: Settings → Staff App Access → copy the Business ID.',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Business ID',
                  hintText: 'Paste the ID from your employer',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final bid = ctrl.text.trim();
                        if (bid.isEmpty) return;
                        setS(() => saving = true);
                        Navigator.pop(ctx);
                        await p.setManualBusinessId(bid);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
                child: const Text('Connect',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p        = provider;
    final profile  = p.profile;
    final name     = (profile['name']  as String?) ?? 'Staff';
    final email    = (profile['email'] as String?) ?? '';
    final shopId   = p.staffShop;
    final shop     = p.shops[shopId];
    final shopName = shop?.name ?? shopId;
    final shopIcon = shop?.icon ?? '🏪';
    final attendUrl = 'https://arthanote.com/attend.html'
        '?bid=${p.businessId}&shop=$shopId'
        '&sname=${Uri.encodeComponent(shopName)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'S',
                  style: const TextStyle(
                    color: kPrimary, fontWeight: FontWeight.w800, fontSize: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
                const SizedBox(height: 2),
                Text(email,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.isOwnMode
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p.isOwnMode
                        ? '🏠 My Business · Own Mode'
                        : '$shopIcon $shopName · Cashier',
                    style: TextStyle(
                        color: p.isOwnMode ? const Color(0xFFD97706) : kPrimary,
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ]),
        ),

        const Divider(height: 1, thickness: 1),

        // Staff-mode-only tiles — hidden when viewing own data
        if (!p.isOwnMode) ...[
          ListTile(
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_rounded, color: kPrimary, size: 20),
            ),
            title: const Text('Attendance QR',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Mark attendance — $shopName',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: kMuted),
            onTap: () {
              Navigator.pop(context);
              launchUrl(Uri.parse(attendUrl), mode: LaunchMode.externalApplication);
            },
          ),

          ListTile(
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link_rounded,
                  color: Color(0xFF7C3AED), size: 20),
            ),
            title: const Text('Connect to Employer',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text('Enter employer\'s Business ID',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: kMuted),
            onTap: () {
              Navigator.pop(context);
              _showConnectDialog(context, provider);
            },
          ),
        ],

        // Own Mode toggle
        ListTile(
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: p.isOwnMode
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              p.isOwnMode ? Icons.work_outline_rounded : Icons.dashboard_rounded,
              color: p.isOwnMode ? kPrimary : const Color(0xFFD97706),
              size: 20,
            ),
          ),
          title: Text(
            p.isOwnMode ? 'Back to Staff Mode' : 'My Dashboard',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            p.isOwnMode
                ? 'Return to employer\'s data'
                : 'View your own business data',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          trailing: p.isOwnMode
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('NEW',
                      style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 9,
                          fontWeight: FontWeight.w800)),
                ),
          onTap: () {
            Navigator.pop(context);
            provider.toggleOwnMode();
          },
        ),

        ListTile(
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.logout_rounded, color: kRed, size: 20),
          ),
          title: const Text('Sign Out',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: kRed)),
          subtitle: Text('Log out of staff account',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          onTap: () {
            Navigator.pop(context);
            onLogout();
          },
        ),

        const SizedBox(height: 16),
      ]),
    );
  }
}
