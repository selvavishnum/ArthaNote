import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/shop.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int    _step         = 0;
  String _selectedType = '';
  String _selectedIcon = '';
  final  _shopName     = TextEditingController();
  bool   _saving       = false;
  final  _auth         = AuthService();

  String get _lang => context.read<AppProvider>().lang;

  Future<void> _finish() async {
    if (_shopName.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final provider = context.read<AppProvider>();
      final uid      = _auth.currentUser!.uid;
      final shopId   = const Uuid().v4().substring(0, 8);
      final shop     = Shop(
        id:   shopId,
        name: _shopName.text.trim(),
        icon: _selectedIcon,
        type: _selectedType,
      );

      provider.addShop(shopId, shop);

      await _auth.saveConfig(provider.businessId, {
        'shops':    {shopId: shop.toMap()},
        'bizType':  _selectedType,
        'onboarded': true,
      });
      await _auth.saveProfile(uid, {'onboarded': true});

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder:    (_, __, ___) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (_, a, __, child) =>
                FadeTransition(opacity: a, child: child),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Please try again.'),
            backgroundColor: kRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _lang;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(l),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: _step == 0
                  ? _buildStep0(l)
                  : _buildStep1(l),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader(String l) => Container(
    decoration: const BoxDecoration(
      gradient: kGradient,
      borderRadius: BorderRadius.only(
        bottomLeft:  Radius.circular(0),
        bottomRight: Radius.circular(0),
      ),
    ),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('AN',
          style: TextStyle(
            color: Colors.white, fontSize: 22,
            fontWeight: FontWeight.w900, fontFamily: 'Georgia')),
        const SizedBox(width: 10),
        Text('ArthaNote',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9), fontSize: 16,
            fontWeight: FontWeight.w600)),
        const Spacer(),
        // Step indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${t("step", l)} ${_step + 1} ${t("of", l)} 2',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 12),
      Text(
        t('onboarding_title', l),
        style: const TextStyle(
          color: Colors.white, fontSize: 20,
          fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        _step == 0
            ? t('biz_type_hint', l)
            : t('shop_subtitle', l),
        style: TextStyle(
          color: Colors.white.withOpacity(0.75),
          fontSize: 13),
      ),
      const SizedBox(height: 12),
      // Progress bar
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (_step + 1) / 2,
          backgroundColor: Colors.white.withOpacity(0.2),
          color: Colors.white,
          minHeight: 4,
        ),
      ),
    ]),
  );

  Widget _buildStep0(String l) => Padding(
    key: const ValueKey(0),
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    child: Column(children: [
      Expanded(
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.95,
          ),
          itemCount: kShopTypes.length,
          itemBuilder: (_, i) {
            final s      = kShopTypes[i];
            final active = _selectedType == s['type'];
            return GestureDetector(
              onTap: () => setState(() {
                _selectedType = s['type']!;
                _selectedIcon = s['icon']!;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? kPrimary : const Color(0xFFE5E7EB),
                    width: active ? 2 : 1,
                  ),
                  boxShadow: active ? kBoxShadow : kCardShadow,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(s['icon']!, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(
                      s['label']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _selectedType.isEmpty
            ? null
            : () => setState(() => _step = 1),
        child: Text(t('next', l)),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => _showStaffConnectDialog(context),
        child: const Text(
          "I'm a staff member — Connect to employer",
          style: TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ]),
  );

  void _showStaffConnectDialog(BuildContext ctx) {
    final ctrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Connect to Employer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Ask your employer for their Business ID.\n'
            'Owner: Settings → Staff App Access → copy the Business ID.',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Business ID',
              hintText: 'Paste the ID from your employer',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _connectWithId(dctx, ctrl.text.trim()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => _connectWithId(dctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            child: const Text('Connect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _connectWithId(BuildContext dctx, String bid) async {
    if (bid.isEmpty) return;
    Navigator.pop(dctx); // close dialog
    setState(() => _saving = true);
    await context.read<AppProvider>().setManualBusinessId(bid);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder:    (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
        ),
      );
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _buildStep1(String l) => Padding(
    key: const ValueKey(1),
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected type pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kPrimary.withOpacity(0.2)),
          ),
          child: Text(
            '$_selectedIcon  $_selectedType'.replaceFirst(
              _selectedType,
              _selectedType[0].toUpperCase() + _selectedType.substring(1)),
            style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _selectedType == 'personal' ? "What's your name?" : t('name_your_shop', l),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          _selectedType == 'personal'
              ? 'Track money you owe and are owed'
              : t('shop_subtitle', l),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _shopName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _selectedType == 'personal' ? 'Your Name' : t('shop_name', l),
            prefixText: '$_selectedIcon  ',
            prefixStyle: const TextStyle(fontSize: 18),
            hintText: _selectedType == 'personal' ? 'e.g. Ravi Kumar' : 'e.g. Tulsi Vegetables',
          ),
        ),
        const Spacer(),
        Row(children: [
          OutlinedButton(
            onPressed: () => setState(() => _step = 0),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(100, 52),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Text(t('back', l)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: (_shopName.text.trim().isEmpty || _saving) ? null : _finish,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(t('get_started', l)),
            ),
          ),
        ]),
      ],
    ),
  );

  @override
  void dispose() {
    _shopName.dispose();
    super.dispose();
  }
}
