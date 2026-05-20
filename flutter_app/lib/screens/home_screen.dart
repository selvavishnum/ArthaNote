import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import 'dashboard_tab.dart';
import 'entry_screen.dart';
import 'ledger_tab.dart';
import 'suppliers_tab.dart';
import 'reports_tab.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  // IndexedStack preserves state (scroll positions) across tab switches
  static const _bodies = [
    DashboardTab(),
    LedgerTab(),
    SuppliersTab(),
    ReportsTab(),
  ];

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Logout'),
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
    final l = p.lang;

    final titles = [
      t('dashboard', l),
      t('ledger', l),
      t('suppliers', l),
      t('reports', l),
    ];

    return Scaffold(
      appBar: _buildAppBar(titles[_tab], l, p),
      body: IndexedStack(index: _tab, children: _bodies),
      floatingActionButton: (_tab == 0 || _tab == 1)
          ? FloatingActionButton(
              heroTag: 'home_fab_add',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EntryScreen()),
              ),
              backgroundColor: kPrimary,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      bottomNavigationBar: _buildBottomNav(l),
    );
  }

  PreferredSizeWidget _buildAppBar(String title, String l, AppProvider p) =>
      AppBar(
        title: Text(title),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: kGradient),
        ),
        actions: [
          // Language toggle
          TextButton(
            onPressed: () => p.setLang(l == 'en' ? 'ta' : 'en'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(
              l == 'en' ? 'தமிழ்' : 'EN',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
          // More menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) async {
              if (v == 'logout') await _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  const Icon(Icons.logout, size: 18, color: kRed),
                  const SizedBox(width: 10),
                  Text(t('logout', l),
                      style: const TextStyle(color: kRed, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ],
      );

  Widget _buildBottomNav(String l) => BottomNavigationBar(
    currentIndex: _tab,
    onTap: (i) => setState(() => _tab = i),
    items: [
      BottomNavigationBarItem(
        icon: const Icon(Icons.dashboard_outlined),
        activeIcon: const Icon(Icons.dashboard),
        label: t('dashboard', l),
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
}
