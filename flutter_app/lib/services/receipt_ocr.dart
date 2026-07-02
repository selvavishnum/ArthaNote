import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Structured fields pulled from a UPI payment receipt.
class ReceiptData {
  final double?   amount;
  final String?   payee;
  final String?   txnId;
  final DateTime? date;
  const ReceiptData({this.amount, this.payee, this.txnId, this.date});

  bool get hasAmount => amount != null && amount! > 0;
}

/// On-device OCR (Google ML Kit — offline, no API key) + a UPI-receipt parser.
/// Handles Google Pay, PhonePe and Paytm success/receipt screens.
class ReceiptOcr {
  /// Runs the on-device text recognizer on [imagePath] and parses the result.
  static Future<ReceiptData> extractFromImage(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return ReceiptParser.parse(recognized.text);
    } catch (_) {
      return const ReceiptData();
    } finally {
      await recognizer.close();
    }
  }
}

class ReceiptParser {
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Parse raw OCR text into {amount, payee, txnId, date}.
  static ReceiptData parse(String raw) {
    final text  = raw.replaceAll('₹', '₹');
    final flat  = text.replaceAll('\n', ' ');
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ReceiptData(
      amount: _amount(lines),
      payee:  _payee(lines),
      txnId:  _txnId(flat),
      date:   _date(flat),
    );
  }

  // ── Amount ──────────────────────────────────────────────────────────────
  // Collect every ₹ value, skip cashback/reward/ad lines, take the largest —
  // the main payment amount is the prominent one; cashback (₹1.44) is smaller.
  static double? _amount(List<String> lines) {
    final amtRe = RegExp(r'₹\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)');
    final vals = <double>[];
    for (final l in lines) {
      final low = l.toLowerCase();
      if (low.contains('cashback') ||
          low.contains('earned') ||
          low.contains('reward') ||
          low.contains('up to') ||
          low.contains('upto')) continue;
      for (final m in amtRe.allMatches(l)) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v > 0) vals.add(v);
      }
    }
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a > b ? a : b);
  }

  // ── Payee ───────────────────────────────────────────────────────────────
  static String? _payee(List<String> lines) {
    String? clean(String s) {
      var name = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      // reject emails / VPAs / phone numbers
      if (name.contains('@')) return null;
      if (RegExp(r'^\+?\d[\d ]{5,}$').hasMatch(name)) return null;
      if (name.length < 2) return null;
      if (name.length > 40) name = name.substring(0, 40).trim();
      return name;
    }

    for (int i = 0; i < lines.length; i++) {
      final l   = lines[i];
      final low = l.toLowerCase();

      // PhonePe: a lone "Paid to" line, name on the next line.
      if ((low == 'paid to' || low == 'to') && i + 1 < lines.length) {
        final c = clean(lines[i + 1]);
        if (c != null) return c;
      }
      // GPay: "to S P Broilers" / "To Advocate Rohith" / "To: Rohith Kumar M"
      final m = RegExp(r'^(?:paid to|to)\s*:?\s+(.{2,50})$', caseSensitive: false)
          .firstMatch(l);
      if (m != null) {
        final c = clean(m.group(1)!);
        if (c != null) return c;
      }
    }
    return null;
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
