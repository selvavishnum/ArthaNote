import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/shop.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import '../services/db_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p       = context.watch<AppProvider>();
    final l       = p.lang;
    final profile = p.profile;
    final name    = (profile['name']  as String?) ?? '';
    final email   = (profile['email'] as String?) ?? '';
    final isAdmin = p.isAdmin;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(t('settings', l)),
        backgroundColor: Colors.white,
        foregroundColor: kText,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0x18000000),
        titleTextStyle: const TextStyle(
          color: kText,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [

          // ── Profile card ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: kCardShadow,
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: kPrimary.withOpacity(0.12),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15, color: kText)),
                    if (email.isNotEmpty)
                      Text(email,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _planBadgeBg(p),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _planBadgeLabel(p),
                        style: TextStyle(
                          color: _planBadgeFg(p),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // ── Settings menu items ────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: kCardShadow,
            ),
            child: Column(children: [
              _SettingsItem(
                icon: Icons.person_outline,
                iconColor: const Color(0xFF6366F1),
                title: t('profile', l),
                subtitle: 'Your account details',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _ProfileSheet(p: p),
                ),
              ),
              const _ItemDivider(),
              _SettingsItem(
                icon: Icons.store_outlined,
                iconColor: kSecondary,
                title: t('shop_names', l),
                subtitle: 'Edit your shops',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _ShopNamesSheet(p: p),
                ),
              ),
              const _ItemDivider(),
              _SettingsItem(
                icon: Icons.people_outline,
                iconColor: const Color(0xFF8B5CF6),
                title: t('staff', l),
                subtitle: 'View staff members',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _StaffSheet(businessId: p.businessId),
                ),
              ),
              const _ItemDivider(),
              _SettingsItem(
                icon: Icons.qr_code_outlined,
                iconColor: kPrimary,
                title: t('qr_attendance', l),
                subtitle: 'Generate QR & view attendance',
                onTap: () async {
                  final url = Uri.parse('https://selvavishnum.github.io/Kannakupilai/attend.html');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const _ItemDivider(),
              _SettingsItem(
                icon: Icons.receipt_outlined,
                iconColor: kAccent,
                title: t('gst_settings', l),
                subtitle: 'Enable GST & choose tax rate',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => const _GstSheet(),
                ),
              ),
              const _ItemDivider(),
              _SettingsItem(
                icon: Icons.edit_note_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: t('categories', l),
                subtitle: 'Sales & expense categories',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _CategoriesSheet(p: p),
                ),
              ),
              const _ItemDivider(),
              _SettingsItem(
                icon: Icons.save_outlined,
                iconColor: const Color(0xFF10B981),
                title: t('backup', l),
                subtitle: 'Export or restore your data',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => const _BackupSheet(),
                ),
                isLast: !isAdmin,
              ),
              if (isAdmin) ...[
                const _ItemDivider(),
                _SettingsItem(
                  icon: Icons.key_outlined,
                  iconColor: const Color(0xFFD97706),
                  title: '🔑 OCR API Keys',
                  subtitle: 'Gemini & Claude API keys',
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const _OcrApiKeysSheet(),
                  ),
                  isLast: true,
                ),
              ],
            ]),
          ),

          const SizedBox(height: 20),

          // ── Language toggle ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: kCardShadow,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.language, color: kPrimary, size: 22),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('language', l),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14, color: kText)),
                    Text(l == 'en' ? 'English' : 'தமிழ்',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ]),
                ]),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('EN')),
                    ButtonSegment(value: 'ta', label: Text('தமிழ்')),
                  ],
                  selected: {l},
                  onSelectionChanged: (s) => p.setLang(s.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return kPrimary;
                      return Colors.white;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return Colors.white;
                      return kText;
                    }),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Sign Out button ────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context, p),
            icon: const Icon(Icons.logout, color: kRed),
            label: Text(t('sign_out', l), style: const TextStyle(color: kRed)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: kRed),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              foregroundColor: kRed,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static String _planBadgeLabel(AppProvider p) {
    if (p.isAdmin) return 'Admin';
    if (p.profile['pro'] == true) return 'Pro';
    return 'Free';
  }

  static Color _planBadgeBg(AppProvider p) {
    if (p.isAdmin) return const Color(0xFFF3E8FF);
    if (p.profile['pro'] == true) return const Color(0xFFFEF3C7);
    return const Color(0xFFDCFCE7);
  }

  static Color _planBadgeFg(AppProvider p) {
    if (p.isAdmin) return const Color(0xFF7C3AED);
    if (p.profile['pro'] == true) return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }

  Future<void> _confirmSignOut(BuildContext context, AppProvider p) async {
    final l = p.lang;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('sign_out', l)),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel', l)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: Text(t('sign_out', l)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService().signOut();
    if (!context.mounted) return;
    p.reset();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

// ── Settings item tile ────────────────────────────────────────────────────────
class _SettingsItem extends StatelessWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       title;
  final String       subtitle;
  final VoidCallback onTap;
  final bool         isLast;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.only(
      topLeft:     const Radius.circular(16),
      topRight:    const Radius.circular(16),
      bottomLeft:  Radius.circular(isLast ? 16 : 0),
      bottomRight: Radius.circular(isLast ? 16 : 0),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14, color: kText)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB), size: 20),
      ]),
    ),
  );
}

class _ItemDivider extends StatelessWidget {
  const _ItemDivider();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 68),
    child: Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
  );
}

// ── Profile sheet ─────────────────────────────────────────────────────────────
class _ProfileSheet extends StatefulWidget {
  final AppProvider p;
  const _ProfileSheet({required this.p});
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: (widget.p.profile['name'] as String?) ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await AuthService().saveProfile(uid, {'name': _nameCtrl.text.trim()});
    widget.p.updateProfileField('name', _nameCtrl.text.trim());
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Name updated ✅'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name  = (widget.p.profile['name']  as String?) ?? '';
    final email = (widget.p.profile['email'] as String?) ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        Row(children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: kPrimary.withOpacity(0.12),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w800, fontSize: 22),
            ),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Profile',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
            if (email.isNotEmpty)
              Text(email, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Display Name',
            prefixIcon: const Icon(Icons.person_outline, color: kPrimary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kPrimary, width: 2)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: _saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Save Name'),
          ),
        ),
      ]),
    );
  }
}

// ── Shop Names sheet ──────────────────────────────────────────────────────────
class _ShopNamesSheet extends StatefulWidget {
  final AppProvider p;
  const _ShopNamesSheet({required this.p});
  @override
  State<_ShopNamesSheet> createState() => _ShopNamesSheetState();
}

class _ShopNamesSheetState extends State<_ShopNamesSheet> {
  String? _editingId;
  late final Map<String, TextEditingController> _ctrls;
  bool _saving = false;

  // Add shop form state
  bool _addingShop = false;
  final _newIconCtrl = TextEditingController(text: '🏪');
  final _newNameCtrl = TextEditingController();
  String _newType = 'other';

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final e in widget.p.shops.entries)
        e.key: TextEditingController(text: e.value.name)
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    _newIconCtrl.dispose();
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(String id) async {
    final shop = widget.p.shops[id];
    if (shop == null) return;
    final newName = _ctrls[id]?.text.trim() ?? '';
    if (newName.isEmpty) return;
    setState(() => _saving = true);
    widget.p.updateShop(id, shop.copyWith(name: newName));
    setState(() { _saving = false; _editingId = null; });
  }

  void _addShop() {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    final icon = _newIconCtrl.text.trim().isEmpty ? '🏪' : _newIconCtrl.text.trim();

    // Generate next shop ID: find highest s{n} number
    final existing = widget.p.shops.keys;
    int maxN = 0;
    for (final k in existing) {
      final m = RegExp(r'^s(\d+)$').firstMatch(k);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    final newId = 's${maxN + 1}';
    final newShop = Shop(id: newId, name: name, icon: icon, type: _newType);
    final ctrl = TextEditingController(text: name);
    setState(() {
      _ctrls[newId] = ctrl;
      _addingShop = false;
      _newNameCtrl.clear();
      _newIconCtrl.text = '🏪';
      _newType = 'other';
    });
    widget.p.addShop(newId, newShop);
  }

  Future<void> _removeShop(String id) async {
    final shop = widget.p.shops[id];
    if (shop == null) return;
    final confirmCtrl = TextEditingController();
    bool canDelete = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Remove Shop'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type "${shop.name}" to confirm removal.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                decoration: InputDecoration(
                  labelText: 'Shop name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (v) {
                  setDialogState(() => canDelete = v == shop.name);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: canDelete
                  ? () {
                      Navigator.pop(ctx);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kRed,
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );

    // Dispose AFTER dialog returns
    confirmCtrl.dispose();

    if (canDelete) {
      setState(() {
        _ctrls[id]?.dispose();
        _ctrls.remove(id);
      });
      widget.p.removeShop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = widget.p.shops;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        Row(children: [
          const Text('🏪', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Shop Names',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _addingShop = !_addingShop;
              if (!_addingShop) {
                _newNameCtrl.clear();
                _newIconCtrl.text = '🏪';
                _newType = 'other';
              }
            }),
            icon: Icon(_addingShop ? Icons.close : Icons.add, size: 16),
            label: Text(_addingShop ? 'Cancel' : '+ Add Shop'),
            style: TextButton.styleFrom(foregroundColor: kPrimary),
          ),
        ]),

        // Add shop inline form
        if (_addingShop) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withOpacity(0.25)),
            ),
            child: Column(children: [
              Row(children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _newIconCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Icon',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _newNameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Shop name',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _newType,
                decoration: const InputDecoration(
                  labelText: 'Business type',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: kShopTypes
                    .map((st) => DropdownMenuItem(
                          value: st['type']!,
                          child: Text('${st['icon']!} ${st['label']!}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _newType = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addShop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Add Shop'),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),
        if (shops.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No shops configured.', style: TextStyle(color: kMuted)),
          )
        else
          ...shops.entries.map((e) {
            final isEditing = _editingId == e.key;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isEditing ? kPrimary.withOpacity(0.04) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isEditing ? kPrimary.withOpacity(0.3) : const Color(0xFFE5E7EB),
                ),
              ),
              child: isEditing
                  ? Row(children: [
                      Text(e.value.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrls[e.key],
                          autofocus: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _saving ? null : () => _save(e.key),
                        child: const Text('Save', style: TextStyle(color: kPrimary)),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _editingId = null),
                        child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    ])
                  : Row(children: [
                      Text(e.value.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: kMuted),
                        onPressed: () => setState(() => _editingId = e.key),
                      ),
                      if (shops.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: kRed),
                          onPressed: () => _removeShop(e.key),
                        ),
                    ]),
            );
          }),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Staff sheet ───────────────────────────────────────────────────────────────
class _StaffSheet extends StatefulWidget {
  final String businessId;
  const _StaffSheet({required this.businessId});
  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  static const _roles = ['cashier', 'manager', 'worker'];

  void _showStaffForm(BuildContext ctx, String? docId, Map<String, dynamic>? existing) {
    final nameCtrl  = TextEditingController(text: (existing?['name']  as String?) ?? '');
    final emailCtrl = TextEditingController(text: (existing?['email'] as String?) ?? '');
    String role = (existing?['role'] as String?) ?? 'cashier';

    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(docId != null ? 'Edit Staff' : 'Add Staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Gmail / Email'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _roles
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r[0].toUpperCase() + r.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => role = v ?? 'cashier'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'name':       nameCtrl.text.trim(),
                  'email':      emailCtrl.text.trim(),
                  'role':       role,
                  'businessId': widget.businessId,
                };
                final col = FirebaseFirestore.instance.collection('staff');
                if (docId != null) {
                  await col.doc(docId).update(data);
                } else {
                  await col.doc().set(data);
                }
                if (ctx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(docId != null ? 'Staff updated ✅' : 'Staff added ✅'),
                    backgroundColor: kSecondary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).then((_) {
      nameCtrl.dispose();
      emailCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        Row(children: [
          const Text('👥', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Staff Members',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
          ),
          ElevatedButton.icon(
            onPressed: () => _showStaffForm(context, null, null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('+ Add Staff'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('staff')
              .where('businessId', isEqualTo: widget.businessId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: kPrimary),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No staff found.', style: TextStyle(color: kMuted)),
              );
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                itemBuilder: (context, index) {
                  final doc  = docs[index];
                  final d    = doc.data();
                  final name  = (d['name']  as String?) ?? 'Unknown';
                  final email = (d['email'] as String?) ?? '';
                  final role  = (d['role']  as String?) ?? 'staff';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: kPrimary.withOpacity(0.12),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: kPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(email,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(role,
                              style: const TextStyle(
                                  color: kPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: kMuted),
                          onPressed: () => _showStaffForm(context, doc.id, d),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── GST Settings sheet ────────────────────────────────────────────────────────
class _GstSheet extends StatefulWidget {
  const _GstSheet();
  @override
  State<_GstSheet> createState() => _GstSheetState();
}

class _GstSheetState extends State<_GstSheet> {
  bool   _gstOn  = false;
  double _rate   = 18.0;
  bool   _saving = false;
  static const _rates = [0.0, 5.0, 12.0, 18.0, 28.0];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _gstOn = prefs.getBool('slv_gst')      ?? false;
        _rate  = prefs.getDouble('slv_gstrate') ?? 18.0;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('slv_gst', _gstOn);
    await prefs.setDouble('slv_gstrate', _rate);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_gstOn ? 'GST ${_rate.toStringAsFixed(0)}% enabled ✅' : 'GST disabled'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        Row(children: [
          const Text('🧾', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Expanded(child: Text('GST Settings',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary))),
          Switch(value: _gstOn, onChanged: (v) => setState(() => _gstOn = v),
              activeColor: kPrimary),
        ]),
        const SizedBox(height: 20),

        if (_gstOn) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('GST Rate',
                style: TextStyle(fontWeight: FontWeight.w700, color: kText, fontSize: 14)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _rates.map((r) {
              final active = _rate == r;
              return GestureDetector(
                onTap: () => setState(() => _rate = r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? kPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: active ? kPrimary : const Color(0xFFE5E7EB)),
                    boxShadow: active ? kCardShadow : null,
                  ),
                  child: Text(
                    r == 0 ? 'No GST' : '${r.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: active ? Colors.white : kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _gstOn ? kSecondary.withOpacity(0.06) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Text(_gstOn ? '✅' : '⭕', style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Text(
              _gstOn
                  ? 'GST ${_rate.toStringAsFixed(0)}% will be applied to entries'
                  : 'GST is currently disabled',
              style: TextStyle(
                color: _gstOn ? kSecondary : Colors.grey.shade500,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: _saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Save GST Settings'),
          ),
        ),
      ]),
    );
  }
}

// ── Categories sheet ──────────────────────────────────────────────────────────
class _CategoriesSheet extends StatefulWidget {
  final AppProvider p;
  const _CategoriesSheet({required this.p});
  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  final Map<String, TextEditingController> _salesCtrl  = {};
  final Map<String, TextEditingController> _expCtrl    = {};
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    for (final e in widget.p.shops.entries) {
      final shopId = e.key;
      _salesCtrl[shopId] = TextEditingController(
        text: widget.p.salesCats(shopId).join(', '),
      );
      _expCtrl[shopId] = TextEditingController(
        text: widget.p.expenseCats(shopId).join(', '),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomCats());
  }

  @override
  void dispose() {
    for (final c in _salesCtrl.values) c.dispose();
    for (final c in _expCtrl.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadCustomCats() async {
    final prefs = await SharedPreferences.getInstance();
    for (final shopId in widget.p.shops.keys) {
      final customSale = prefs.getStringList('kp_custom_${shopId}_sale') ?? [];
      final customExp  = prefs.getStringList('kp_custom_${shopId}_expense') ?? [];

      if (customSale.isNotEmpty && mounted) {
        final ctrl = _salesCtrl[shopId];
        if (ctrl != null) {
          final existing = ctrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          for (final c in customSale) {
            if (!existing.contains(c)) existing.add(c);
          }
          setState(() => ctrl.text = existing.join(', '));
        }
      }

      if (customExp.isNotEmpty && mounted) {
        final ctrl = _expCtrl[shopId];
        if (ctrl != null) {
          final existing = ctrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          for (final c in customExp) {
            if (!existing.contains(c)) existing.add(c);
          }
          setState(() => ctrl.text = existing.join(', '));
        }
      }
    }
  }

  Future<void> _saveShop(String shopId) async {
    setState(() => _saving.add(shopId));
    final sales = (_salesCtrl[shopId]?.text ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final expense = (_expCtrl[shopId]?.text ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    widget.p.updateShopCats(shopId, sales, expense);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() => _saving.remove(shopId));
      final shop = widget.p.shops[shopId];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${shop?.name ?? ''} categories saved ✅'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _quickAdd(BuildContext context, String category, String type, Shop shop) {
    final amtCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(type == 'sale' ? '💚' : '📉', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(category,
              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shop.name, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: amtCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '0',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPrimary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = amtCtrl.text.trim().replaceAll(',', '');
              final amt = double.tryParse(raw);
              if (amt == null || amt <= 0) return;
              Navigator.pop(ctx);
              await DbService().addTxn(Txn(
                id:         const Uuid().v4(),
                businessId: widget.p.businessId,
                shop:       shop.id,
                shopName:   shop.name,
                date:       DateTime.now(),
                type:       type,
                amount:     amt,
                desc:       category,
              ));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('$category ₹${amt.toStringAsFixed(0)} saved ✅'),
                  backgroundColor: kSecondary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: type == 'sale' ? kSecondary : kRed,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(type == 'sale' ? 'Save Sales' : 'Save Expense'),
          ),
        ],
      ),
    ).then((_) => amtCtrl.dispose());
  }

  Widget _buildShopSection(Shop shop) {
    final shopId = shop.id;
    final isSaving = _saving.contains(shopId);
    final salesText = _salesCtrl[shopId]?.text ?? '';
    final expText   = _expCtrl[shopId]?.text ?? '';
    final saleCats  = salesText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final expCats   = expText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Shop header + save button
          Row(children: [
            Text(shop.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(shop.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            TextButton(
              onPressed: isSaving ? null : () => _saveShop(shopId),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: kPrimary, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: kPrimary)),
            ),
          ]),
          const SizedBox(height: 12),

          // SALES CATEGORIES
          Row(children: [
            Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: kSecondary, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('SALES CATEGORIES',
                style: TextStyle(color: kMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _salesCtrl[shopId],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Cash, GPay, Card, ...',
              helperText: 'Separate each with comma',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: saleCats
                .map((cat) => _CategoryChip(
                      label: cat,
                      color: kSecondary,
                      onTap: () => _quickAdd(context, cat, 'sale', shop),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),

          // EXPENSE CATEGORIES
          Row(children: [
            Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: kRed, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            const Text('EXPENSE CATEGORIES',
                style: TextStyle(color: kMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _expCtrl[shopId],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Purchase, Salary, Rent/EB, ...',
              helperText: 'Separate each with comma',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: expCats
                .map((cat) => _CategoryChip(
                      label: cat,
                      color: kRed,
                      onTap: () => _quickAdd(context, cat, 'expense', shop),
                    ))
                .toList(),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SheetHandle(),
          const SizedBox(height: 18),
          const Row(children: [
            Text('📋', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text('Categories',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
          ]),
          const SizedBox(height: 4),
          Text('Tap a category to quick-add an entry',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 20),
          ...widget.p.shops.values.map(_buildShopSection),
        ]),
      ),
    );
  }
}

// ── Backup sheet ──────────────────────────────────────────────────────────────
class _BackupSheet extends StatelessWidget {
  const _BackupSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        const Row(children: [
          Text('💾', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Text('Backup & Restore',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kPrimary.withOpacity(0.15)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your data is safe',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: kPrimary)),
            const SizedBox(height: 8),
            Text(
              'All your entries are automatically synced to Firebase Cloud in real-time. '
              'Your data is secure and accessible from any device.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            _FeatureRow(icon: '☁️', text: 'Auto-sync to Firebase'),
            _FeatureRow(icon: '🔒', text: 'AES-256 encryption'),
            _FeatureRow(icon: '📱', text: 'Access from any device'),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kAccent.withOpacity(0.25)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🚀', style: TextStyle(fontSize: 14)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'CSV Export & Local Backup coming in v2.\nStay tuned for the next update!',
                style: TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w500),
              )),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 15)),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(color: kText, fontSize: 13)),
    ]),
  );
}

// ── OCR API Keys sheet (admin only) ──────────────────────────────────────────
class _OcrApiKeysSheet extends StatefulWidget {
  const _OcrApiKeysSheet();
  @override
  State<_OcrApiKeysSheet> createState() => _OcrApiKeysSheetState();
}

class _OcrApiKeysSheetState extends State<_OcrApiKeysSheet> {
  final _geminiCtrl = TextEditingController();
  final _claudeCtrl = TextEditingController();
  bool  _geminiOn      = true;
  bool  _claudeOn      = true;
  bool  _saving        = false;
  bool  _geminiObscure = true;
  bool  _claudeObscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _geminiCtrl.text = prefs.getString('slv_gemini_key') ?? '';
      _claudeCtrl.text = prefs.getString('slv_key')        ?? '';
      _geminiOn        = prefs.getBool('slv_gemini_on')    ?? true;
      _claudeOn        = prefs.getBool('slv_claude_on')    ?? true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('slv_gemini_key', _geminiCtrl.text.trim());
    await prefs.setString('slv_key',        _claudeCtrl.text.trim());
    await prefs.setBool('slv_gemini_on',    _geminiOn);
    await prefs.setBool('slv_claude_on',    _claudeOn);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('API keys saved ✅'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final geminiConfigured = _geminiCtrl.text.trim().isNotEmpty;
    final claudeConfigured = _claudeCtrl.text.trim().isNotEmpty;
    final anyConfigured = (_geminiOn && geminiConfigured) || (_claudeOn && claudeConfigured);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: kAccent.withOpacity(0.1), shape: BoxShape.circle),
            child: const Center(child: Text('🔑', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('OCR API Keys',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
            Text('Admin only · Keys stored on device',
                style: TextStyle(color: kMuted, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 20),

        _ApiKeyRow(
          color: const Color(0xFF4285F4),
          label: 'Gemini',
          badge: 'FREE',
          badgeColor: kSecondary,
          controller: _geminiCtrl,
          obscure: _geminiObscure,
          enabled: _geminiOn,
          configured: geminiConfigured,
          onToggleObscure: () => setState(() => _geminiObscure = !_geminiObscure),
          onToggleEnabled: (v) => setState(() => _geminiOn = v),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        _ApiKeyRow(
          color: const Color(0xFFD97706),
          label: 'Claude',
          badge: 'PAID',
          badgeColor: kRed,
          controller: _claudeCtrl,
          obscure: _claudeObscure,
          enabled: _claudeOn,
          configured: claudeConfigured,
          onToggleObscure: () => setState(() => _claudeObscure = !_claudeObscure),
          onToggleEnabled: (v) => setState(() => _claudeOn = v),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: anyConfigured ? kSecondary.withOpacity(0.08) : kRed.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: anyConfigured ? kSecondary.withOpacity(0.2) : kRed.withOpacity(0.2)),
          ),
          child: Row(children: [
            Text(anyConfigured ? '✅' : '⚠️', style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text(
              anyConfigured ? 'OCR engine ready' : 'No OCR engine configured',
              style: TextStyle(
                  color: anyConfigured ? kSecondary : kRed,
                  fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const Spacer(),
            Text('🔒 Stored locally',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: _saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('✅  Save API Keys'),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _geminiCtrl.dispose();
    _claudeCtrl.dispose();
    super.dispose();
  }
}

// ── Shared handle widget ──────────────────────────────────────────────────────
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
          color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
    ),
  );
}

// ── Single API key input row ──────────────────────────────────────────────────
class _ApiKeyRow extends StatelessWidget {
  final Color                color;
  final String               label;
  final String               badge;
  final Color                badgeColor;
  final TextEditingController controller;
  final bool                 obscure;
  final bool                 enabled;
  final bool                 configured;
  final VoidCallback         onToggleObscure;
  final ValueChanged<bool>   onToggleEnabled;
  final ValueChanged<String> onChanged;

  const _ApiKeyRow({
    required this.color,
    required this.label,
    required this.badge,
    required this.badgeColor,
    required this.controller,
    required this.obscure,
    required this.enabled,
    required this.configured,
    required this.onToggleObscure,
    required this.onToggleEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: enabled ? Colors.white : const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: enabled && configured
              ? kSecondary.withOpacity(0.4)
              : const Color(0xFFE5E7EB)),
    ),
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
        child: Row(children: [
          Container(width: 32, height: 32,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeColor.withOpacity(0.3)),
            ),
            child: Text(badge,
                style: TextStyle(color: badgeColor, fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
          const Spacer(),
          Text(configured ? 'Configured' : 'Not configured',
              style: TextStyle(
                  color: configured ? kSecondary : Colors.grey.shade400, fontSize: 11)),
          const SizedBox(width: 8),
          Switch(value: enabled, onChanged: onToggleEnabled,
              activeColor: kPrimary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'Paste your $label API key here',
            hintStyle: const TextStyle(fontSize: 12),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18, color: kMuted,
              ),
              onPressed: onToggleObscure,
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ),
      ),
    ]),
  );
}

// ── Category chip ─────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Icon(Icons.add_circle_outline, size: 14, color: color),
      ]),
    ),
  );
}
