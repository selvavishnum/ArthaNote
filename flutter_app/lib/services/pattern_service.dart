import '../models/txn.dart';

/// Learns from past transactions to predict type and category for new entries.
/// Fully offline — no API, no network.
class PatternService {
  // normalized_desc → { type → count }
  final Map<String, Map<String, int>> _types = {};
  // normalized_desc → { category → count }
  final Map<String, Map<String, int>> _cats  = {};

  // ── Public API ────────────────────────────────────────────────────────────

  void learnFromTxns(List<Txn> txns) {
    for (final t in txns) {
      if (t.desc.isNotEmpty) _record(t.desc, t.type, t.desc);
    }
  }

  void learn(String desc, String type, String category) {
    if (desc.isEmpty) return;
    _record(desc, type, category);
  }

  AiPrediction predict(String input) {
    final text = input.trim();
    if (text.length < 2) return AiPrediction.empty();

    final key    = _norm(text);
    Map<String, int>? tMap = _types[key];
    Map<String, int>? cMap = _cats[key];

    // Prefix / contains fallback
    if (tMap == null) {
      int bestScore = 0;
      for (final k in _types.keys) {
        if (k.startsWith(key) || key.startsWith(k)) {
          final score = _types[k]!.values.fold(0, (a, b) => a + b);
          if (score > bestScore) {
            bestScore = score;
            tMap = _types[k];
            cMap = _cats[k];
          }
        }
      }
    }

    if (tMap == null || tMap.isEmpty) return AiPrediction.empty();

    final total   = tMap.values.fold(0, (a, b) => a + b);
    final topType = tMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final conf    = tMap[topType]! / total;
    final topCat  = (cMap != null && cMap.isNotEmpty)
        ? cMap.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : '';

    return AiPrediction(
      type:       topType,
      category:   topCat,
      confidence: conf,
      count:      total,
    );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _record(String desc, String type, String category) {
    final key = _norm(desc);
    if (key.isEmpty) return;
    _types[key] ??= {};
    _types[key]![type] = (_types[key]![type] ?? 0) + 1;
    if (category.isNotEmpty) {
      final ck = _norm(category);
      _cats[key] ??= {};
      _cats[key]![ck] = (_cats[key]![ck] ?? 0) + 1;
    }
  }

  String _norm(String s) => s.trim().toLowerCase();
}

class AiPrediction {
  final String type;
  final String category;
  final double confidence; // 0.0–1.0
  final int    count;      // total past entries matched

  const AiPrediction({
    required this.type,
    required this.category,
    required this.confidence,
    required this.count,
  });

  factory AiPrediction.empty() =>
      const AiPrediction(type: '', category: '', confidence: 0, count: 0);

  bool get isEmpty  => type.isEmpty;
  /// Good enough to show a suggestion (at least 1 past entry, ≥50% agreement)
  bool get isGood   => !isEmpty && confidence >= 0.5 && count >= 1;
  /// Strong enough to auto-apply type without user interaction
  bool get isStrong => !isEmpty && confidence >= 0.7 && count >= 2;
}
