import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
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
    final role    = (profile['role']  as String?) ?? 'owner';
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
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: kText,
                        ),
                      ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatRole(role),
                        style: const TextStyle(
                          color: Color(0xFF7C3AED),
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
                onTap: () => _comingSoon(context, l),
              ),
              _ItemDivider(),
              _SettingsItem(
                icon: Icons.store_outlined,
                iconColor: kSecondary,
                title: t('shop_names', l),
                subtitle: 'Edit or remove your shops',
                onTap: () => _comingSoon(context, l),
              ),
              _ItemDivider(),
              _SettingsItem(
                icon: Icons.people_outline,
                iconColor: const Color(0xFF8B5CF6),
                title: t('staff', l),
                subtitle: 'Add, edit or remove staff members',
                onTap: () => _comingSoon(context, l),
              ),
              _ItemDivider(),
              _SettingsItem(
                icon: Icons.qr_code_outlined,
                iconColor: kPrimary,
                title: t('qr_attendance', l),
                subtitle: 'Generate QR & view attendance',
                onTap: () => _comingSoon(context, l),
              ),
              _ItemDivider(),
              _SettingsItem(
                icon: Icons.receipt_outlined,
                iconColor: kAccent,
                title: t('gst_settings', l),
                subtitle: 'Enable GST & choose tax rate',
                onTap: () => _comingSoon(context, l),
              ),
              _ItemDivider(),
              _SettingsItem(
                icon: Icons.edit_note_outlined,
                iconColor: const Color(0xFF0EA5E9),
                title: t('categories', l),
                subtitle: 'Sales & expense categories per shop',
                onTap: () => _comingSoon(context, l),
              ),
              _ItemDivider(),
              _SettingsItem(
                icon: Icons.save_outlined,
                iconColor: const Color(0xFF10B981),
                title: t('backup', l),
                subtitle: 'Export or restore your data',
                onTap: () => _comingSoon(context, l),
                isLast: !isAdmin,
              ),
              if (isAdmin) ...[
                _ItemDivider(),
                _SettingsItem(
                  icon: Icons.key_outlined,
                  iconColor: const Color(0xFFD97706),
                  title: '🔑 OCR API Keys',
                  subtitle: 'Gemini & Claude API keys',
                  onTap: () => _showOcrApiKeys(context),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('language', l),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: kText,
                        ),
                      ),
                      Text(
                        l == 'en' ? 'English' : 'தமிழ்',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
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
                      if (states.contains(WidgetState.selected)) {
                        return kPrimary;
                      }
                      return Colors.white;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return kText;
                    }),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Sign Out outlined red button ──────────────────────────────
          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context, p),
            icon: const Icon(Icons.logout, color: kRed),
            label: Text(
              t('sign_out', l),
              style: const TextStyle(color: kRed),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              side: const BorderSide(color: kRed),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              foregroundColor: kRed,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOcrApiKeys(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _OcrApiKeysSheet(),
    );
  }

  void _comingSoon(BuildContext context, String l) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('coming_soon', l)),
        backgroundColor: kPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'owner':   return 'Admin';
      case 'manager': return 'Manager';
      case 'cashier': return 'Cashier';
      default:
        return role.isEmpty
            ? 'Admin'
            : '${role[0].toUpperCase()}${role.substring(1)}';
    }
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
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: kText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right,
            color: Color(0xFFD1D5DB), size: 20),
      ]),
    ),
  );
}

// ── Thin inset divider ────────────────────────────────────────────────────────
class _ItemDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(left: 68),
    child: Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6)),
  );
}

// ── OCR API Keys bottom sheet (admin only) ────────────────────────────────────
class _OcrApiKeysSheet extends StatefulWidget {
  const _OcrApiKeysSheet();
  @override
  State<_OcrApiKeysSheet> createState() => _OcrApiKeysSheetState();
}

class _OcrApiKeysSheetState extends State<_OcrApiKeysSheet> {
  final _geminiCtrl = TextEditingController();
  final _claudeCtrl = TextEditingController();
  bool  _geminiOn   = true;
  bool  _claudeOn   = true;
  bool  _saving     = false;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('API keys saved ✅'),
          backgroundColor: kSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final geminiConfigured = _geminiCtrl.text.trim().isNotEmpty;
    final claudeConfigured = _claudeCtrl.text.trim().isNotEmpty;
    final anyConfigured    = (_geminiOn && geminiConfigured) ||
                             (_claudeOn && claudeConfigured);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 18),

        // Header
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.1),
              shape: BoxShape.circle),
            child: const Center(
              child: Text('🔑', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OCR API Keys',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: kPrimary,
                  ),
                ),
                Text(
                  'Admin only · Keys stored on device',
                  style: TextStyle(color: kMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 20),

        // Gemini row
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

        // Claude row
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

        // Status row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: anyConfigured
                ? kSecondary.withOpacity(0.08)
                : kRed.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: anyConfigured
                  ? kSecondary.withOpacity(0.2)
                  : kRed.withOpacity(0.2),
            ),
          ),
          child: Row(children: [
            Text(
              anyConfigured ? '✅' : '⚠️',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 8),
            Text(
              anyConfigured
                  ? 'OCR engine ready'
                  : 'No OCR engine configured',
              style: TextStyle(
                color: anyConfigured ? kSecondary : kRed,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              '🔒 Stored locally',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ]),
        ),
        const SizedBox(height: 18),

        // Save button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
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
            : const Color(0xFFE5E7EB),
      ),
    ),
    child: Column(children: [
      // Header row
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: kText,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeColor.withOpacity(0.3)),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: badgeColor,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          Text(
            configured ? 'Configured' : 'Not configured',
            style: TextStyle(
              color: configured ? kSecondary : Colors.grey.shade400,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: enabled,
            onChanged: onToggleEnabled,
            activeColor: kPrimary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ]),
      ),
      // Key input
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
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: kMuted,
              ),
              onPressed: onToggleObscure,
            ),
            suffixIconConstraints: const BoxConstraints(
                minWidth: 36, minHeight: 36),
          ),
        ),
      ),
    ]),
  );
}
