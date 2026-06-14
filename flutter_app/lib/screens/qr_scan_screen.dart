import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final MobileScannerController _controller;
  bool _detected = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      final bid   = uri.queryParameters['bid'];
      final shop  = uri.queryParameters['shop'];
      final sname = uri.queryParameters['sname'] ?? '';
      if (bid != null && bid.isNotEmpty && shop != null && shop.isNotEmpty) {
        setState(() => _detected = true);
        _controller.stop();
        _showSheet(bid, shop, sname);
        return;
      }
    }
  }

  Future<void> _showSheet(String bid, String shopId, String shopName) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttendanceMarkSheet(bid: bid, shopId: shopId, shopName: shopName),
    );
    if (mounted) {
      setState(() => _detected = false);
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          CustomPaint(painter: _OverlayPainter(), child: const SizedBox.expand()),
          SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Scan Attendance QR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TorchState>(
                  valueListenable: _controller.torchState,
                  builder: (_, state, __) => IconButton(
                    icon: Icon(
                      state == TorchState.on
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: state == TorchState.on
                          ? const Color(0xFFFBBF24)
                          : Colors.white54,
                      size: 24,
                    ),
                    onPressed: () => _controller.toggleTorch(),
                  ),
                ),
              ],
            ),
          ),
          // Hint text below the scan frame
          Align(
            alignment: const Alignment(0, 0.72),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Owner-ஓட QR-ஐ frame-ல வையுங்க',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan frame overlay with corner brackets ───────────────────────────────────
class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const boxSize = 260.0;
    final cx = size.width / 2;
    final cy = size.height / 2.2;
    final l = cx - boxSize / 2;
    final t = cy - boxSize / 2;
    final r = cx + boxSize / 2;
    final b = cy + boxSize / 2;

    final shadow = Paint()..color = Colors.black.withOpacity(0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTRB(l, t, r, b), const Radius.circular(4)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, shadow);

    const cl = 32.0;
    final cp = Paint()
      ..color = kSecondary
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(l, t + cl), Offset(l, t), cp);
    canvas.drawLine(Offset(l, t), Offset(l + cl, t), cp);
    canvas.drawLine(Offset(r - cl, t), Offset(r, t), cp);
    canvas.drawLine(Offset(r, t), Offset(r, t + cl), cp);
    canvas.drawLine(Offset(l, b - cl), Offset(l, b), cp);
    canvas.drawLine(Offset(l, b), Offset(l + cl, b), cp);
    canvas.drawLine(Offset(r - cl, b), Offset(r, b), cp);
    canvas.drawLine(Offset(r, b), Offset(r, b - cl), cp);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Bottom sheet: staff name + type + confirm → success card ─────────────────
class _AttendanceMarkSheet extends StatefulWidget {
  final String bid, shopId, shopName;
  const _AttendanceMarkSheet({
    required this.bid,
    required this.shopId,
    required this.shopName,
  });
  @override
  State<_AttendanceMarkSheet> createState() => _AttendanceMarkSheetState();
}

class _AttendanceMarkSheetState extends State<_AttendanceMarkSheet> {
  List<String> _staffNames = [];
  String? _selected;
  String _type = 'in';
  bool _loadingStaff = true;
  bool _saving = false;
  bool _done = false;
  bool _sharing = false;
  String _markedTime = '';
  String _markedDate = '';
  final GlobalKey _repaintKey = GlobalKey();

  static const _typeLabels = {
    'in':   'IN பதிவாகிவிட்டது',
    'rest': 'REST Break',
    'back': 'Back to Work',
    'out':  'OUT பதிவாகிவிட்டது',
  };

  static const _typeColors = {
    'in':   Color(0xFF059669),
    'rest': Color(0xFFF59E0B),
    'back': Color(0xFF3B82F6),
    'out':  Color(0xFFEF4444),
  };

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('staff')
          .where('businessId', isEqualTo: widget.bid)
          .get();
      final names = snap.docs
          .map((d) => (d.data()['name'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (mounted) setState(() { _staffNames = names; _loadingStaff = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  Future<void> _confirm() async {
    if (_selected == null || _selected!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('உங்கள் பெயரை தேர்ந்தெடுங்க'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now   = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final time  = DateFormat('hh:mm a').format(now);
      await FirebaseFirestore.instance.collection('attendance').add({
        'businessId': widget.bid,
        'shopId':     widget.shopId,
        'shopName':   widget.shopName,
        'staffName':  _selected,
        'date':       today,
        'time':       time,
        'timeRaw':    now.millisecondsSinceEpoch,
        'type':       _type,
        'markedAt':   FieldValue.serverTimestamp(),
      });
      setState(() {
        _done       = true;
        _markedTime = time;
        _markedDate = DateFormat('dd MMM yyyy').format(now);
        _saving     = false;
      });
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _shareCard() async {
    setState(() => _sharing = true);
    await Future.delayed(const Duration(milliseconds: 150));
    try {
      final ctx    = _repaintKey.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final bytes    = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir      = await getTemporaryDirectory();
      final safe     = (_selected ?? 'staff').replaceAll(RegExp(r'[^\w]'), '_');
      final file     = File('${dir.path}/attendance_$safe.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Attendance Marked — $_selected',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: _done ? 0.78 : 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: _done ? _buildSuccess() : _buildForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Form state ──────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Shop header
      Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.store_rounded, color: kPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Attendance', style: TextStyle(color: kMuted, fontSize: 11)),
            Text(
              widget.shopName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: kText,
              ),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 22),
      const Text(
        'உங்கள் பெயர்',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kText),
      ),
      const SizedBox(height: 8),
      _loadingStaff
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(color: kPrimary),
              ),
            )
          : DropdownButtonFormField<String>(
              value: _selected,
              hint: const Text('Select your name'),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: kPrimary, width: 1.5),
                ),
              ),
              items: _staffNames
                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                  .toList(),
              onChanged: (v) => setState(() => _selected = v),
            ),
      const SizedBox(height: 22),
      const Text(
        'Type',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kText),
      ),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.6,
        children: [
          _typeBtn('in',   '🟢 IN'),
          _typeBtn('rest', '🟡 REST'),
          _typeBtn('back', '🔵 BACK'),
          _typeBtn('out',  '🔴 OUT'),
        ],
      ),
      const SizedBox(height: 26),
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _saving ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  '✅ Confirm',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
        ),
      ),
    ]);
  }

  Widget _typeBtn(String type, String label) {
    final sel   = _type == type;
    final color = _typeColors[type]!;
    return GestureDetector(
      onTap: () => setState(() => _type = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.10) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? color : Colors.grey.shade200,
            width: sel ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? color : kMuted,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ── Success state ───────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final typeLabel = _typeLabels[_type] ?? _type;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Green success card — captured as screenshot
      RepaintBoundary(
        key: _repaintKey,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF065f46), Color(0xFF059669)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Checkmark circle
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 14),
              Text(
                typeLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 0.3,
                ),
              ),
              const Text(
                '✅ பதிவாகிவிட்டது!',
                style: TextStyle(
                  color: Color(0xFFA7F3D0),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              // Info box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  _infoRow(Icons.person_outline_rounded, _selected ?? ''),
                  const SizedBox(height: 8),
                  _infoRow(Icons.store_rounded, widget.shopName),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.access_time_rounded,
                    '$_markedTime  ·  $_markedDate',
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              const Text(
                'arthanote.com',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      // WhatsApp share button (hidden during screenshot capture)
      if (!_sharing)
        ElevatedButton.icon(
          onPressed: _shareCard,
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text(
            'WhatsApp-ல Share பண்ணு',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )
      else
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: CircularProgressIndicator(color: kPrimary),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
        label: const Text(
          'மற்றொருவர் Scan பண்ணட்டும்',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: kPrimary,
          side: const BorderSide(color: kPrimary),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ]);
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
