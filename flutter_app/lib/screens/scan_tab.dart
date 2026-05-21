import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../l10n.dart';
import '../models/txn.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';

class ScanTab extends StatefulWidget {
  const ScanTab({super.key});
  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  final _db     = DbService();
  final _picker = ImagePicker();
  String   _shopId     = '';
  DateTime _ledgerDate = DateTime.now();
  File?    _image;
  bool     _scanning   = false;
  String   _geminiKey  = '';

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _geminiKey = prefs.getString('slv_gemini_key') ?? '');
  }

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
    if (picked != null && mounted) setState(() => _ledgerDate = picked);
  }

  Future<void> _pickImage(ImageSource source) async {
    final xFile = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (xFile != null && mounted) setState(() => _image = File(xFile.path));
  }

  void _showImageSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt, color: kPrimary),
              ),
              title: const Text('Camera', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Take a photo now'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library, color: kSecondary),
              ),
              title: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Choose from your photos'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _runOcr(BuildContext context, AppProvider p) async {
    if (_image == null) {
      _showSnack(context, 'Please select a photo first', kRed);
      return;
    }
    if (_geminiKey.isEmpty) {
      _showSnack(context, 'Add Gemini API key in Settings → OCR API Keys', kRed);
      return;
    }

    setState(() => _scanning = true);
    try {
      final bytes  = await _image!.readAsBytes();
      final b64    = base64Encode(bytes);

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiKey',
      );
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'inline_data': {'mime_type': 'image/jpeg', 'data': b64}},
                {
                  'text':
                      'Extract all ledger entries from this image. '
                      'Return a JSON array only, no markdown, no explanation. '
                      'Format: [{"desc":"item name","amount":100,"type":"sale"}] '
                      'where type is "sale", "expense", or "payment". '
                      'If no entries found, return [].',
                },
              ],
            },
          ],
        }),
      );

      if (!mounted) return;
      if (resp.statusCode != 200) {
        throw Exception('Gemini error ${resp.statusCode}');
      }

      final json   = jsonDecode(resp.body) as Map<String, dynamic>;
      final text   = ((json['candidates'] as List).first['content']['parts']
              as List)
          .first['text'] as String;

      final cleaned = text
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

      final raw = jsonDecode(cleaned) as List<dynamic>;
      if (raw.isEmpty) {
        _showSnack(context, 'No entries detected in the image', kAccent);
        return;
      }

      final shopName = p.shops[_shopId]?.name ?? '';
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _ParsedEntriesSheet(
          entries: raw.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          shopId: _shopId,
          shopName: shopName,
          date: _ledgerDate,
          businessId: p.businessId,
          db: _db,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      _showSnack(context, 'OCR failed: ${msg.length > 80 ? msg.substring(0, 80) : msg}', kRed);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _showSnack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
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

          // ── No API key warning ──────────────────────────────────────────
          if (_geminiKey.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kRed.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kRed.withOpacity(0.2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚠️', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gemini API key not configured.\nGo to Settings → OCR API Keys to add your key.',
                      style: TextStyle(
                        color: kRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Shop dropdown + Date picker row ─────────────────────────────
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SHOP', style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: kCardShadow,
                    ),
                    child: p.shops.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text('No shops', style: TextStyle(color: kMuted, fontSize: 13)),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _shopId.isEmpty ? null : _shopId,
                              isExpanded: true,
                              isDense: true,
                              hint: Text(t('select_shop', l), style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              icon: const Icon(Icons.expand_more, color: kMuted, size: 20),
                              onChanged: (v) => setState(() => _shopId = v ?? ''),
                              items: p.shops.values.map((s) => DropdownMenuItem(
                                value: s.id,
                                child: Text('${s.icon} ${s.name}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                              )).toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LEDGER DATE', style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _pickDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: kCardShadow,
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined, size: 15, color: kPrimary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            DateFormat('dd MMM yyyy').format(_ledgerDate),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: kMuted, size: 20),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Upload zone ─────────────────────────────────────────────────
          GestureDetector(
            onTap: () => _showImageSourceSheet(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: _image != null ? 240 : 200,
              decoration: BoxDecoration(
                color: _image != null ? kPrimary.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _image != null ? kPrimary : const Color(0xFFD1D5DB),
                  width: 1.5,
                ),
                boxShadow: kCardShadow,
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(children: [
                        Image.file(_image!, fit: BoxFit.cover,
                            width: double.infinity, height: double.infinity),
                        Positioned(
                          bottom: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Tap to change',
                                style: TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ]),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('📜', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 14),
                        Text(t('tap_photo', l),
                            style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('Gallery or Camera · JPG PNG HEIC',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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
                onPressed: _scanning ? null : () => _runOcr(context, p),
                icon: _scanning
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('📷', style: TextStyle(fontSize: 16)),
                label: Text(
                  _scanning ? 'Scanning...' : 'Scan OCR',
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: () => _showImageSourceSheet(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  foregroundColor: kText,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                child: const Text('Pick Photo'),
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
                  Text('TIPS FOR BEST RESULTS',
                      style: TextStyle(color: kPrimary, fontSize: 11,
                          fontWeight: FontWeight.w800, letterSpacing: 1.0)),
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
                      const Text('• ', style: TextStyle(color: kPrimary, fontSize: 13)),
                      Expanded(child: Text(tip,
                          style: const TextStyle(color: kMuted, fontSize: 12))),
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

// ── Parsed entries confirmation sheet ─────────────────────────────────────────
class _ParsedEntriesSheet extends StatefulWidget {
  final List<Map<String, dynamic>> entries;
  final String    shopId;
  final String    shopName;
  final DateTime  date;
  final String    businessId;
  final DbService db;

  const _ParsedEntriesSheet({
    required this.entries,
    required this.shopId,
    required this.shopName,
    required this.date,
    required this.businessId,
    required this.db,
  });

  @override
  State<_ParsedEntriesSheet> createState() => _ParsedEntriesSheetState();
}

class _ParsedEntriesSheetState extends State<_ParsedEntriesSheet> {
  late List<Map<String, dynamic>> _entries;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries.map((e) => {
      'desc':   (e['desc']   ?? '').toString(),
      'amount': (e['amount'] is num)
          ? (e['amount'] as num).toDouble()
          : double.tryParse(e['amount'].toString()) ?? 0.0,
      'type':   (e['type']   ?? 'sale').toString(),
    }).toList();
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      for (final entry in _entries) {
        await widget.db.addTxn(Txn(
          id:         '',
          businessId: widget.businessId,
          shop:       widget.shopId,
          shopName:   widget.shopName,
          date:       widget.date,
          type:       entry['type'] as String,
          amount:     entry['amount'] as double,
          desc:       entry['desc'] as String,
        ));
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${_entries.length} entries saved'),
          backgroundColor: kSecondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Text('📋', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            'Detected Entries (${_entries.length})',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kPrimary),
          ),
          const Spacer(),
          Text('Tap badge to change type',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
        ]),
        const SizedBox(height: 12),

        // Entries list
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final type  = entry['type'] as String;
              final color = type == 'sale'
                  ? kSecondary
                  : type == 'expense'
                      ? kRed
                      : kAccent;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Row(children: [
                  GestureDetector(
                    onTap: () {
                      const types = ['sale', 'expense', 'payment'];
                      final idx = types.indexOf(type);
                      setState(() => _entries[index]['type'] = types[(idx + 1) % 3]);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: color, borderRadius: BorderRadius.circular(6)),
                      child: Text(type.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry['desc'] as String,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '₹${(entry['amount'] as double).toStringAsFixed(0)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _entries.removeAt(index)),
                    child: const Icon(Icons.close, size: 18, color: Colors.grey),
                  ),
                ]),
              );
            },
          ),
        ),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: (_saving || _entries.isEmpty) ? null : _saveAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : Text('Save ${_entries.length} Entries to Ledger'),
          ),
        ),
      ]),
    );
  }
}
