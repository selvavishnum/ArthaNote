import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _QrAttendanceSheet(p: p),
                ),
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
                subtitle: 'Export, import & sync your data',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _BackupSheet(p: p),
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

          const SizedBox(height: 20),

          // ── Privacy Policy & Terms ─────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://selvavishnum.github.io/Kannakupilai/privacy.html'),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                child: const Text('Privacy Policy'),
              ),
              Text('·', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://selvavishnum.github.io/Kannakupilai/privacy.html#terms'),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF059669),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                child: const Text('Terms & Conditions'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'v1.0.4 · ArthaNote by Tulsi Groups',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 8),
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

// ── QR Attendance sheet ───────────────────────────────────────────────────────
class _QrAttendanceSheet extends StatefulWidget {
  final AppProvider p;
  const _QrAttendanceSheet({required this.p});
  @override
  State<_QrAttendanceSheet> createState() => _QrAttendanceSheetState();
}

class _QrAttendanceSheetState extends State<_QrAttendanceSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _shopId = '';
  DateTime _summaryMonth = DateTime.now();
  DateTime _markDate     = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab    = TabController(length: 2, vsync: this);
    _shopId = widget.p.shops.values.firstOrNull?.id ?? '';
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String get _qrUrl {
    final shop = widget.p.shops[_shopId];
    final name  = Uri.encodeComponent(shop?.name ?? 'Shop');
    return 'https://selvavishnum.github.io/Kannakupilai/attend.html'
        '?bid=${widget.p.businessId}&shop=$_shopId&sname=$name';
  }

  @override
  Widget build(BuildContext context) {
    final shops = widget.p.shops;
    return SizedBox.expand(
      child: Column(children: [
        const SizedBox(height: 8),
        const _SheetHandle(),
        const SizedBox(height: 12),
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('📋', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Attendance',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
            ),
            if (shops.length > 1)
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _shopId.isEmpty ? null : _shopId,
                  isDense: true,
                  onChanged: (v) => setState(() => _shopId = v ?? _shopId),
                  items: shops.values.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text('${s.icon} ${s.name}',
                        style: const TextStyle(fontSize: 13)),
                  )).toList(),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        // Tab bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: Colors.white,
              unselectedLabelColor: kMuted,
              indicator: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: const [
                Tab(text: '✅ Mark Attendance'),
                Tab(text: '📊 Summary'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildMarkTab(shops),
              _buildSummaryTab(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Mark Attendance tab ────────────────────────────────────────────────────
  Widget _buildMarkTab(Map<String, dynamic> shops) {
    final shop = widget.p.shops[_shopId];
    if (shop == null) {
      return const Center(child: Text('No shops configured.', style: TextStyle(color: kMuted)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(children: [
        // Shop selector (if only 1 shop show name here)
        if (widget.p.shops.length == 1) ...[
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(shop.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(shop.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: kPrimary)),
          ]),
          const SizedBox(height: 4),
        ],
        // QR Card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimary.withOpacity(0.2)),
            boxShadow: kCardShadow,
          ),
          child: Column(children: [
            // Green header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: const Column(children: [
                Text('📒', style: TextStyle(fontSize: 26)),
                SizedBox(height: 4),
                Text('ArthaNote',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                Text('Staff Attendance Scanner',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(shop.icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(shop.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kPrimary)),
            ]),
            const SizedBox(height: 4),
            Text('🔒 Permanent QR — Auto date daily',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
            const SizedBox(height: 16),
            // QR code
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: QrImageView(
                data: _qrUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF065f46),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF065f46),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Instructions
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📱 எப்படி scan பண்றது?',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kPrimary)),
                  const SizedBox(height: 8),
                  ...[
                    '1. Phone camera திறங்க',
                    '2. இந்த QR-ஐ point பண்ணுங்க',
                    '3. உங்கள் பேரை tap பண்ணுங்க',
                    '4. ✅ Attendance complete!',
                  ].map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(s, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Share / Open link buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Share.share(
                      'Attendance QR for ${shop.name}: $_qrUrl',
                    ),
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('Share Link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(_qrUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: const Text('Open'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }

  // ── Summary tab ────────────────────────────────────────────────────────────
  Widget _buildSummaryTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final now = DateTime.now();
                // Simple month picker via showDatePicker (day doesn't matter)
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _summaryMonth,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(now.year, now.month),
                  initialDatePickerMode: DatePickerMode.year,
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(primary: kPrimary),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _summaryMonth = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_month_outlined, size: 16, color: kPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('MMM yyyy').format(_summaryMonth),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18, color: kMuted),
                ]),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('attendance')
              .where('businessId', isEqualTo: widget.p.businessId)
              .where('shopId', isEqualTo: _shopId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: kPrimary));
            }
            final docs = snap.data?.docs ?? [];
            // Filter to selected month
            final monthStr = DateFormat('yyyy-MM').format(_summaryMonth);
            final monthDocs = docs.where((d) {
              final date = (d.data()['date'] as String?) ?? '';
              return date.startsWith(monthStr);
            }).toList();

            if (monthDocs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📭', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text('No attendance in ${DateFormat('MMM yyyy').format(_summaryMonth)}',
                        style: const TextStyle(color: kMuted, fontSize: 13)),
                  ],
                ),
              );
            }

            // Group by staffName
            final Map<String, List<Map<String, dynamic>>> byStaff = {};
            for (final doc in monthDocs) {
              final d    = doc.data();
              final name = (d['staffName'] as String?) ?? 'Unknown';
              byStaff.putIfAbsent(name, () => []).add(d);
            }

            // Count working days in month
            final int year  = _summaryMonth.year;
            final int month = _summaryMonth.month;
            final int daysInMonth = DateTime(year, month + 1, 0).day;
            final int today = DateTime.now().day;
            final int workingDays = (month == DateTime.now().month && year == DateTime.now().year)
                ? today
                : daysInMonth;

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: byStaff.length,
              itemBuilder: (ctx, i) {
                final entry    = byStaff.entries.elementAt(i);
                final name     = entry.key;
                final records  = entry.value;
                final presentDays = records
                    .where((r) => r['type'] == 'in' || r['type'] == null)
                    .map((r) => r['date'] as String?)
                    .whereType<String>()
                    .toSet()
                    .length;
                final absentDays = workingDays - presentDays;
                final rate = workingDays > 0
                    ? (presentDays / workingDays * 100).round()
                    : 0;

                // Average hours calculation
                final Map<String, List<Map<String, dynamic>>> byDay = {};
                for (final r in records) {
                  final date = (r['date'] as String?) ?? '';
                  byDay.putIfAbsent(date, () => []).add(r);
                }
                double totalHrs = 0;
                int hrCount = 0;
                for (final dayRecs in byDay.values) {
                  final inRec  = dayRecs.where((r) => r['type'] == 'in' || r['type'] == null).firstOrNull;
                  final outRec = dayRecs.where((r) => r['type'] == 'out').firstOrNull;
                  if (inRec != null && outRec != null) {
                    final inMs  = (inRec['timeRaw']  as num?)?.toDouble() ?? 0;
                    final outMs = (outRec['timeRaw'] as num?)?.toDouble() ?? 0;
                    if (outMs > inMs) {
                      totalHrs += (outMs - inMs) / 3600000;
                      hrCount++;
                    }
                  }
                }
                final avgHrs = hrCount > 0 ? (totalHrs / hrCount) : 0.0;

                final presentDatesList = records
                    .where((r) => r['type'] == 'in' || r['type'] == null)
                    .map((r) => r['date'] as String?)
                    .whereType<String>()
                    .toSet()
                    .map((d) => d.split('-').last)
                    .toList()
                  ..sort();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    boxShadow: kCardShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Header row
                      Row(children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: kPrimary,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(monthStr,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('$presentDays',
                              style: const TextStyle(
                                  color: kRed, fontWeight: FontWeight.w800, fontSize: 20)),
                          Text('days / $workingDays working',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                        ]),
                      ]),
                      const SizedBox(height: 10),
                      // Rate row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Attendance Rate',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          Text('$rate%',
                              style: const TextStyle(
                                  color: kRed, fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: rate / 100,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              rate >= 80 ? kSecondary : kRed),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Stats row
                      IntrinsicHeight(
                        child: Row(children: [
                          _StatCell(label: 'PRESENT', value: '$presentDays', color: kSecondary),
                          const VerticalDivider(color: Color(0xFFE5E7EB), width: 1),
                          _StatCell(label: 'ABSENT', value: '${absentDays < 0 ? 0 : absentDays}', color: kRed),
                          const VerticalDivider(color: Color(0xFFE5E7EB), width: 1),
                          _StatCell(
                            label: 'AVG HRS',
                            value: hrCount > 0 ? avgHrs.toStringAsFixed(1) : '—',
                            color: kAccent,
                          ),
                        ]),
                      ),
                      if (presentDatesList.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('வந்த நாட்கள்',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: presentDatesList.map((day) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: kSecondary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kSecondary.withOpacity(0.3)),
                            ),
                            child: Text(day,
                                style: TextStyle(
                                    color: kSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
                          )).toList(),
                        ),
                      ],
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _StatCell({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: kMuted, fontSize: 9, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

// ── Backup sheet ──────────────────────────────────────────────────────────────
class _BackupSheet extends StatefulWidget {
  final AppProvider p;
  const _BackupSheet({required this.p});
  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  bool _syncing   = false;
  bool _exporting = false;
  bool _importing = false;
  bool _csvExp    = false;
  bool _clearing  = false;

  Future<void> _forceSync() async {
    setState(() => _syncing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('kp_txs_cache');
      await prefs.remove('kp_cfg_cache');
      await prefs.remove('kp_me_cache');
      await prefs.remove('kp_cache_ts');
      await prefs.remove('kp_sups_cache');
      await prefs.remove('kp_bills_cache');
      await widget.p.init(FirebaseAuth.instance.currentUser!.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✅ Synced from Firebase!'),
          backgroundColor: kSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _exportJson() async {
    setState(() => _exporting = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('businessId', isEqualTo: widget.p.businessId)
          .get();
      final data = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      final json = const JsonEncoder.withIndent('  ').convert({
        'exported':     DateTime.now().toIso8601String(),
        'businessId':   widget.p.businessId,
        'count':        data.length,
        'transactions': data,
      });
      final fileName = 'arthanote_backup_${DateFormat('yyyyMMdd').format(DateTime.now())}.json';
      final tempFile = File('${Directory.systemTemp.path}/$fileName');
      await tempFile.writeAsString(json);
      await Share.shareXFiles([XFile(tempFile.path)], subject: 'ArthaNote Backup');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importJson() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.bytes == null) {
        setState(() => _importing = false);
        return;
      }
      final bytes  = result.files.single.bytes!;
      final jsonStr = utf8.decode(bytes);
      final parsed  = jsonDecode(jsonStr) as Map<String, dynamic>;
      final txns    = (parsed['transactions'] as List<dynamic>?) ?? [];
      if (txns.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No transactions found in file.'),
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _importing = false);
        return;
      }

      // Batch write in groups of 500
      final col = FirebaseFirestore.instance.collection('transactions');
      int imported = 0;
      for (int i = 0; i < txns.length; i += 400) {
        final batch = FirebaseFirestore.instance.batch();
        final chunk = txns.sublist(i, i + 400 > txns.length ? txns.length : i + 400);
        for (final item in chunk) {
          final m = item as Map<String, dynamic>;
          final id = (m['id'] as String?) ?? const Uuid().v4();
          final ref = col.doc(id);
          // Convert date if needed
          if (m['date'] is String) {
            m['date'] = Timestamp.fromDate(DateTime.parse(m['date']));
          }
          batch.set(ref, m, SetOptions(merge: true));
          imported++;
        }
        await batch.commit();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Imported $imported entries!'),
          backgroundColor: kSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _csvExp = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('businessId', isEqualTo: widget.p.businessId)
          .get();
      final buf = StringBuffer();
      buf.writeln('Date,Shop,Type,Amount,Description');
      for (final doc in snap.docs) {
        final d    = doc.data();
        final date = (d['date'] is Timestamp)
            ? DateFormat('yyyy-MM-dd').format((d['date'] as Timestamp).toDate())
            : (d['date']?.toString() ?? '');
        final shop = (d['shopName'] as String?) ?? '';
        final type = (d['type'] as String?) ?? '';
        final amt  = (d['amount'] as num?)?.toString() ?? '';
        final desc = ((d['desc'] as String?) ?? '').replaceAll(',', ';');
        buf.writeln('$date,$shop,$type,$amt,$desc');
      }
      final csvName = 'arthanote_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final tempFile = File('${Directory.systemTemp.path}/$csvName');
      await tempFile.writeAsString(buf.toString());
      await Share.shareXFiles([XFile(tempFile.path)], subject: 'ArthaNote CSV Export');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CSV export failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _csvExp = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Local Cache?'),
        content: const Text(
            'This clears locally cached data. All data will reload from Firebase on next open. '
            'No data will be deleted from the cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('kp_txs_cache');
    await prefs.remove('kp_cfg_cache');
    await prefs.remove('kp_me_cache');
    await prefs.remove('kp_cache_ts');
    await prefs.remove('kp_sups_cache');
    await prefs.remove('kp_bills_cache');
    if (mounted) {
      setState(() => _clearing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('🗑️ Cache cleared. Fresh load on next open.'),
        backgroundColor: kSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _SheetHandle(),
        const SizedBox(height: 18),
        const Row(children: [
          Text('💾', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Text('Backup & Restore',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kPrimary)),
        ]),
        const SizedBox(height: 16),
        // Cloud Sync info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSecondary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kSecondary.withOpacity(0.2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('☁️', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cloud Sync',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kPrimary)),
                const SizedBox(height: 2),
                Text('Your data is stored securely in Firebase',
                    style: TextStyle(color: kSecondary, fontSize: 11)),
                const SizedBox(height: 6),
                Text(
                  'All entries are auto-saved to Firebase cloud. Use the options below to '
                  'export a local copy or restore from file.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        // Force Sync
        _BackupButton(
          label: '↻  Force Sync to Cloud',
          color: kPrimary,
          textColor: Colors.white,
          loading: _syncing,
          onTap: _forceSync,
        ),
        const SizedBox(height: 10),
        // Export JSON
        _BackupButton(
          label: '🧺  Export JSON Backup',
          color: const Color(0xFF2563EB),
          textColor: Colors.white,
          loading: _exporting,
          onTap: _exportJson,
        ),
        const SizedBox(height: 10),
        // Import JSON
        _BackupButton(
          label: '📂  Import JSON Backup',
          color: Colors.white,
          textColor: const Color(0xFF2563EB),
          borderColor: const Color(0xFF2563EB),
          loading: _importing,
          onTap: _importJson,
        ),
        const SizedBox(height: 10),
        // Export CSV
        _BackupButton(
          label: '📊  Export CSV',
          color: Colors.white,
          textColor: kAccent,
          borderColor: kAccent,
          loading: _csvExp,
          onTap: _exportCsv,
        ),
        const SizedBox(height: 10),
        // Clear Cache
        _BackupButton(
          label: '🗑️  Clear Local Cache',
          color: kRed,
          textColor: Colors.white,
          loading: _clearing,
          onTap: _clearCache,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Cache cleared = fresh load from Firebase on next open',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
              textAlign: TextAlign.center),
        ),
      ]),
    );
  }
}

class _BackupButton extends StatelessWidget {
  final String    label;
  final Color     color;
  final Color     textColor;
  final Color?    borderColor;
  final bool      loading;
  final VoidCallback onTap;
  const _BackupButton({
    required this.label,
    required this.color,
    required this.textColor,
    this.borderColor,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        elevation: borderColor != null ? 0 : 2,
        side: borderColor != null ? BorderSide(color: borderColor!) : BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: loading
          ? SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(color: textColor, strokeWidth: 2.5))
          : Text(label),
    ),
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
