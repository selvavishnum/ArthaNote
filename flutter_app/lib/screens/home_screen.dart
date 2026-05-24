import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../l10n.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import 'dashboard_tab.dart';
import 'scan_tab.dart';
import 'entry_tab.dart';
import 'ledger_tab.dart';
import 'suppliers_tab.dart';
import 'reports_tab.dart';
import 'finance_tab.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  List<Widget> _bodies(bool isAdmin) => [
    const DashboardTab(),
    if (isAdmin) const ScanTab(),
    const EntryTab(),
    const LedgerTab(),
    const SuppliersTab(),
    const ReportsTab(),
  ];

  void _showAiFab(BuildContext context, bool isAdmin) {
    final entryIdx   = isAdmin ? 2 : 1;
    final reportsIdx = isAdmin ? 5 : 4;
    final p          = context.read<AppProvider>();
    final useNativeFinance = _showFinanceTab(p);

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
              label: '📊 View Reports',
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _tab = reportsIdx);
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
                if (useNativeFinance) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceTab()),
                  );
                } else {
                  launchUrl(
                    Uri.parse('https://selvavishnum.github.io/Kannakupilai/finance.html'),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
          ]),
        ]),
      ),
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
    final showFinance = _showFinanceTab(p);
    final bodies     = _bodies(isAdmin);
    final safeTab    = _tab.clamp(0, bodies.length - 1);

    return Scaffold(
      backgroundColor: kBg,
      // No AppBar — we render a custom header inside the body column
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCustomHeader(context, p),
          _buildShopChipsRow(context, p),
          Expanded(
            child: IndexedStack(
              index: safeTab,
              children: bodies,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(p.lang, isAdmin, showFinance),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.bolt_rounded),
        onPressed: () => _showAiFab(context, isAdmin),
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
                  color: kPrimary,
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
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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
              const SizedBox(width: 8),
              // Language toggle pill
              GestureDetector(
                onTap: () => p.setLang(l == 'en' ? 'ta' : 'en'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Text(
                    l == 'en' ? 'தமிழ்' : 'EN',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Hamburger → Settings
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
  Widget _buildShopChipsRow(BuildContext context, AppProvider p) {
    final l = p.lang;

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
              label: '🏠 ${t("all", l)}',
              active: p.selectedShop.isEmpty,
              isAllChip: true,
              onTap: () => p.setSelectedShop(''),
            ),
            // Individual shop chips
            ...p.shops.values.map((s) => _ShopChip(
              label: '${s.icon} ${s.name}',
              active: p.selectedShop == s.id,
              isAllChip: false,
              onTap: () => p.setSelectedShop(s.id),
            )),
          ],
        ),
      ),
    );
  }

  // ── Check if Finance tab should be shown ──────────────────────────────────
  bool _showFinanceTab(AppProvider p) {
    return p.isFinanceUser;
  }

  // ── Bottom navigation ──────────────────────────────────────────────────────
  Widget _buildBottomNav(String l, bool isAdmin, bool showFinance) {
    final maxIdx = showFinance ? (isAdmin ? 6 : 5) : (isAdmin ? 5 : 4);
    return BottomNavigationBar(
      currentIndex: _tab.clamp(0, maxIdx),
      onTap: (i) {
        // Finance tab: navigate to FinanceTab screen
        final financeIdx = isAdmin ? 6 : 5;
        if (showFinance && i == financeIdx) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FinanceTab()),
          );
          return;
        }
        setState(() => _tab = i);
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: kPrimary,
      unselectedItemColor: const Color(0xFF9CA3AF),
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
      unselectedLabelStyle: const TextStyle(fontSize: 10),
      elevation: 16,
      items: [
        BottomNavigationBarItem(
          icon: const Icon(Icons.dashboard_outlined),
          activeIcon: const Icon(Icons.dashboard),
          label: t('dashboard', l),
        ),
        if (isAdmin)
          BottomNavigationBarItem(
            icon: const Icon(Icons.document_scanner_outlined),
            activeIcon: const Icon(Icons.document_scanner),
            label: t('scan', l),
          ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.add_circle_outline),
          activeIcon: const Icon(Icons.add_circle),
          label: t('entry', l),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.receipt_long_outlined),
          activeIcon: const Icon(Icons.receipt_long),
          label: t('ledger', l),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.people_outline),
          activeIcon: const Icon(Icons.people),
          label: t('suppliers', l),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.bar_chart_outlined),
          activeIcon: const Icon(Icons.bar_chart),
          label: t('reports', l),
        ),
        if (showFinance)
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            activeIcon: const Icon(Icons.account_balance_wallet),
            label: 'Finance',
          ),
      ],
    );
  }

  String _badgeLabel(AppProvider p) {
    if (p.isAdmin) return 'Admin';
    if (p.profile['pro'] == true) return 'Pro';
    return 'Free';
  }

  Color _badgeBg(AppProvider p) {
    if (p.isAdmin) return const Color(0xFFF3E8FF);
    if (p.profile['pro'] == true) return const Color(0xFFFEF3C7);
    return const Color(0xFFDCFCE7);
  }

  Color _badgeFg(AppProvider p) {
    if (p.isAdmin) return const Color(0xFF7C3AED);
    if (p.profile['pro'] == true) return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }
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
