import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});
  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  final _svc = AdminService();
  AdminDashboardStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _svc.getDashboardStats();
      if (mounted) setState(() { _stats = stats; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '₹${(v/10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '₹${(v/100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '₹${(v/1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ArthaNote Admin', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
              Text(DateFormat('EEEE, d MMM').format(DateTime.now()),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
            actions: [
              IconButton(
                icon: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF065F46)))
                    : const Icon(Icons.refresh, color: Color(0xFF065F46)),
                onPressed: _loading ? null : _load,
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (_loading && s == null)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFF065F46))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  // ROW 1: Total Users | Active Today
                  Row(children: [
                    Expanded(child: _StatCard(
                      title: 'TOTAL USERS',
                      value: '${s?.totalUsers ?? 0}',
                      icon: Icons.people,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF3B82F6),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(
                      title: 'ACTIVE TODAY',
                      value: '${s?.activeToday ?? 0}',
                      icon: Icons.flash_on,
                      iconBg: const Color(0xFFFEF3C7),
                      iconColor: const Color(0xFFF59E0B),
                      subtitle: 'adding entries',
                    )),
                  ]),
                  const SizedBox(height: 12),

                  // ROW 2: Active This Week | Pro Users
                  Row(children: [
                    Expanded(child: _StatCard(
                      title: 'ACTIVE THIS WEEK',
                      value: '${s?.activeThisWeek ?? 0}',
                      icon: Icons.calendar_view_week,
                      iconBg: const Color(0xFFF3E8FF),
                      iconColor: const Color(0xFF7C3AED),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(
                      title: 'PRO USERS',
                      value: '${s?.proUsers ?? 0}',
                      icon: Icons.star,
                      iconBg: const Color(0xFFFEF3C7),
                      iconColor: const Color(0xFFD97706),
                      subtitle: s?.proUsers != null ? '₹${(s!.proUsers * 99).toString()}/mo MRR' : null,
                    )),
                  ]),
                  const SizedBox(height: 12),

                  // ROW 3: Entries Today | Sales (90d)
                  Row(children: [
                    Expanded(child: _StatCard(
                      title: 'ENTRIES TODAY',
                      value: '${s?.entriesToday ?? 0}',
                      icon: Icons.receipt_long,
                      iconBg: const Color(0xFFDCFCE7),
                      iconColor: const Color(0xFF065F46),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(
                      title: 'SALES (90 DAYS)',
                      value: s != null ? _fmt(s.totalSalesAllTime) : '—',
                      icon: Icons.trending_up,
                      iconBg: const Color(0xFFDCFCE7),
                      iconColor: const Color(0xFF059669),
                    )),
                  ]),
                  const SizedBox(height: 24),

                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: Color(0xFF065F46), size: 18),
                      const SizedBox(width: 10),
                      const Expanded(child: Text(
                        'Tap Users tab to see each user\'s business details and entry history.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF065F46)),
                      )),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String  title;
  final String  value;
  final IconData icon;
  final Color   iconBg;
  final Color   iconColor;
  final String? subtitle;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 20,
          offset: const Offset(0, 4),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title, style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280), letterSpacing: 0.5)),
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
        ]),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(
            fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        ],
      ]),
    );
  }
}
