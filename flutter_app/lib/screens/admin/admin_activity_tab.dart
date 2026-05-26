import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';

class AdminActivityTab extends StatefulWidget {
  const AdminActivityTab({super.key});
  @override
  State<AdminActivityTab> createState() => _AdminActivityTabState();
}

class _AdminActivityTabState extends State<AdminActivityTab> {
  final _svc = AdminService();
  List<AdminActivityEntry> _activity = [];
  String _filter = 'all'; // all / sale / expense / payment
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await _svc.loadActivityFromCache();
    if (mounted) setState(() { _activity = cached; _loading = false; });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await _svc.syncAll();
      final fresh = await _svc.loadActivityFromCache();
      if (mounted) setState(() { _activity = fresh; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var list = _activity;
    if (_filter != 'all') {
      list = list.where((e) => e.type == _filter || (_filter == 'sale' && e.type == 'sales')).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('Activity Log', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          actions: [
            IconButton(
              icon: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF065F46)))
                  : const Icon(Icons.sync, color: Color(0xFF065F46)),
              onPressed: _loading ? null : _refresh,
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(label: 'All', active: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                  const SizedBox(width: 8),
                  _Chip(label: '💰 Sales', active: _filter == 'sale', onTap: () => setState(() => _filter = 'sale')),
                  const SizedBox(width: 8),
                  _Chip(label: '📉 Expense', active: _filter == 'expense', onTap: () => setState(() => _filter = 'expense')),
                  const SizedBox(width: 8),
                  _Chip(label: '💳 Payment', active: _filter == 'payment', onTap: () => setState(() => _filter = 'payment')),
                ]),
              ),
            ),
          ),
        ),
        if (_loading && _activity.isEmpty)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF065F46))))
        else if (list.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text('No activity yet. Tap sync to load.',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final e = list[i];
                  final isFirst = i == 0 || !_sameDay(list[i - 1].date, e.date);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (isFirst) ...[
                      if (i > 0) const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          _dateLabel(e.date),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: Color(0xFF9CA3AF), letterSpacing: 0.5),
                        ),
                      ),
                    ],
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )],
                      ),
                      child: Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _typeColor(e.type).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_typeIcon(e.type), color: _typeColor(e.type), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            e.desc.isNotEmpty ? e.desc : _typeLabel(e.type),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(e.userName, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(
                            _fmtAmt(e.amount),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _typeColor(e.type)),
                          ),
                          const SizedBox(height: 2),
                          Text(DateFormat('HH:mm').format(e.date),
                              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
                        ]),
                      ]),
                    ),
                  ]);
                },
                childCount: list.length,
              ),
            ),
          ),
      ]),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    if (date == today) return 'TODAY';
    if (date == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('d MMM yyyy').format(d).toUpperCase();
  }

  Color _typeColor(String t) {
    if (t == 'sale' || t == 'sales') return const Color(0xFF059669);
    if (t == 'expense') return const Color(0xFFEF4444);
    return const Color(0xFF3B82F6);
  }

  IconData _typeIcon(String t) {
    if (t == 'sale' || t == 'sales') return Icons.trending_up;
    if (t == 'expense') return Icons.trending_down;
    return Icons.swap_horiz;
  }

  String _typeLabel(String t) {
    if (t == 'sale' || t == 'sales') return 'Sale';
    if (t == 'expense') return 'Expense';
    return 'Payment';
  }

  static String _fmtAmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF065F46) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? Colors.white : const Color(0xFF6B7280))),
    ),
  );
}
