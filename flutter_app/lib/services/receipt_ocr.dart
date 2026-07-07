import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Structured fields pulled from a UPI payment receipt.
class ReceiptData {
  final double?   amount;
  final String?   payee;
  final String?   txnId;
  final DateTime? date;
  /// 'expense' (money paid out) or 'sale' (money received).
  final String    txnType;
  const ReceiptData(
      {this.amount, this.payee, this.txnId, this.date, this.txnType = 'expense'});

  bool get hasAmount => amount != null && amount! > 0;
  bool get isIncome  => txnType == 'sale';

  /// Field-wise merge: [primary] wins, [secondary] only fills the gaps.
  /// Direction stays with [primary] — it read the receipt's own markers.
  static ReceiptData merge(ReceiptData primary, ReceiptData secondary) =>
      ReceiptData(
        amount:  primary.amount ?? secondary.amount,
        payee:   primary.payee  ?? secondary.payee,
        txnId:   primary.txnId  ?? secondary.txnId,
        date:    primary.date   ?? secondary.date,
        txnType: primary.txnType,
      );
}

/// On-device OCR (Google ML Kit — offline, no API key) + a UPI-receipt parser.
/// Handles Google Pay, PhonePe and Paytm success/receipt screens.
class ReceiptOcr {
  /// Runs the on-device text recognizer on [imagePath] and parses the result.
  static Future<ReceiptData> extractFromImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final first = ReceiptParser.parse(await _ocr(recognizer, imagePath));
      if (first.hasAmount) return first;
      // GPay renders the amount as a huge thin-stroke headline that the
      // on-device model often fails to detect at full screenshot resolution
      // (the small detail rows still read fine, so payee/date/ref arrive
      // without an amount). On a downscaled copy that headline becomes
      // normal-sized text — retry there and merge whatever was missing.
      final small = await _downscale(imagePath);
      if (small == null) return first;
      final second = ReceiptParser.parse(await _ocr(recognizer, small));
      return ReceiptData.merge(first, second);
    } catch (_) {
      return const ReceiptData();
    } finally {
      await recognizer.close();
    }
  }

  static Future<String> _ocr(TextRecognizer recognizer, String path) async {
    final recognized =
        await recognizer.processImage(InputImage.fromFilePath(path));
    // ML Kit returns blocks in DETECTION order, not reading order — on
    // PhonePe receipts the header time can land right after "Paid to",
    // which broke payee extraction. Rebuild true reading order from each
    // line's on-screen geometry (top-to-bottom, then left-to-right).
    final lines = <TextLine>[];
    for (final block in recognized.blocks) {
      lines.addAll(block.lines);
    }
    lines.sort((a, b) {
      final at = a.boundingBox.top, bt = b.boundingBox.top;
      if ((at - bt).abs() > 14) return at.compareTo(bt);
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });
    final ordered = lines.map((l) => l.text).join('\n');
    return ordered.isEmpty ? recognized.text : ordered;
  }

  static Future<String?> _downscale(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 800, allowUpscaling: false);
      final frame = await codec.getNextFrame();
      final png =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (png == null) return null;
      final f = File('${Directory.systemTemp.path}/an_receipt_small.png');
      await f.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}

class ReceiptParser {
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Parse raw OCR text into {amount, payee, txnId, date, direction}.
  static ReceiptData parse(String raw) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final flat = lines.join(' ');
    final type = _direction(lines);

    return ReceiptData(
      amount:  _amount(lines),
      payee:   _payee(lines, income: type == 'sale'),
      txnId:   _txnId(flat),
      date:    _date(flat),
      txnType: type,
    );
  }

  // ── Direction: paid out (expense) vs received (sale) ────────────────────
  // Receipts state the counterparty headline first (lines are in reading
  // order): a PAID receipt leads with "Paid to X" / "To X"; a RECEIVED
  // receipt leads with "From X" / "Received" / "Credited". Both kinds also
  // carry To:/From: rows further down in Transfer Details, so the FIRST
  // marker wins.
  static String _direction(List<String> lines) {
    for (final l in lines) {
      final low = l.toLowerCase().trim();
      if (low.contains('paid to') || low.contains('debited')) return 'expense';
      if (low.contains('received') || low.contains('credited')) return 'sale';
      if (low == 'to' || RegExp(r'^to[:\s]').hasMatch(low)) return 'expense';
      if (low == 'from' || RegExp(r'^from[:\s]').hasMatch(low)) return 'sale';
    }
    // Sharing your own outgoing payment is the common case.
    return 'expense';
  }

  // Lines that carry amounts we must NOT treat as the payment (cashback,
  // promo banners, "payments up to ₹5,000" ads, battery %).
  static bool _noiseLine(String low) =>
      low.contains('cashback') ||
      low.contains('earned') ||
      low.contains('reward') ||
      low.contains('up to') ||
      low.contains('upto') ||
      low.contains('%');

  // ── Amount ──────────────────────────────────────────────────────────────
  // Tier 1: explicit ₹ / Rs / INR prefix.
  // Tier 2: OCR frequently misreads or drops the ₹ glyph, so also accept a
  //         line that is essentially just a number — but only when it has a
  //         comma group / decimals, or a short mangled-symbol prefix ("?20,000").
  // The payment amount is the largest surviving candidate (cashback is small).
  static double? _amount(List<String> lines) {
    final withCurrency = <double>[];
    final bare = <double>[];
    final curRe = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9][0-9,.]*)',
        caseSensitive: false);
    final bareRe = RegExp(r'^([^0-9\s]{0,2})\s*([0-9][0-9,.]{0,14})\s*$');

    void scan(String l, String low) {
      for (final m in curRe.allMatches(l)) {
        final v = _parseMoney(m.group(1)!);
        if (v != null && v > 0 && v < 10000000) withCurrency.add(v);
      }

      // Bare-number fallback. Skip lines with ':' (times "09:38",
      // labels "UTR: 4463...").
      if (low.contains(':')) return;
      final m = bareRe.firstMatch(l);
      if (m == null) return;
      final prefix = m.group(1)!;
      final numStr = m.group(2)!;
      // A plain integer with no currency hint is too risky (years, counts,
      // status-bar numbers, or — the bug this guards against — a MASKED
      // ACCOUNT/CARD NUMBER like "XX5607" or "XXXX1234"). Only a non-empty
      // prefix made of punctuation/symbol noise is trusted as a corrupted
      // currency glyph ("?200"); a letters prefix is the masking convention
      // banks/UPI apps use, never a mangled ₹, so it must NOT count as
      // evidence this line is money.
      final prefixIsLetters =
          prefix.isNotEmpty && RegExp(r'^[A-Za-z]+$').hasMatch(prefix);
      if ((prefix.isEmpty || prefixIsLetters) &&
          !RegExp(r'[.,]').hasMatch(numStr)) return;
      final v = _parseMoney(numStr);
      if (v != null && v > 0 && v < 10000000) bare.add(v);
    }

    for (final l in lines) {
      final low = l.toLowerCase();
      if (_noiseLine(low)) continue;
      scan(l, low);
      // Retry with common digit misreads fixed ("7,0OO" → "7,000"): only
      // amount-shaped patterns can match, so words stay harmless.
      final fixed = _fixDigits(l);
      if (fixed != l) scan(fixed, fixed.toLowerCase());
    }

    final pool = withCurrency.isNotEmpty ? withCurrency : bare;
    if (pool.isEmpty) return null;
    return pool.reduce(math.max);
  }

  /// OCR confuses O/0 and l/I/1 inside the big thin-font amount.
  static String _fixDigits(String s) => s
      .replaceAll('O', '0')
      .replaceAll('o', '0')
      .replaceAll('l', '1')
      .replaceAll('|', '1');

  /// Parses an OCR'd money token, tolerating both separator styles:
  /// "20,000" / "7.000" (dot misread of the lakh comma) → thousands groups;
  /// "1,234.56" / "7.50" → decimals. Trailing punctuation is stripped.
  static double? _parseMoney(String s) {
    s = s.replaceAll(RegExp(r'[.,]+$'), '');
    if (s.isEmpty) return null;
    // Every separator followed by a 3-digit (or Indian 2-digit) group and
    // no 1–2-digit tail → they are thousands separators, drop them all.
    if (RegExp(r'^[0-9]{1,3}(?:[.,][0-9]{2,3})+$').hasMatch(s) &&
        !RegExp(r'\.[0-9]{1,2}$').hasMatch(s)) {
      return double.tryParse(s.replaceAll(RegExp(r'[.,]'), ''));
    }
    final m = RegExp(r'^([0-9,]+)(?:\.([0-9]{1,2}))?$').firstMatch(s);
    if (m == null) return null;
    final whole = m.group(1)!.replaceAll(',', '');
    return double.tryParse(
        m.group(2) == null ? whole : '$whole.${m.group(2)}');
  }

  // ── Payee (counterparty) ─────────────────────────────────────────────────
  // For a PAID receipt the counterparty follows "Paid to"/"To"; for a
  // RECEIVED one it follows "From" ("From ASHRAF ALI", "From: ASHRAF ALI").
  static String? _payee(List<String> lines, {bool income = false}) {
    final standalone = income ? ['from'] : ['paid to', 'to'];
    final inlineRe = income
        ? RegExp(r'^from\s*:?\s+(.{2,60})$', caseSensitive: false)
        : RegExp(r'^(?:paid to|to)\s*:?\s+(.{2,60})$', caseSensitive: false);

    for (var i = 0; i < lines.length; i++) {
      final l   = lines[i];
      final low = l.toLowerCase();

      // Keyword-only header — the name may not be the very next OCR line
      // (avatars, phone numbers, stray rows). Scan a few lines ahead for the
      // first thing that survives the name cleaner.
      if (standalone.contains(low)) {
        for (var j = i + 1; j < lines.length && j <= i + 4; j++) {
          final c = _cleanName(lines[j]);
          if (c != null) return c;
        }
      }
      // Inline: "to S P Broilers" / "To: Rohith Kumar M" / "From ASHRAF ALI"
      final m = inlineRe.firstMatch(l);
      if (m != null) {
        final c = _cleanName(m.group(1)!);
        if (c != null) return c;
      }
    }

    // PhonePe fallback: "Banking Name : Rajasekaran G" (paid receipts show
    // the counterparty's banking name; skip for received to avoid picking
    // our own account name).
    if (!income) {
      for (final l in lines) {
        final m = RegExp(r'banking name\s*:?\s*(.+)$', caseSensitive: false)
            .firstMatch(l);
        if (m != null) {
          final c = _cleanName(m.group(1)!);
          if (c != null) return c;
        }
      }
    }

    // Last resort: the line just above a phone number is usually the name.
    final phoneRe = RegExp(r'^\+?[0-9][0-9 ]{8,14}$');
    for (var i = 1; i < lines.length; i++) {
      if (phoneRe.hasMatch(lines[i])) {
        final c = _cleanName(lines[i - 1]);
        if (c != null) return c;
      }
    }
    return null;
  }

  /// Normalizes a payee candidate; returns null for anything that is clearly
  /// not a name (dates, times, phone numbers, VPAs, receipt UI chrome).
  static String? _cleanName(String s) {
    var name = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip an inline amount when name+amount share one OCR row
    // ("Mr Rajasekaran ₹20,000").
    name = name
        .replaceAll(
            RegExp(r'(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?',
                caseSensitive: false),
            '')
        .trim();
    if (name.length < 2) return null;
    if (name.contains('@')) return null; // VPA / email

    // Latin OCR of a Tamil/regional-script header produces gibberish like
    // "6IräiJTg" (for லிங்கராஜ்). Real UPI counterparty names are plain
    // ASCII — reject accented output and words with digits fused to letters,
    // so the scan falls through to the clean "To: LINGA RAJ A" detail row.
    if (name.codeUnits.any((c) => c > 127)) return null;
    if (RegExp(r'[0-9][A-Za-z]|[A-Za-z][0-9]').hasMatch(name)) return null;

    // Dates & times are never names ("09:38 am on 03 Jul 2026", "3/7/2026").
    if (RegExp(r'\d{1,2}:\d{2}').hasMatch(name)) return null;
    final low = name.toLowerCase();
    if (RegExp(r'\d{1,2}\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)')
        .hasMatch(low)) return null;
    if (RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}').hasMatch(name)) return null;

    // Phone numbers / ID-like strings (mostly digits).
    final digitCount = name.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digitCount * 2 > name.length) return null;

    // Receipt UI chrome that sits near the name.
    const junk = [
      'transaction', 'successful', 'transfer detail', 'debited',
      'banking name', 'completed', 'view history', 'split expense',
      'share receipt', 'send again', 'powered by', 'contact', 'support',
      'pay again', 'view details', 'add a note', 'in your',
    ];
    for (final j in junk) {
      if (low.contains(j)) return null;
    }

    if (name.length > 40) name = name.substring(0, 40).trim();
    return name.isEmpty ? null : name;
  }

  // ── Transaction ID ──────────────────────────────────────────────────────
  static String? _txnId(String flat) {
    final t = RegExp(r'transaction id\s*:?\s*([A-Za-z0-9]{6,})',
            caseSensitive: false)
        .firstMatch(flat);
    if (t != null) return t.group(1);
    final utr =
        RegExp(r'\bUTR\s*:?\s*([A-Za-z0-9]{6,})', caseSensitive: false)
            .firstMatch(flat);
    return utr?.group(1);
  }

  // ── Date ────────────────────────────────────────────────────────────────
  // "30 June 2026", "02 Jul 2026", "1 Jul 2026"
  static DateTime? _date(String flat) {
    final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})').firstMatch(flat);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final mon = _months[m.group(2)!.toLowerCase().substring(0, 3)];
    final yr  = int.tryParse(m.group(3)!);
    if (day == null || mon == null || yr == null) return null;
    try {
      return DateTime(yr, mon, day);
    } catch (_) {
      return null;
    }
  }
}
