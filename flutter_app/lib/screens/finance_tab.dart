import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../providers/app_provider.dart';
import '../models/fc_member.dart';
import '../models/fc_payment.dart';
import '../models/fc_chit.dart';
import '../services/fc_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtAmt(double v) {
  if (v >= 1e6) return '₹${(v / 1e6).toStringAsFixed(1)}L';
  if (v >= 1e3) return '₹${(v / 1e3).toStringAsFixed(1)}K';
  final formatted = NumberFormat('#,##,##0.##', 'en_IN').format(v);
  return '₹$formatted';
}

String _nowPeriod(String frequency) => periodKey(DateTime.now(), frequency);
String _nowYYYYMM() => DateFormat('yyyy-MM').format(DateTime.now());

// ── Finance Tab root ──────────────────────────────────────────────────────────

class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});
  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tc;
  String _selectedMonth = _nowYYYYMM();
  final _svc = FcService();

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _prevM() => setState(() => _selectedMonth = prevPeriod(_selectedMonth, 'monthly'));
  void _nextM() => setState(() => _selectedMonth = nextPeriod(_selectedMonth, 'monthly'));

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text('Finance & Chit Fund',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Reports',
            onPressed: () => _showReportsSheet(context, p),
          ),
        ],
        bottom: TabBar(
          controller: _tc,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Members'),
            Tab(text: 'Collections'),
            Tab(text: 'Chit Fund'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tc,
        children: [
          _OverviewTab(
            svc:           _svc,
            businessId:    p.businessId,
            selectedMonth: _selectedMonth,
            onPrev:        _prevM,
            onNext:        _nextM,
          ),
          _MembersTab(svc: _svc, businessId: p.businessId),
          _CollectionsTab(
            svc:        _svc,
            businessId: p.businessId,
          ),
          _ChitFundTab(svc: _svc, businessId: p.businessId),
        ],
      ),
    );
  }

  // ── Reports bottom sheet ──────────────────────────────────────────────────
  void _showReportsSheet(BuildContext context, AppProvider p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _ReportsSheet(
        svc:        _svc,
        businessId: p.businessId,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final FcService svc;
  final String    businessId;
  final String    selectedMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _OverviewTab({
    required this.svc,
    required this.businessId,
    required this.selectedMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FCMember>>(
      stream: svc.memberStream(businessId),
      builder: (ctx, mSnap) {
        final members = mSnap.data ?? [];
        return StreamBuilder<List<FCPayment>>(
          stream: svc.paymentStream(businessId, selectedMonth),
          builder: (ctx, pSnap) {
            final payments = pSnap.data ?? [];
            return _buildBody(context, members, payments);
          },
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<FCMember> members,
      List<FCPayment> payments) {
    final totalDue       = members.fold(0.0, (s, m) => s + m.amount);
    final totalCollected = payments.fold(0.0, (s, p) => s + p.amount);
    final totalPending   = (totalDue - totalCollected).clamp(0.0, double.infinity);
    final pct = totalDue > 0 ? (totalCollected / totalDue).clamp(0.0, 1.0) : 0.0;

    final paidIds    = payments.map((p) => p.memberId).toSet();
    final defaulters = members.where((m) => !paidIds.contains(m.id)).toList();

    final recentPayments = [...payments]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent5 = recentPayments.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Month selector
        _MonthSelector(
            month: selectedMonth, onPrev: onPrev, onNext: onNext),
        const SizedBox(height: 14),

        // 3 stat cards
        Row(children: [
          Expanded(
            child: _StatCard(
              label: 'Collected',
              value: _fmtAmt(totalCollected),
              color: kSecondary,
              icon: Icons.check_circle_outline,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Pending',
              value: _fmtAmt(totalPending),
              color: kRed,
              icon: Icons.timer_outlined,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: 'Members',
              value: '${members.length}',
              color: kPrimary,
              icon: Icons.people_outline,
            ),
          ),
        ]),
        const SizedBox(height: 14),

        // Progress bar
        _ProgressCard(pct: pct, collected: totalCollected, total: totalDue),
        const SizedBox(height: 14),

        // Defaulters
        _SectionHeader(
          title: 'Defaulters',
          trailing: '${defaulters.length} pending',
        ),
        if (defaulters.isEmpty)
          _EmptyTile(icon: Icons.celebration, text: 'All members paid!')
        else
          ...defaulters.map((m) => _DefaulterTile(member: m)),
        const SizedBox(height: 14),

        // Recent payments
        _SectionHeader(
          title: 'Recent Payments',
          trailing: '${recent5.length} shown',
        ),
        if (recent5.isEmpty)
          _EmptyTile(icon: Icons.receipt_long_outlined, text: 'No payments yet')
        else
          ...recent5.map((p) {
            final member = _memberById(members, p.memberId);
            return _PaymentTile(payment: p, memberName: member?.name ?? '—');
          }),
      ],
    );
  }

  FCMember? _memberById(List<FCMember> members, String id) {
    try {
      return members.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — MEMBERS
// ═══════════════════════════════════════════════════════════════════════════════

class _MembersTab extends StatelessWidget {
  final FcService svc;
  final String    businessId;
  const _MembersTab({required this.svc, required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: StreamBuilder<List<FCMember>>(
        stream: svc.memberStream(businessId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: kPrimary));
          }
          final members = snap.data ?? [];
          if (members.isEmpty) {
            return _FullEmptyState(
              icon: Icons.people_outline,
              title: 'No members yet',
              subtitle: 'Tap + to add your first member',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
            itemCount: members.length,
            itemBuilder: (_, i) => _MemberCard(
              member: members[i],
              svc:    svc,
              businessId: businessId,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add_outlined),
        onPressed: () => _showAddMemberSheet(context),
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _AddMemberSheet(svc: svc, businessId: businessId),
    );
  }
}

// ─── Member card ──────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final FCMember  member;
  final FcService svc;
  final String    businessId;
  const _MemberCard(
      {required this.member, required this.svc, required this.businessId});

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Member?'),
        content: Text(
            'This will permanently delete "${member.name}". '
            'Payment history will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await svc.deleteMember(member.id);
            },
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) =>
          _MemberDetailSheet(member: member, svc: svc, businessId: businessId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupColor = _groupColor(member.group);
    return Dismissible(
      key: Key(member.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: kRed.withOpacity(0.1),
        child: const Icon(Icons.delete_outline, color: kRed),
      ),
      confirmDismiss: (_) async {
        _confirmDelete(context);
        return false;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: groupColor.withOpacity(0.15),
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: groupColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    if (member.phone.isNotEmpty)
                      Text(member.phone,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_fmtAmt(member.amount)}/${member.frequency[0]}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: kPrimary),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _GroupBadge(group: member.group),
                    if (member.loanAmount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kAmber.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '₹${(member.loanAmount / 1000).toStringAsFixed(0)}K loan',
                          style: const TextStyle(color: kAmber, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Color _groupColor(String group) {
    switch (group) {
      case 'chit':    return const Color(0xFF7C3AED);
      case 'both':    return kAccent;
      default:        return kPrimary;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — COLLECTIONS (per-frequency period navigation)
// ═══════════════════════════════════════════════════════════════════════════════

class _CollectionsTab extends StatefulWidget {
  final FcService svc;
  final String    businessId;

  const _CollectionsTab({required this.svc, required this.businessId});

  @override
  State<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<_CollectionsTab> {
  // Active frequency filter for the collections view
  String _freqFilter = 'daily'; // 'daily' | 'weekly' | 'monthly'
  late String _period;

  @override
  void initState() {
    super.initState();
    _period = _nowPeriod(_freqFilter);
  }

  void _prev() => setState(() => _period = prevPeriod(_period, _freqFilter));
  void _next() => setState(() => _period = nextPeriod(_period, _freqFilter));

  void _setFreq(String f) => setState(() {
    _freqFilter = f;
    _period = _nowPeriod(f);
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FCMember>>(
      stream: widget.svc.memberStream(widget.businessId),
      builder: (ctx, mSnap) {
        final allMembers = mSnap.data ?? [];
        // Show only members matching the active frequency
        final members = allMembers.where((m) => m.frequency == _freqFilter).toList();
        return StreamBuilder<List<FCPayment>>(
          stream: widget.svc.paymentStream(widget.businessId, _period),
          builder: (ctx, pSnap) {
            final payments = pSnap.data ?? [];
            return _buildBody(context, allMembers, members, payments);
          },
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<FCMember> allMembers,
      List<FCMember> members, List<FCPayment> payments) {
    final paidIds        = payments.map((p) => p.memberId).toSet();
    final paidCount      = members.where((m) => paidIds.contains(m.id)).length;
    final totalDue       = members.fold(0.0, (s, m) => s + m.amount);
    final totalCollected = payments.fold(0.0, (s, p) => s + p.amount);

    return Column(
      children: [
        // Frequency filter chips
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            for (final f in ['daily', 'weekly', 'monthly'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FreqChip(
                  label: f[0].toUpperCase() + f.substring(1),
                  active: _freqFilter == f,
                  onTap: () => _setFreq(f),
                ),
              ),
          ]),
        ),
        // Period selector + summary
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PeriodSelector(
                label: formatPeriodLabel(_period, _freqFilter),
                onPrev: _prev,
                onNext: _next,
              ),
              const SizedBox(height: 8),
              Text(
                '$paidCount of ${members.length} paid  ·  '
                '${_fmtAmt(totalCollected)} of ${_fmtAmt(totalDue)}',
                style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: allMembers.isEmpty
              ? const _FullEmptyState(
                  icon: Icons.people_outline,
                  title: 'No members yet',
                  subtitle: 'Add members first from the Members tab',
                )
              : members.isEmpty
                  ? _FullEmptyState(
                      icon: Icons.calendar_today_outlined,
                      title: 'No ${_freqFilter} members',
                      subtitle: 'Add members with "$_freqFilter" frequency',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                      itemCount: members.length,
                      itemBuilder: (_, i) {
                        final member  = members[i];
                        final payment = _paymentFor(payments, member.id);
                        return _CollectionMemberRow(
                          member:     member,
                          payment:    payment,
                          svc:        widget.svc,
                          businessId: widget.businessId,
                          period:     _period,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  FCPayment? _paymentFor(List<FCPayment> payments, String memberId) {
    try { return payments.firstWhere((p) => p.memberId == memberId); }
    catch (_) { return null; }
  }
}

// ─── Collection row per member ────────────────────────────────────────────────

class _CollectionMemberRow extends StatelessWidget {
  final FCMember   member;
  final FCPayment? payment;
  final FcService  svc;
  final String     businessId;
  final String     period;

  const _CollectionMemberRow({
    required this.member,
    required this.payment,
    required this.svc,
    required this.businessId,
    required this.period,
  });

  void _showRecordPaymentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _RecordPaymentSheet(
        svc:        svc,
        businessId: businessId,
        member:     member,
        period:     period,
      ),
    );
  }

  void _showPaymentDetail(BuildContext context) {
    final p = payment!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment — ${member.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('Month', month),
            _DetailRow('Amount', _fmtAmt(p.amount)),
            _DetailRow('Mode', p.mode.toUpperCase()),
            if (p.note.isNotEmpty) _DetailRow('Note', p.note),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await svc.deletePayment(p.id);
            },
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Delete'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = payment != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: (isPaid ? kSecondary : kRed).withOpacity(0.12),
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: isPaid ? kSecondary : kRed,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                if (member.phone.isNotEmpty)
                  Text(member.phone,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
          if (isPaid)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('✅ ${_fmtAmt(payment!.amount)}',
                    style: const TextStyle(
                        color: kSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showPaymentDetail(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kSecondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('View',
                        style: TextStyle(
                            color: kSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('⏳ Due ${_fmtAmt(member.amount)}/${member.frequency[0]}',
                    style: const TextStyle(
                        color: kRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showRecordPaymentSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Record',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4 — CHIT FUND
// ═══════════════════════════════════════════════════════════════════════════════

class _ChitFundTab extends StatelessWidget {
  final FcService svc;
  final String    businessId;
  const _ChitFundTab({required this.svc, required this.businessId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: StreamBuilder<List<FCChit>>(
        stream: svc.chitStream(businessId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: kPrimary));
          }
          final chits = snap.data ?? [];
          if (chits.isEmpty) {
            return const _FullEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No Chit Groups yet',
              subtitle: 'Tap + to create your first chit group',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
            itemCount: chits.length,
            itemBuilder: (_, i) =>
                _ChitCard(chit: chits[i], svc: svc, businessId: businessId),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
        onPressed: () => _showAddChitSheet(context),
      ),
    );
  }

  void _showAddChitSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) =>
          _AddChitSheet(svc: svc, businessId: businessId),
    );
  }
}

// ─── Chit card ────────────────────────────────────────────────────────────────

class _ChitCard extends StatelessWidget {
  final FCChit    chit;
  final FcService svc;
  final String    businessId;
  const _ChitCard(
      {required this.chit, required this.svc, required this.businessId});

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chit Group?'),
        content: Text('Delete "${chit.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await svc.deleteChit(chit.id);
            },
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRecordPrize(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _RecordPrizeSheet(chit: chit, svc: svc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final curMo = chit.currentMonth(now);

    return Dismissible(
      key: Key(chit.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: kRed.withOpacity(0.1),
        child: const Icon(Icons.delete_outline, color: kRed),
      ),
      confirmDismiss: (_) async {
        _confirmDelete(context);
        return false;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet,
                      size: 16, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(chit.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18, color: kMuted),
                  onSelected: (v) {
                    if (v == 'delete') _confirmDelete(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 16, color: kRed),
                        SizedBox(width: 10),
                        Text('Delete Group',
                            style: TextStyle(color: kRed)),
                      ]),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 10),

              // Stats row
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  _ChitStat(
                    label: 'Members',
                    value: '${chit.memberCount}',
                  ),
                  _ChitDivider(),
                  _ChitStat(
                    label: 'Per Member',
                    value: _fmtAmt(chit.amount),
                  ),
                  _ChitDivider(),
                  _ChitStat(
                    label: 'Monthly Total',
                    value: _fmtAmt(chit.monthlyTotal),
                  ),
                ]),
              ),
              const SizedBox(height: 10),

              // Duration progress
              Row(children: [
                const Icon(Icons.calendar_month_outlined,
                    size: 14, color: kMuted),
                const SizedBox(width: 6),
                Text(
                  'Month $curMo of ${chit.months}  ·  starts ${chit.startMonth}',
                  style: const TextStyle(color: kMuted, fontSize: 11),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: chit.months > 0 ? curMo / chit.months : 0,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF7C3AED)),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),

              // Prizes list
              if (chit.prizes.isNotEmpty) ...[
                const Text('Prize Winners',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: kMuted)),
                const SizedBox(height: 6),
                ...chit.prizes.map((pr) => _PrizeTile(prize: pr)),
                const SizedBox(height: 8),
              ],

              // Record prize button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.emoji_events_outlined, size: 16),
                  label: const Text("Record This Month's Prize"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    minimumSize: const Size(0, 40),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _showRecordPrize(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEETS
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Add Member Sheet ─────────────────────────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  final FcService svc;
  final String    businessId;
  const _AddMemberSheet({required this.svc, required this.businessId});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _nameCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _amtCtrl       = TextEditingController();
  final _loanAmtCtrl   = TextEditingController();
  String _group        = 'finance';
  String _frequency    = 'daily';
  bool   _saving       = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _amtCtrl.dispose();
    _loanAmtCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final freqLabels = {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly'};
    final amtLabel = 'Amount ₹ / ${freqLabels[_frequency] ?? ''}';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        const Row(children: [
          _CircleIcon(icon: Icons.person_add_outlined, color: kPrimary),
          SizedBox(width: 12),
          Text('Add Member',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: kPrimary)),
        ]),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Member Name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (optional)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 14),
        // Collection Frequency
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Collection Frequency',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kMuted)),
            const SizedBox(height: 8),
            Row(children: [
              for (final f in ['daily', 'weekly', 'monthly'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FreqChip(
                    label: freqLabels[f]!,
                    active: _frequency == f,
                    onTap: () => setState(() => _frequency = f),
                  ),
                ),
            ]),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _amtCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: amtLabel,
            prefixIcon: const Icon(Icons.payments_outlined),
            hintText: _frequency == 'daily' ? 'e.g. 100' : _frequency == 'weekly' ? 'e.g. 700' : 'e.g. 3000',
          ),
        ),
        const SizedBox(height: 12),
        // Loan amount (finance only)
        if (_group == 'finance' || _group == 'both') ...[
          TextFormField(
            controller: _loanAmtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Loan Amount Given ₹ (optional)',
              prefixIcon: Icon(Icons.account_balance_outlined),
              hintText: 'e.g. 10000',
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Group chips
        Row(children: [
          const Text('Group:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kMuted)),
          const SizedBox(width: 10),
          _GroupChip(
            label: 'Finance',
            active: _group == 'finance',
            color: kPrimary,
            onTap: () => setState(() => _group = 'finance'),
          ),
          const SizedBox(width: 8),
          _GroupChip(
            label: 'Chit',
            active: _group == 'chit',
            color: const Color(0xFF7C3AED),
            onTap: () => setState(() => _group = 'chit'),
          ),
          const SizedBox(width: 8),
          _GroupChip(
            label: 'Both',
            active: _group == 'both',
            color: kAccent,
            onTap: () => setState(() => _group = 'both'),
          ),
        ]),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    if (_nameCtrl.text.trim().isEmpty) return;
                    final amt  = double.tryParse(_amtCtrl.text.trim()) ?? 0;
                    final loan = double.tryParse(_loanAmtCtrl.text.trim()) ?? 0;
                    setState(() => _saving = true);
                    await widget.svc.addMember(FCMember(
                      id:         '',
                      businessId: widget.businessId,
                      name:       _nameCtrl.text.trim(),
                      phone:      _phoneCtrl.text.trim(),
                      amount:     amt,
                      loanAmount: loan,
                      frequency:  _frequency,
                      group:      _group,
                      joinMonth:  _nowYYYYMM(),
                      createdAt:  DateTime.now(),
                    ));
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Save Member', style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ─── Member Detail Sheet ──────────────────────────────────────────────────────

class _MemberDetailSheet extends StatelessWidget {
  final FCMember  member;
  final FcService svc;
  final String    businessId;
  const _MemberDetailSheet(
      {required this.member, required this.svc, required this.businessId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FCPayment>>(
      stream: svc.memberPaymentStream(businessId, member.id),
      builder: (ctx, snap) {
        final payments  = snap.data ?? [];
        final totalPaid = payments.fold(0.0, (s, p) => s + p.amount);
        // Months since join
        final joinParts = member.joinMonth.split('-');
        final now       = DateTime.now();
        int monthsActive = 1;
        if (joinParts.length == 2) {
          final jy = int.tryParse(joinParts[0]) ?? now.year;
          final jm = int.tryParse(joinParts[1]) ?? now.month;
          monthsActive =
              ((now.year - jy) * 12 + (now.month - jm) + 1).clamp(1, 9999);
        }
        final totalDue = member.amount * monthsActive;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, ctrl) => Padding(
            padding:
                const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 16),
                Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: kPrimary.withOpacity(0.1),
                    child: Text(
                      member.name.isNotEmpty
                          ? member.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        if (member.phone.isNotEmpty)
                          Text(member.phone,
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                  _GroupBadge(group: member.group),
                ]),
                const SizedBox(height: 14),
                // Frequency badge
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${member.frequency[0].toUpperCase()}${member.frequency.substring(1)} · ${_fmtAmt(member.amount)}/cycle',
                      style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                  if (member.loanAmount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kAmber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Loan: ${_fmtAmt(member.loanAmount)}',
                        style: const TextStyle(color: kAmber, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
                // Summary row
                Row(children: [
                  Expanded(
                      child: _StatCard(
                          label: 'Total Paid',
                          value: _fmtAmt(totalPaid),
                          color: kSecondary,
                          icon: Icons.check_circle_outline)),
                  const SizedBox(width: 10),
                  if (member.loanAmount > 0)
                    Expanded(
                        child: _StatCard(
                            label: 'Balance',
                            value: _fmtAmt((member.loanAmount - totalPaid).clamp(0, double.infinity)),
                            color: kRed,
                            icon: Icons.account_balance_outlined))
                  else
                    Expanded(
                        child: _StatCard(
                            label: 'Total Due',
                            value: _fmtAmt(totalDue),
                            color: kRed,
                            icon: Icons.timer_outlined)),
                ]),
                const SizedBox(height: 14),
                Text('Payment History (${payments.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: kText)),
                const SizedBox(height: 8),
                Expanded(
                  child: payments.isEmpty
                      ? const Center(
                          child: Text('No payments recorded',
                              style: TextStyle(color: kMuted)))
                      : ListView(
                          controller: ctrl,
                          children: payments
                              .map((p) => _PaymentHistoryTile(payment: p))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Record Payment Sheet ─────────────────────────────────────────────────────

class _RecordPaymentSheet extends StatefulWidget {
  final FcService svc;
  final String    businessId;
  final FCMember  member;
  final String    period;
  const _RecordPaymentSheet({
    required this.svc,
    required this.businessId,
    required this.member,
    required this.period,
  });

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  late final TextEditingController _amtCtrl;
  final _noteCtrl = TextEditingController();
  String _mode    = 'cash';
  bool   _saving  = false;

  @override
  void initState() {
    super.initState();
    _amtCtrl = TextEditingController(
        text: widget.member.amount.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        Row(children: [
          const _CircleIcon(
              icon: Icons.payments_outlined, color: kSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record Payment — ${widget.member.name}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                Text('Period: ${formatPeriodLabel(widget.period, widget.member.frequency)}',
                    style: const TextStyle(color: kMuted, fontSize: 12)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 20),
        TextFormField(
          controller: _amtCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: kPrimary),
          decoration: const InputDecoration(
            labelText: 'Amount ₹',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: 14),
        // Mode chips
        Row(children: [
          const Text('Mode:',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: kMuted)),
          const SizedBox(width: 10),
          Wrap(spacing: 6, children: [
            for (final m in ['cash', 'gpay', 'bank', 'other'])
              _ModeChip(
                label: m.toUpperCase(),
                active: _mode == m,
                onTap: () => setState(() => _mode = m),
              ),
          ]),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    final amt =
                        double.tryParse(_amtCtrl.text.trim());
                    if (amt == null || amt <= 0) return;
                    setState(() => _saving = true);
                    await widget.svc.recordPayment(FCPayment(
                      id:         '',
                      businessId: widget.businessId,
                      memberId:   widget.member.id,
                      month:      widget.period.length == 7 ? widget.period : widget.period.substring(0, 7),
                      period:     widget.period,
                      amount:     amt,
                      mode:       _mode,
                      note:       _noteCtrl.text.trim(),
                      createdAt:  DateTime.now(),
                    ));
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(backgroundColor: kSecondary),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Save Payment',
                    style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ─── Add Chit Sheet ───────────────────────────────────────────────────────────

class _AddChitSheet extends StatefulWidget {
  final FcService svc;
  final String    businessId;
  const _AddChitSheet({required this.svc, required this.businessId});

  @override
  State<_AddChitSheet> createState() => _AddChitSheetState();
}

class _AddChitSheetState extends State<_AddChitSheet> {
  final _nameCtrl    = TextEditingController();
  final _membersCtrl = TextEditingController();
  final _amtCtrl     = TextEditingController();
  final _monthsCtrl  = TextEditingController();
  String _startMonth = _nowYYYYMM();
  String _frequency  = 'monthly';
  bool   _saving     = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _membersCtrl.dispose();
    _amtCtrl.dispose();
    _monthsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        const Row(children: [
          _CircleIcon(
              icon: Icons.account_balance_wallet_outlined,
              color: Color(0xFF7C3AED)),
          SizedBox(width: 12),
          Text('New Chit Group',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF7C3AED))),
        ]),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            prefixIcon: Icon(Icons.group_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _membersCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Members',
                prefixIcon: Icon(Icons.people_outline),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _monthsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (months)',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        // Collection Frequency for chit
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Collection Frequency',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kMuted)),
            const SizedBox(height: 8),
            Row(children: [
              for (final f in ['daily', 'weekly', 'monthly'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FreqChip(
                    label: f[0].toUpperCase() + f.substring(1),
                    active: _frequency == f,
                    onTap: () => setState(() => _frequency = f),
                  ),
                ),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amtCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount ₹/member/${_frequency}',
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: 12),
        // Start month selector
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(
                  colorScheme:
                      const ColorScheme.light(primary: Color(0xFF7C3AED)),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              setState(() => _startMonth =
                  DateFormat('yyyy-MM').format(picked));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 18, color: kMuted),
              const SizedBox(width: 10),
              Text('Start Month: $_startMonth',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 18, color: kMuted),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    if (_nameCtrl.text.trim().isEmpty) return;
                    final members =
                        int.tryParse(_membersCtrl.text.trim()) ?? 0;
                    final amt =
                        double.tryParse(_amtCtrl.text.trim()) ?? 0;
                    final months =
                        int.tryParse(_monthsCtrl.text.trim()) ?? 0;
                    if (members <= 0 || amt <= 0 || months <= 0) return;
                    setState(() => _saving = true);
                    await widget.svc.addChit(FCChit(
                      id:          '',
                      businessId:  widget.businessId,
                      name:        _nameCtrl.text.trim(),
                      memberCount: members,
                      amount:      amt,
                      months:      months,
                      frequency:   _frequency,
                      startMonth:  _startMonth,
                      prizes:      [],
                      createdAt:   DateTime.now(),
                    ));
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED)),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Create Chit Group',
                    style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ─── Record Prize Sheet ───────────────────────────────────────────────────────

class _RecordPrizeSheet extends StatefulWidget {
  final FCChit    chit;
  final FcService svc;
  const _RecordPrizeSheet({required this.chit, required this.svc});

  @override
  State<_RecordPrizeSheet> createState() => _RecordPrizeSheetState();
}

class _RecordPrizeSheetState extends State<_RecordPrizeSheet> {
  final _winnerCtrl = TextEditingController();
  late final TextEditingController _amtCtrl;
  String _month  = _nowYYYYMM();
  bool   _saving = false;

  @override
  void initState() {
    super.initState();
    final defaultAmt = widget.chit.memberCount * widget.chit.amount;
    _amtCtrl =
        TextEditingController(text: defaultAmt.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _winnerCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 16),
        const Row(children: [
          _CircleIcon(
              icon: Icons.emoji_events_outlined,
              color: Color(0xFF7C3AED)),
          SizedBox(width: 12),
          Text('Record Prize',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF7C3AED))),
        ]),
        const SizedBox(height: 20),
        TextFormField(
          controller: _winnerCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Winner Name',
            prefixIcon: Icon(Icons.emoji_events_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amtCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Prize Amount ₹',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: 12),
        // Month selector row
        _MonthSelector(
          month: _month,
          onPrev: () => setState(() => _month = _prevMonth(_month)),
          onNext: () => setState(() => _month = _nextMonth(_month)),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    if (_winnerCtrl.text.trim().isEmpty) return;
                    final amt =
                        double.tryParse(_amtCtrl.text.trim()) ?? 0;
                    setState(() => _saving = true);
                    await widget.svc.recordChitPrize(widget.chit.id, {
                      'month':      _month,
                      'winnerName': _winnerCtrl.text.trim(),
                      'amount':     amt,
                    });
                    if (mounted) Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED)),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Save Prize',
                    style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ─── Reports Sheet ────────────────────────────────────────────────────────────

class _ReportsSheet extends StatelessWidget {
  final FcService svc;
  final String    businessId;
  const _ReportsSheet({required this.svc, required this.businessId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FCMember>>(
      stream: svc.memberStream(businessId),
      builder: (ctx, mSnap) {
        final members = mSnap.data ?? [];
        // Load all payments via individual member streams would be complex;
        // instead we do a broad payment stream for each member.
        // For simplicity we use the current month stream and show totals.
        // A complete all-time report requires joining all payment docs.
        return _ReportsBody(
            members: members, svc: svc, businessId: businessId);
      },
    );
  }
}

class _ReportsBody extends StatelessWidget {
  final List<FCMember> members;
  final FcService      svc;
  final String         businessId;
  const _ReportsBody(
      {required this.members,
      required this.svc,
      required this.businessId});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _SheetHandle(),
            SizedBox(height: 24),
            Icon(Icons.bar_chart_rounded, size: 48, color: kMuted),
            SizedBox(height: 12),
            Text('No members yet',
                style: TextStyle(
                    color: kMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, ctrl) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(children: [
          const _SheetHandle(),
          const SizedBox(height: 16),
          const Row(children: [
            _CircleIcon(
                icon: Icons.bar_chart_rounded, color: kPrimary),
            SizedBox(width: 12),
            Text('Finance Reports',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: kPrimary)),
          ]),
          const SizedBox(height: 12),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: members.length,
              itemBuilder: (_, i) => _MemberReportRow(
                member:     members[i],
                svc:        svc,
                businessId: businessId,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _MemberReportRow extends StatelessWidget {
  final FCMember  member;
  final FcService svc;
  final String    businessId;
  const _MemberReportRow(
      {required this.member,
      required this.svc,
      required this.businessId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FCPayment>>(
      stream: svc.memberPaymentStream(businessId, member.id),
      builder: (ctx, snap) {
        final payments  = snap.data ?? [];
        final totalPaid = payments.fold(0.0, (s, p) => s + p.amount);
        final now       = DateTime.now();
        final joinParts = member.joinMonth.split('-');
        int monthsActive = 1;
        if (joinParts.length == 2) {
          final jy = int.tryParse(joinParts[0]) ?? now.year;
          final jm = int.tryParse(joinParts[1]) ?? now.month;
          monthsActive =
              ((now.year - jy) * 12 + (now.month - jm) + 1).clamp(1, 9999);
        }
        final totalDue  = member.amount * monthsActive;
        final pending   = (totalDue - totalPaid).clamp(0.0, double.infinity);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: kPrimary.withOpacity(0.1),
              child: Text(
                member.name.isNotEmpty
                    ? member.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(member.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Paid ${_fmtAmt(totalPaid)}',
                    style: const TextStyle(
                        color: kSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
                Text('Due ${_fmtAmt(pending)}',
                    style: TextStyle(
                        color:
                            pending > 0 ? kRed : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                        fontSize: 11)),
              ],
            ),
          ]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _MonthSelector extends StatelessWidget {
  final String       month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthSelector({required this.month, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    String label = month;
    try {
      final dt = DateFormat('yyyy-MM').parse(month);
      label    = DateFormat('MMMM yyyy').format(dt);
    } catch (_) {}
    return _PeriodSelector(label: label, onPrev: onPrev, onNext: onNext);
  }
}

// Generic period navigator used by both Overview (monthly) and Collections (any freq)
class _PeriodSelector extends StatelessWidget {
  final String       label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _PeriodSelector({required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Row(children: [
      IconButton(
        icon: const Icon(Icons.chevron_left, color: kPrimary),
        onPressed: onPrev,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
      Expanded(
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: kPrimary)),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right, color: kPrimary),
        onPressed: onNext,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
    ]),
  );
}

class _FreqChip extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;
  const _FreqChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: active ? kPrimary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? kPrimary : const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.grey.shade600,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  final String  label;
  final String  value;
  final Color   color;
  final IconData icon;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2))
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: kMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _ProgressCard extends StatelessWidget {
  final double pct;
  final double collected;
  final double total;
  const _ProgressCard(
      {required this.pct,
      required this.collected,
      required this.total});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 2))
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Collection Progress',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: kText)),
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: kSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor:
                const AlwaysStoppedAnimation<Color>(kSecondary),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_fmtAmt(collected)} collected of ${_fmtAmt(total)} total',
          style:
              const TextStyle(color: kMuted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;
  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: kText)),
      const Spacer(),
      Text(trailing,
          style: const TextStyle(
              color: kMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

class _DefaulterTile extends StatelessWidget {
  final FCMember member;
  const _DefaulterTile({required this.member});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: kRed.withOpacity(0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kRed.withOpacity(0.2)),
    ),
    child: Row(children: [
      CircleAvatar(
        radius: 14,
        backgroundColor: kRed.withOpacity(0.15),
        child: Text(
          member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: kRed,
              fontWeight: FontWeight.w800,
              fontSize: 12),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(member.name,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
      ),
      Text(_fmtAmt(member.amount),
          style: const TextStyle(
              color: kRed,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
    ]),
  );
}

class _PaymentTile extends StatelessWidget {
  final FCPayment payment;
  final String    memberName;
  const _PaymentTile(
      {required this.payment, required this.memberName});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: kSecondary.withOpacity(0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kSecondary.withOpacity(0.2)),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle_outline,
          size: 18, color: kSecondary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(memberName,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            Text(payment.mode.toUpperCase(),
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 10)),
          ],
        ),
      ),
      Text(_fmtAmt(payment.amount),
          style: const TextStyle(
              color: kSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
    ]),
  );
}

class _PaymentHistoryTile extends StatelessWidget {
  final FCPayment payment;
  const _PaymentHistoryTile({required this.payment});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Row(children: [
      const Icon(Icons.receipt_long_outlined,
          size: 16, color: kMuted),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(payment.month,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
            Text(payment.mode.toUpperCase(),
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 10)),
            if (payment.note.isNotEmpty)
              Text(payment.note,
                  style: const TextStyle(
                      color: kMuted, fontSize: 11)),
          ],
        ),
      ),
      Text(_fmtAmt(payment.amount),
          style: const TextStyle(
              color: kSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13)),
    ]),
  );
}

class _PrizeTile extends StatelessWidget {
  final Map<String, dynamic> prize;
  const _PrizeTile({required this.prize});

  @override
  Widget build(BuildContext context) {
    final month  = prize['month']      as String? ?? '';
    final winner = prize['winnerName'] as String? ?? '';
    final amount = (prize['amount']    as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Text('🏆', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(winner,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
              Text(month,
                  style: const TextStyle(
                      color: kMuted, fontSize: 10)),
            ],
          ),
        ),
        Text(_fmtAmt(amount),
            style: const TextStyle(
                color: Color(0xFF7C3AED),
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      ]),
    );
  }
}

class _GroupBadge extends StatelessWidget {
  final String group;
  const _GroupBadge({required this.group});

  @override
  Widget build(BuildContext context) {
    final color = group == 'chit'
        ? const Color(0xFF7C3AED)
        : group == 'both'
            ? kAccent
            : kPrimary;
    final label = group[0].toUpperCase() + group.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final String       label;
  final bool         active;
  final Color        color;
  final VoidCallback onTap;
  const _GroupChip(
      {required this.label,
      required this.active,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: active ? color : const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.grey.shade600,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ModeChip extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? kPrimary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active ? kPrimary : const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.grey.shade600,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ChitStat extends StatelessWidget {
  final String label;
  final String value;
  const _ChitStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value,
          style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: kText)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(
              color: kMuted,
              fontSize: 9,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

class _ChitDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    color: const Color(0xFFE5E7EB),
    margin: const EdgeInsets.symmetric(horizontal: 6),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Text('$label: ',
          style: const TextStyle(
              color: kMuted,
              fontWeight: FontWeight.w600,
              fontSize: 13)),
      Text(value,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13)),
    ]),
  );
}

class _FullEmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const _FullEmptyState(
      {required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 36, color: kPrimary),
        ),
        const SizedBox(height: 18),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: kPrimary)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(
                color: Colors.grey.shade500, fontSize: 13)),
      ],
    ),
  );
}

class _EmptyTile extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _EmptyTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Icon(icon, size: 18, color: kMuted),
      const SizedBox(width: 10),
      Text(text,
          style: const TextStyle(
              color: kMuted, fontSize: 13)),
    ]),
  );
}

// ─── Sheet helpers ────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2)),
    ),
  );
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final Color    color;
  const _CircleIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
        color: color.withOpacity(0.1), shape: BoxShape.circle),
    child: Icon(icon, color: color, size: 20),
  );
}
