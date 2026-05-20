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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _tabs = [
    DashboardTab(),
    LedgerTab(),
    SuppliersTab(),
    ReportsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    final titles = [t('dashboard', l), t('ledger', l), t('suppliers', l), t('reports', l)];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          // Language toggle
          IconButton(
            icon: Text(l == 'en' ? 'தமிழ்' : 'EN', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            onPressed: () => p.setLang(l == 'en' ? 'ta' : 'en'),
          ),
          // Settings
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) async {
              if (v == 'logout') {
                await AuthService().signOut();
                p.reset();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'logout', child: Row(children: [
                const Icon(Icons.logout, size: 18, color: kRed), const SizedBox(width: 10),
                Text(t('logout', l)),
              ])),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: _tabs),
      floatingActionButton: (_tab == 0 || _tab == 1)
          ? FloatingActionButton(
              heroTag: 'add_entry',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EntryScreen())),
              backgroundColor: kPrimary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.dashboard_outlined), activeIcon: const Icon(Icons.dashboard), label: t('dashboard', l)),
          BottomNavigationBarItem(icon: const Icon(Icons.receipt_long_outlined), activeIcon: const Icon(Icons.receipt_long), label: t('ledger', l)),
          BottomNavigationBarItem(icon: const Icon(Icons.people_outline), activeIcon: const Icon(Icons.people), label: t('suppliers', l)),
          BottomNavigationBarItem(icon: const Icon(Icons.bar_chart_outlined), activeIcon: const Icon(Icons.bar_chart), label: t('reports', l)),
        ],
      ),
    );
  }
}
