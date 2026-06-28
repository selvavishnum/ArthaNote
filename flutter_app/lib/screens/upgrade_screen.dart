import 'package:flutter/material.dart';
import '../theme.dart';

/// Full-screen "this is a Pro feature" placeholder shown in place of a gated
/// screen's content when the user is on the free tier (trial ended). Tapping
/// Upgrade opens the [UpgradeScreen] paywall.
class ProLockView extends StatelessWidget {
  final String feature;
  final String blurb;
  const ProLockView({super.key, required this.feature, required this.blurb});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: kGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 18),
            Text('$feature is a Pro feature',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 8),
            Text(blurb,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: kMuted, height: 1.4)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const UpgradeScreen())),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Upgrade to Pro',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ArthaNote Pro upgrade / paywall screen.
///
/// Presents the three subscription tiers (monthly / yearly / lifetime) and the
/// free-vs-Pro feature comparison. The actual purchase is wired to Google Play
/// Billing in a later phase — [onSubscribe] is invoked with the chosen plan id
/// ('monthly' | 'yearly' | 'lifetime') so billing can be plugged in centrally
/// without touching this UI.
class UpgradeScreen extends StatefulWidget {
  /// Called when the user taps Subscribe. Receives the plan id. When null, a
  /// "coming soon" notice is shown (billing not yet enabled).
  final Future<void> Function(String planId)? onSubscribe;
  const UpgradeScreen({super.key, this.onSubscribe});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String _selected = 'yearly'; // default-highlight the best-value plan
  bool _busy = false;

  static const _plans = [
    _Plan('monthly', 'Monthly', '₹199', '/month', null, false),
    _Plan('yearly', 'Yearly', '₹999', '/year', 'SAVE 58%', true),
    _Plan('lifetime', 'Lifetime', '₹1999', 'one-time', 'BEST VALUE', false),
  ];

  static const _features = [
    _Feat('Shops', '1 shop + personal', 'Unlimited'),
    _Feat('Staff access', 'Up to 10', 'Unlimited'),
    _Feat('Data history', '2 years', 'Lifetime'),
    _Feat('Reports page', false, true),
    _Feat('AI Missing-Entry Alert', false, true),
    _Feat('AI Duplicate-Entry Alert', false, true),
    _Feat('Finance & Chit module', false, true),
    _Feat('Expense reminders', false, true),
  ];

  Future<void> _subscribe() async {
    if (widget.onSubscribe == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Payments are being set up — coming very soon!'),
        backgroundColor: kPrimary,
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubscribe!(_selected);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Purchase failed: $e'), backgroundColor: kRed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('ArthaNote Pro',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                // Hero
                Center(
                  child: Column(children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: kGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 14),
                    const Text('Unlock everything',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: kText)),
                    const SizedBox(height: 6),
                    const Text(
                      'Grow without limits. One plan, every feature.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: kMuted),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),

                // Plan cards
                ..._plans.map((p) => _PlanCard(
                      plan: p,
                      selected: _selected == p.id,
                      onTap: () => setState(() => _selected = p.id),
                    )),

                const SizedBox(height: 22),

                // Feature comparison
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: kCardShadow,
                  ),
                  child: Column(children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Row(children: [
                        Expanded(flex: 5, child: Text('')),
                        Expanded(
                            flex: 3,
                            child: Text('FREE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: kMuted))),
                        Expanded(
                            flex: 3,
                            child: Text('PRO',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: kPrimary))),
                      ]),
                    ),
                    const Divider(height: 1),
                    ..._features.map((f) => _FeatureRow(feat: f)),
                    const SizedBox(height: 8),
                  ]),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    'Cancel anytime · Secure payment via Google Play',
                    style: TextStyle(fontSize: 11, color: kMuted),
                  ),
                ),
              ],
            ),
          ),

          // Sticky subscribe bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: kBoxShadow,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _busy ? null : _subscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        'Get ${_plans.firstWhere((p) => p.id == _selected).title} — '
                        '${_plans.firstWhere((p) => p.id == _selected).price}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Plan {
  final String id;
  final String title;
  final String price;
  final String period;
  final String? badge;
  final bool highlight;
  const _Plan(this.id, this.title, this.price, this.period, this.badge,
      this.highlight);
}

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard(
      {required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFECFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? kPrimary : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? kPrimary : kMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(plan.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
                if (plan.badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(plan.badge!,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706))),
                  ),
                ],
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(plan.price,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: kPrimary)),
            Text(plan.period,
                style: const TextStyle(fontSize: 11, color: kMuted)),
          ]),
        ]),
      ),
    );
  }
}

class _Feat {
  final String name;
  // free/pro are either bool (✓/✗) or String (text value)
  final Object free;
  final Object pro;
  const _Feat(this.name, this.free, this.pro);
}

class _FeatureRow extends StatelessWidget {
  final _Feat feat;
  const _FeatureRow({required this.feat});

  Widget _cell(Object v, Color tickColor) {
    if (v is bool) {
      return Icon(v ? Icons.check_circle : Icons.remove_circle_outline,
          size: 18, color: v ? tickColor : const Color(0xFFD1D5DB));
    }
    return Text(v.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kText));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        Expanded(
            flex: 5,
            child: Text(feat.name,
                style: const TextStyle(fontSize: 12, color: kText))),
        Expanded(flex: 3, child: Center(child: _cell(feat.free, kMuted))),
        Expanded(flex: 3, child: Center(child: _cell(feat.pro, kPrimary))),
      ]),
    );
  }
}
