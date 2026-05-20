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
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  String _selectedType = '';
  String _selectedIcon = '';
  final _shopName = TextEditingController();
  bool _saving = false;
  final _auth = AuthService();

  String get lang => context.read<AppProvider>().lang;

  Future<void> _finish() async {
    if (_shopName.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final provider = context.read<AppProvider>();
      final uid = _auth.currentUser!.uid;
      final shopId = const Uuid().v4().substring(0, 8);
      final shop = Shop(id: shopId, name: _shopName.text.trim(), icon: _selectedIcon, type: _selectedType);
      provider.addShop(shopId, shop);
      await _auth.saveConfig(provider.businessId, {
        'shops': {shopId: shop.toMap()},
        'bizType': _selectedType,
        'onboarded': true,
      });
      await _auth.saveProfile(uid, {'onboarded': true});
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = lang;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text(t('app_name', l))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _step == 0 ? _buildStep0(l) : _buildStep1(l),
          ),
        ),
      ),
    );
  }

  Widget _buildStep0(String l) => Column(
    key: const ValueKey(0),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('What type of shop?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary)),
      const SizedBox(height: 8),
      Text('Select your business type', style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 24),
      Expanded(
        child: GridView.count(
          crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12,
          children: kShopTypes.map((s) {
            final active = _selectedType == s['type'];
            return GestureDetector(
              onTap: () => setState(() { _selectedType = s['type']!; _selectedIcon = s['icon']!; }),
              child: Container(
                decoration: BoxDecoration(
                  color: active ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active ? kPrimary : Colors.grey.shade200, width: active ? 2 : 1),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(s['icon']!, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(s['label']!, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: active ? Colors.white : Colors.grey.shade700)),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _selectedType.isEmpty ? null : () => setState(() => _step = 1),
        child: const Text('Next →'),
      ),
    ],
  );

  Widget _buildStep1(String l) => Column(
    key: const ValueKey(1),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$_selectedIcon Name your shop', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kPrimary)),
      const SizedBox(height: 8),
      Text('This is what you\'ll see on your dashboard', style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 32),
      TextFormField(
        controller: _shopName,
        autofocus: true,
        decoration: InputDecoration(
          labelText: t('shop_name', l),
          prefixText: '$_selectedIcon  ',
          hintText: 'e.g. Tulsi Vegetables',
        ),
      ),
      const Spacer(),
      Row(children: [
        TextButton(onPressed: () => setState(() => _step = 0), child: const Text('← Back')),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: (_shopName.text.trim().isEmpty || _saving) ? null : _finish,
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                           : const Text('Get Started →'),
          ),
        ),
      ]),
    ],
  );

  @override
  void dispose() { _shopName.dispose(); super.dispose(); }
}
