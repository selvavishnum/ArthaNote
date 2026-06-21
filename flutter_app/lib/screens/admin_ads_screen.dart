import 'package:flutter/material.dart';
import '../models/ad_banner.dart';
import '../services/db_service.dart';
import '../theme.dart';

/// Admin-only screen to create, toggle, and delete premium ads.
/// Reachable from the Settings screen for admin users only.
class AdminAdsScreen extends StatefulWidget {
  const AdminAdsScreen({super.key});
  @override
  State<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends State<AdminAdsScreen> {
  final _db = DbService();

  void _openAddSheet([AdBanner? existing]) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl  = TextEditingController(text: existing?.description ?? '');
    final imgCtrl   = TextEditingController(text: existing?.imageUrl ?? '');
    final linkCtrl  = TextEditingController(text: existing?.linkUrl ?? '');
    final ctaCtrl   = TextEditingController(text: existing?.ctaText ?? 'Learn More');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(existing == null ? 'New Ad' : 'Edit Ad',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kPrimary)),
            const SizedBox(height: 16),
            _field(titleCtrl, 'Ad Title *', maxLines: 1),
            const SizedBox(height: 12),
            _field(descCtrl, 'Description', maxLines: 3),
            const SizedBox(height: 12),
            _field(imgCtrl, 'Image URL (optional)', maxLines: 1),
            const SizedBox(height: 12),
            _field(linkCtrl, 'Tap Link URL (optional)', maxLines: 1),
            const SizedBox(height: 12),
            _field(ctaCtrl, 'Button Text', maxLines: 1),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                if (existing == null) {
                  await _db.saveAd(AdBanner(
                    id: '',
                    title: title,
                    description: descCtrl.text.trim(),
                    imageUrl: imgCtrl.text.trim(),
                    linkUrl: linkCtrl.text.trim(),
                    ctaText: ctaCtrl.text.trim(),
                    active: true,
                    createdAt: DateTime.now(),
                  ));
                } else {
                  await _db.updateAd(existing.id, {
                    'title':       title,
                    'description': descCtrl.text.trim(),
                    'imageUrl':    imgCtrl.text.trim(),
                    'linkUrl':     linkCtrl.text.trim(),
                    'ctaText':     ctaCtrl.text.trim(),
                  });
                }
              },
              child: Text(existing == null ? 'Create Ad' : 'Save Changes',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Premium Ads',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Ad',
            onPressed: _openAddSheet,
          ),
        ],
      ),
      body: StreamBuilder<List<AdBanner>>(
        stream: _db.activeAdsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ads = snap.data ?? [];
          if (ads.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.campaign_outlined,
                      size: 64, color: Color(0xFFD1FAE5)),
                  const SizedBox(height: 16),
                  const Text('No ads yet',
                      style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first premium ad.',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _openAddSheet,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Ad'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: ads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final ad = ads[i];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFD1FAE5),
                    child: const Icon(Icons.campaign,
                        color: kPrimary, size: 20),
                  ),
                  title: Text(ad.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  subtitle: ad.description.isNotEmpty
                      ? Text(ad.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF6B7280), fontSize: 13))
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Active toggle
                      Switch(
                        value: ad.active,
                        activeColor: kPrimary,
                        onChanged: (v) =>
                            _db.updateAd(ad.id, {'active': v}),
                      ),
                      // Edit
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: Color(0xFF6B7280)),
                        onPressed: () => _openAddSheet(ad),
                      ),
                      // Delete
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFFDC2626)),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete Ad?'),
                              content:
                                  Text('Delete "${ad.title}"? This cannot be undone.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete',
                                        style: TextStyle(
                                            color: Color(0xFFDC2626)))),
                              ],
                            ),
                          );
                          if (ok == true) _db.deleteAd(ad.id);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        onPressed: _openAddSheet,
        icon: const Icon(Icons.add),
        label: const Text('New Ad',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
