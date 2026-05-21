import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import 'login_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  // IndexedStack preserves scroll state across tab switches
  static const _bodies = [
    DashboardTab(),
    ScanTab(),
    EntryTab(),
    LedgerTab(),
    SuppliersTab(),
    ReportsTab(),
  ];

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
              index: _tab,
              children: _bodies,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(p.lang),
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
              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatRole(role),
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
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

  // ── Bottom navigation ──────────────────────────────────────────────────────
  Widget _buildBottomNav(String l) => BottomNavigationBar(
    currentIndex: _tab,
    onTap: (i) => setState(() => _tab = i),
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
    ],
  );

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'owner':   return 'Admin';
      case 'manager': return 'Manager';
      case 'cashier': return 'Cashier';
      default:        return role.isEmpty ? 'Admin' : _capitalize(role);
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
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
