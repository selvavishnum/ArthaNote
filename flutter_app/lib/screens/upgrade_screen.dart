import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../providers/app_provider.dart';
import '../services/billing_service.dart';
import '../widgets/promo_dialog.dart';

/// Purchase-intent signal for the admin "💎 Ready to Pay" list — same event
/// the website logs. Throttled to one audit write per source per day so a
/// user reopening the paywall never burns Firestore quota. Fire-and-forget:
/// never throws, never blocks the UI. Skipped in guest mode (no uid).
Future<void> logPaywallView(BuildContext context, String source) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pw_${source.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(key) == today) return;
    await prefs.setString(key, today);
    if (!context.mounted) return;
    final p = context.read<AppProvider>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || p.businessId.isEmpty) return;
    await FirebaseFirestore.instance.collection('audit').add({
      'businessId': p.businessId,
      'userId': uid,
      'by': 'app-user',
      'action': 'paywall_view',
      'desc': source,
      'at': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

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
                    builder: (_) => UpgradeScreen(source: feature))),
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
/// free-vs-Pro feature comparison. Purchases go through Google Play Billing
/// ([BillingService]) by default; [onSubscribe] lets a caller override that
/// (e.g. for tests) with a custom handler for the chosen plan id
/// ('monthly' | 'yearly' | 'lifetime').
class UpgradeScreen extends StatefulWidget {
  /// Called when the user taps Subscribe, overriding the default
  /// [BillingService] purchase flow. Receives the plan id.
  final Future<void> Function(String planId)? onSubscribe;

  /// Which lock/banner brought the user here — logged as purchase intent.
  final String source;
  const UpgradeScreen({super.key, this.onSubscribe, this.source = 'direct'});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String _selected = 'yearly'; // default-highlight the best-value plan
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) logPaywallView(context, widget.source);
    });
  }

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
    setState(() => _busy = true);
    try {
      if (widget.onSubscribe != null) {
        await widget.onSubscribe!(_selected);
      } else {
        await BillingService().buy(_selected);
      }
      // Purchase confirmation arrives asynchronously via BillingService's
      // stream listener (Play shows its own sheet/receipt UI meanwhile) —
      // this just launched the flow.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Continue in the Google Play sheet to complete your purchase'),
          backgroundColor: kPrimary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Purchase failed: $e'), backgroundColor: kRed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await BillingService().restorePurchases();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Checking Google Play for previous purchases…'),
          backgroundColor: kPrimary,
        ));
        // Give the purchase stream a moment to deliver restored purchases,
        // then pull the (possibly now-updated) profile.
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) await context.read<AppProvider>().refreshProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restore failed: $e'), backgroundColor: kRed));
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
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      final ok = await showPromoCodeSheet(context);
                      if (ok && mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.card_giftcard_rounded,
                        size: 18, color: kPrimary),
                    label: const Text('Have a promo code? Redeem',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kPrimary)),
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.restore_rounded,
                        size: 18, color: kMuted),
                    label: const Text('Already subscribed? Restore purchases',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kMuted)),
                  ),
                ),
                const SizedBox(height: 6),
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
