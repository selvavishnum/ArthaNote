import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';

class AdminShopsTab extends StatefulWidget {
  const AdminShopsTab({super.key});
  @override
  State<AdminShopsTab> createState() => _AdminShopsTabState();
}

class _AdminShopsTabState extends State<AdminShopsTab> {
  final _svc = AdminService();
  List<Map<String, dynamic>> _shops = [];
  String _sort = 'active'; // active / name / sales
  String _filterType = 'all'; // all / personal / finance / vegetables / etc
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final shops = await _svc.getAggregatedShops();
    if (mounted) setState(() { _shops = shops; _loading = false; });
  }

  List<Map<String, dynamic>> _sorted() {
    var list = List<Map<String, dynamic>>.from(_shops);
    if (_filterType != 'all') {
      list = list.where((s) => (s['type'] as String? ?? '') == _filterType).toList();
    }
    switch (_sort) {
      case 'active':
        list.sort((a, b) {
          final da = a['lastActive'] != null ? DateTime.tryParse(a['lastActive'] as String) : null;
          final db = b['lastActive'] != null ? DateTime.tryParse(b['lastActive'] as String) : null;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      case 'sales':
        list.sort((a, b) => ((b['totalSales'] as num?) ?? 0).compareTo((a['totalSales'] as num?) ?? 0));
      case 'name':
        list.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
    }
    return list;
  }

  static String _timeAgo(String? iso) {
    if (iso == null) return 'Never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1) return '${diff.inHours}h ago';
    if (diff.inDays    < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  static String _fmtAmt(num v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final list = _sorted();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text('Shops (${_shops.length})', style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          actions: [
            IconButton(
              icon: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF065F46)))
                  : const Icon(Icons.sync, color: Color(0xFF065F46)),
              onPressed: _loading ? null : _load,
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
                  const Text('Sort:', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  const SizedBox(width: 8),
                  _Chip2(label: '🕐 Active', active: _sort == 'active', onTap: () => setState(() => _sort = 'active')),
                  const SizedBox(width: 6),
                  _Chip2(label: '💰 Sales', active: _sort == 'sales', onTap: () => setState(() => _sort = 'sales')),
                  const SizedBox(width: 6),
                  _Chip2(label: 'A–Z', active: _sort == 'name', onTap: () => setState(() => _sort = 'name')),
                  const SizedBox(width: 12),
                  const Text('|', style: TextStyle(color: Color(0xFFE5E7EB))),
                  const SizedBox(width: 12),
                  _Chip2(label: 'All Types', active: _filterType == 'all', onTap: () => setState(() => _filterType = 'all')),
                  const SizedBox(width: 6),
                  _Chip2(label: '👤 Personal', active: _filterType == 'personal', onTap: () => setState(() => _filterType = 'personal')),
                  const SizedBox(width: 6),
                  _Chip2(label: '💰 Finance', active: _filterType == 'finance', onTap: () => setState(() => _filterType = 'finance')),
                  const SizedBox(width: 6),
                  _Chip2(label: '🥬 Vegeta.', active: _filterType == 'vegetables', onTap: () => setState(() => _filterType = 'vegetables')),
                ]),
              ),
            ),
          ),
        ),
        if (_loading && _shops.isEmpty)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF065F46))))
        else if (list.isEmpty)
          SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.store_outlined, size: 48, color: Color(0xFFD1D5DB)),
            const SizedBox(height: 12),
            const Text('No shops loaded. Expand user cards first to load details.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF065F46), foregroundColor: Colors.white),
            ),
          ])))
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final s = list[i];
                  final name    = s['name']      as String? ?? 'Unnamed';
                  final icon    = s['icon']      as String? ?? '🏪';
                  final type    = s['type']      as String? ?? '';
                  final owner   = s['userName']  as String? ?? '';
                  final lastAct = _timeAgo(s['lastActive'] as String?);
                  final sales   = (s['totalSales'] as num?) ?? 0;
                  final entries = (s['entryCount'] as int?) ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      )],
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                        const SizedBox(height: 2),
                        Row(children: [
                          Text(owner, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                          const Text(' · ', style: TextStyle(color: Color(0xFFD1D5DB))),
                          Text(type, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                        ]),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_fmtAmt(sales),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
                        const SizedBox(height: 2),
                        Text('$entries entries', style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(lastAct, style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
                        ),
                      ]),
                    ]),
                  );
                },
                childCount: list.length,
              ),
            ),
          ),
      ]),
    );
  }
}

class _Chip2 extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _Chip2({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF065F46) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: active ? Colors.white : const Color(0xFF6B7280))),
    ),
  );
}
