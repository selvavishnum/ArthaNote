import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../l10n.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p     = context.watch<AppProvider>();
    final l     = p.lang;
    final profile = p.profile;
    final name    = (profile['name']  as String?) ?? '';
    final email   = (profile['email'] as String?) ?? '';
    final role    = (profile['role']  as String?) ?? 'owner';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kText,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          t('settings', l),
          style: const TextStyle(
            color: kText,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(0),
        children: [
          // ── Profile card ───────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
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
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: kText)),
                    if (email.isNotEmpty)
                      Text(email,
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xFF7C3AED),
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Settings list ──────────────────────────────────────────────────
          Container(
            color: Colors.white,
            child: Column(children: [
              _SettingsTile(
                icon: '👤',
                bgColor: const Color(0xFFEFF6FF),
                title: t('profile', l),
                subtitle: 'Your account details',
                onTap: () => _comingSoon(context, l),
              ),
              const Divider(height: 1, indent: 72),
              _SettingsTile(
                icon: '🏪',
                bgColor: const Color(0xFFF0FDF4),
                title: t('shop_names', l),
                subtitle: 'Edit or remove your shops',
                onTap: () => _comingSoon(context, l),
              ),
              const Divider(height: 1, indent: 72),
              _SettingsTile(
                icon: '👥',
                bgColor: const Color(0xFFEDE9FE),
                title: t('staff', l),
                subtitle: 'Add, edit or remove staff members',
                onTap: () => _comingSoon(context, l),
              ),
              const Divider(height: 1, indent: 72),
              _SettingsTile(
                icon: '📷',
                bgColor: const Color(0xFFFFF7ED),
                title: t('qr_attendance', l),
                subtitle: 'Generate QR & view attendance',
                onTap: () => _comingSoon(context, l),
              ),
              const Divider(height: 1, indent: 72),
              _SettingsTile(
                icon: '🧾',
                bgColor: const Color(0xFFF0FDF4),
                title: t('gst_settings', l),
                subtitle: 'Enable GST & choose tax rate',
                onTap: () => _comingSoon(context, l),
              ),
              const Divider(height: 1, indent: 72),
              _SettingsTile(
                icon: '✏️',
                bgColor: const Color(0xFFFFF7ED),
                title: t('categories', l),
                subtitle: 'Sales & expense categories per shop',
                onTap: () => _comingSoon(context, l),
              ),
              const Divider(height: 1, indent: 72),
              _SettingsTile(
                icon: '💾',
                bgColor: const Color(0xFFF1F5F9),
                title: t('backup', l),
                subtitle: 'Export or restore your data',
                onTap: () => _comingSoon(context, l),
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Sign Out ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, p),
              icon: const Text('🚪', style: TextStyle(fontSize: 16)),
              label: Text(
                t('sign_out', l),
                style: const TextStyle(
                    color: kRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                side: const BorderSide(color: kRed),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Sign Out'),
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

// ── Settings tile ─────────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final String    icon;
  final Color     bgColor;
  final String    title;
  final String    subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: kText)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: kMuted, size: 20),
      ]),
    ),
  );
}
