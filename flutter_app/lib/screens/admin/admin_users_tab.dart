import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});
  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final _svc    = AdminService();
  final _search = TextEditingController();
  String  _filter   = 'all';
  String  _q        = '';
  List<AdminUser> _users    = [];
  bool    _loading  = true;
  bool    _syncing  = false;
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _q = _search.text.toLowerCase()));
    _loadUsers();
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _loadUsers() async {
    // Phase 1: show cache immediately (zero Firestore reads)
    final cached = await _svc.loadUsersFromCache();
    if (cached.isNotEmpty && mounted) {
      setState(() { _users = cached; _loading = false; });
    }
    // Phase 2: sync from Firestore once per day
    if (await _svc.needsSync()) {
      if (mounted) setState(() => _syncing = true);
      try {
        final result = await _svc.syncAll();
        _lastSynced  = await _svc.getLastSyncTime();
        if (mounted) setState(() { _users = result.users; _syncing = false; });
      } catch (_) {
        if (mounted) setState(() => _syncing = false);
      }
    } else {
      _lastSynced = await _svc.getLastSyncTime();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _forceSync() async {
    setState(() => _syncing = true);
    try {
      final result = await _svc.syncAll();
      _lastSynced = await _svc.getLastSyncTime();
      if (mounted) setState(() { _users = result.users; _syncing = false; });
    } catch (_) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _syncLabel() {
    if (_lastSynced == null) return 'Never synced';
    final diff = DateTime.now().difference(_lastSynced!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Row(children: [
              const Text('Users', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
              const Spacer(),
              if (_lastSynced != null && !_syncing)
                Text(_syncLabel(), style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(width: 4),
              if (_syncing)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF065F46)))
              else
                IconButton(
                  icon: const Icon(Icons.sync, color: Color(0xFF065F46), size: 20),
                  tooltip: 'Sync from Firebase',
                  onPressed: _forceSync,
                ),
            ]),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(110),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(children: [
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or email...',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF), size: 20),
                      suffixIcon: _q.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () { _search.clear(); setState(() => _q = ''); })
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    _FilterChip(label: 'All', active: _filter == 'all',
                        onTap: () => setState(() => _filter = 'all')),
                    const SizedBox(width: 8),
                    _FilterChip(label: '⭐ Pro', active: _filter == 'pro',
                        onTap: () => setState(() => _filter = 'pro')),
                  ]),
                ]),
              ),
            ),
          ),
          Builder(builder: (ctx) {
            if (_loading) {
              return const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF065F46))),
              );
            }
            var users = _users;
            if (_filter == 'pro') users = users.where((u) => u.isPro).toList();
            if (_q.isNotEmpty) {
              users = users.where((u) =>
                  u.name.toLowerCase().contains(_q) ||
                  u.email.toLowerCase().contains(_q)).toList();
            }
            if (users.isEmpty) {
              return SliverFillRemaining(
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, size: 48, color: Color(0xFFD1D5DB)),
                  const SizedBox(height: 12),
                  Text(_q.isNotEmpty ? 'No users matching "$_q"' : 'No users yet',
                      style: const TextStyle(color: Color(0xFF6B7280))),
                ])),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _UserCard(user: users[i], svc: _svc),
                  ),
                  childCount: users.length,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _UserCard extends StatefulWidget {
  final AdminUser    user;
  final AdminService svc;
  const _UserCard({required this.user, required this.svc});
  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> with SingleTickerProviderStateMixin {
  bool               _expanded       = false;
  bool               _loadingDetails = false;
  AdminUserDetails?  _details;
  late final AnimationController _anim;
  late final Animation<double>   _rotate;

  @override
  void initState() {
    super.initState();
    _anim   = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _rotate = Tween(begin: 0.0, end: 0.5)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  Future<void> _toggle() async {
    if (!_expanded) {
      setState(() => _expanded = true);
      _anim.forward();
      if (_details == null) {
        setState(() => _loadingDetails = true);
        try {
          final d = await widget.svc.getUserDetails(widget.user.businessId);
          if (mounted) setState(() { _details = d; _loadingDetails = false; });
        } catch (_) {
          if (mounted) setState(() => _loadingDetails = false);
        }
      }
    } else {
      setState(() => _expanded = false);
      _anim.reverse();
    }
  }

  static String _fmtAmt(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  static String _timeAgo(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours   < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1) return '${diff.inHours}h ago';
    if (diff.inDays    < 7) return '${diff.inDays}d ago';
    return DateFormat('d MMM').format(dt);
  }

  Color _avatarColor(String name) {
    const cols = [
      Color(0xFF065F46), Color(0xFF1D4ED8), Color(0xFF7C3AED),
      Color(0xFFDB2777), Color(0xFFD97706), Color(0xFF059669),
    ];
    return cols[name.isEmpty ? 0 : name.codeUnitAt(0) % cols.length];
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final d = _details;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 20, offset: const Offset(0, 4),
        )],
      ),
      child: Column(children: [
        InkWell(
          borderRadius: _expanded
              ? const BorderRadius.vertical(top: Radius.circular(16))
              : BorderRadius.circular(16),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _avatarColor(u.name),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Text(u.initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(u.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF111827)),
                      overflow: TextOverflow.ellipsis)),
                  if (u.isPro) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('PRO', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: Color(0xFFD97706), letterSpacing: 0.5)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(u.email,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              RotationTransition(turns: _rotate,
                  child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF9CA3AF))),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          if (_loadingDetails)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(
                  color: Color(0xFF065F46), strokeWidth: 2)),
            )
          else if (d != null)
            _DetailsSection(details: d, fmtAmt: _fmtAmt, timeAgo: _timeAgo)
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Failed to load details',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
            ),
        ],
      ]),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  final AdminUserDetails           details;
  final String Function(double)    fmtAmt;
  final String Function(DateTime?) timeAgo;
  const _DetailsSection({required this.details, required this.fmtAmt, required this.timeAgo});

  @override
  Widget build(BuildContext context) {
    final d   = details;
    final net = d.totalSales - d.totalExpense;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _MiniStat(label: 'Sales',   value: fmtAmt(d.totalSales),   color: const Color(0xFF059669)),
          const SizedBox(width: 8),
          _MiniStat(label: 'Expense', value: fmtAmt(d.totalExpense), color: const Color(0xFFEF4444)),
          const SizedBox(width: 8),
          _MiniStat(label: 'Net', value: fmtAmt(net),
              color: net >= 0 ? const Color(0xFF065F46) : const Color(0xFFEF4444)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 4, children: [
          _MetaItem(Icons.receipt_long_outlined, '${d.entryCount} entries (90d)'),
          _MetaItem(Icons.calendar_today_outlined, '${d.activeDays} active days'),
          _MetaItem(Icons.access_time, 'Last: ${timeAgo(d.lastActive)}'),
        ]),
        if (d.shops.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _SectionLabel('SHOPS'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6,
            children: d.shops.map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${s['icon']} ${s['name']}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w500)),
            )).toList(),
          ),
        ],
        if (d.last7DaySales.any((v) => v > 0)) ...[
          const SizedBox(height: 14),
          const _SectionLabel('LAST 7 DAYS SALES'),
          const SizedBox(height: 8),
          _Sparkline(values: d.last7DaySales),
        ],
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label; final String value; final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.8), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _MetaItem extends StatelessWidget {
  final IconData icon; final String text;
  const _MetaItem(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
    const SizedBox(width: 4),
    Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
  ]);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
      fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF), letterSpacing: 0.5));
}

class _Sparkline extends StatelessWidget {
  final List<double> values;
  const _Sparkline({required this.values});
  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final now  = DateTime.now();
    const days = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return SizedBox(
      height: 60,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final frac    = maxV > 0 ? (values[i] / maxV).clamp(0.0, 1.0) : 0.0;
          final isToday = i == values.length - 1;
          final dayIdx  = ((now.weekday % 7) - (values.length - 1 - i)) % 7;
          final label   = days[((dayIdx % 7) + 7) % 7];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Flexible(
                  child: FractionallySizedBox(
                    heightFactor: frac > 0 ? frac : 0.05,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isToday
                            ? const Color(0xFF065F46)
                            : frac > 0
                                ? const Color(0xFF065F46).withOpacity(0.3)
                                : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(
                    fontSize: 9,
                    color: isToday ? const Color(0xFF065F46) : const Color(0xFF9CA3AF),
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});
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
          fontSize: 13, fontWeight: FontWeight.w600,
          color: active ? Colors.white : const Color(0xFF6B7280))),
    ),
  );
}
