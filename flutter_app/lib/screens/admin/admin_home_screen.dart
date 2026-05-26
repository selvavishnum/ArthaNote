import 'package:flutter/material.dart';
import 'admin_dashboard_tab.dart';
import 'admin_users_tab.dart';
import 'admin_activity_tab.dart';
import 'admin_shops_tab.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: IndexedStack(
        index: _tab,
        children: const [
          AdminDashboardTab(),
          AdminUsersTab(),
          AdminShopsTab(),
          AdminActivityTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDCFCE7),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Color(0xFF065F46)),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: Color(0xFF065F46)),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store, color: Color(0xFF065F46)),
            label: 'Shops',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline, color: Color(0xFF065F46)),
            label: 'Activity',
          ),
        ],
      ),
    );
  }
}
