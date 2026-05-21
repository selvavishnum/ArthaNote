import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../l10n.dart';
import '../providers/app_provider.dart';

class ScanTab extends StatefulWidget {
  const ScanTab({super.key});
  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  String   _shopId      = '';
  DateTime _ledgerDate  = DateTime.now();
  bool     _imageSelected = false;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _ledgerDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _ledgerDate = picked);
    }
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('OCR Scan — coming soon'),
        backgroundColor: kPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final l = p.lang;

    if (_shopId.isEmpty && p.shops.isNotEmpty) {
      _shopId = p.shops.values.first.id;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Section title ───────────────────────────────────────────────
          Text(
            '📷 ${t("upload_ledger", l).toUpperCase()}',
            style: const TextStyle(
              color: kPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),

          // ── Shop dropdown + Date picker row ─────────────────────────────
          Row(children: [
            // Shop dropdown
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SHOP',
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: kCardShadow,
                    ),
                    child: p.shops.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              'No shops',
                              style: TextStyle(color: kMuted, fontSize: 13),
                            ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _shopId.isEmpty ? null : _shopId,
                              isExpanded: true,
                              isDense: true,
                              hint: Text(
                                t('select_shop', l),
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 13,
                                ),
                              ),
                              icon: const Icon(Icons.expand_more,
                                  color: kMuted, size: 20),
                              onChanged: (v) =>
                                  setState(() => _shopId = v ?? ''),
                              items: p.shops.values
                                  .map((s) => DropdownMenuItem(
                                        value: s.id,
                                        child: Text(
                                          '${s.icon} ${s.name}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Date picker
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LEDGER DATE',
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _pickDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: kCardShadow,
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 15, color: kPrimary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            DateFormat('dd MMM yyyy').format(_ledgerDate),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            color: kMuted, size: 20),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 12),

          // ── Info box ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('📅', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select the date written on your ledger before uploading',
                    style: TextStyle(
                      color: Color(0xFF1D4ED8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Dashed upload zone ──────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _imageSelected = !_imageSelected),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: _imageSelected
                    ? kPrimary.withOpacity(0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _imageSelected
                      ? kPrimary
                      : const Color(0xFFD1D5DB),
                  width: 1.5,
                ),
                boxShadow: kCardShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _imageSelected ? '✅' : '📜',
                    style: const TextStyle(fontSize: 44),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _imageSelected
                        ? 'Photo selected'
                        : t('tap_photo', l),
                    style: TextStyle(
                      color: _imageSelected ? kPrimary : kText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _imageSelected
                        ? 'Tap again to change'
                        : 'Gallery or Camera · JPG PNG HEIC',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Action buttons ──────────────────────────────────────────────
          Row(children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: () => _showComingSoon(context),
                icon: const Text('📷', style: TextStyle(fontSize: 16)),
                label: const Text(
                  'Scan OCR',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: () => _showComingSoon(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  foregroundColor: kText,
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                child: const Text('Manual Entry'),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // ── OCR tips card ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: kCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Text('💡', style: TextStyle(fontSize: 15)),
                  SizedBox(width: 8),
                  Text(
                    'TIPS FOR BEST RESULTS',
                    style: TextStyle(
                      color: kPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                ...[
                  'Good lighting — avoid shadows on the page',
                  'Keep the ledger flat and straight',
                  'Ensure all text is clearly visible',
                  'Supports Tamil & English numerals',
                ].map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(color: kPrimary, fontSize: 13),
                      ),
                      Expanded(
                        child: Text(
                          tip,
                          style: const TextStyle(
                            color: kMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
