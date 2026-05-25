import 'package:flutter/material.dart';

// Model 3 — Bold Rounded nav icons
// StrokeWidth: 2.8, StrokeCap.round, StrokeJoin.round

const _kGreen  = Color(0xFF065F46);
const _kAccent = Color(0xFF4ADE80);
const _kGrey   = Color(0xFF9CA3AF);
const _kFaint  = Color(0xFFD1D5DB);
const _kTint   = Color(0xFFDCFCE7);

enum NavIconType { dashboard, scan, entry, ledger, suppliers, reports, finance }

class NavIcon extends StatelessWidget {
  final NavIconType type;
  final bool active;
  const NavIcon({super.key, required this.type, required this.active});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 26,
        height: 26,
        child: CustomPaint(painter: _NavPainter(type: type, active: active)),
      );
}

class _NavPainter extends CustomPainter {
  final NavIconType type;
  final bool active;
  const _NavPainter({required this.type, required this.active});

  Paint get _sp => Paint()
    ..color = active ? _kGreen : _kGrey
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.8
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _fp(Color c) => Paint()..color = c..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size s) {
    switch (type) {
      case NavIconType.dashboard:  _dash(canvas, s);
      case NavIconType.scan:       _scan(canvas, s);
      case NavIconType.entry:      _entry(canvas, s);
      case NavIconType.ledger:     _ledger(canvas, s);
      case NavIconType.suppliers:  _suppliers(canvas, s);
      case NavIconType.reports:    _reports(canvas, s);
      case NavIconType.finance:    _finance(canvas, s);
    }
  }

  // ── Dashboard: 2×2 rounded grid ──────────────────────────────────────────
  void _dash(Canvas canvas, Size s) {
    const pad = 2.0, gap = 2.5, r = 3.5;
    final hw = (s.width - pad * 2 - gap) / 2;
    final hh = (s.height - pad * 2 - gap) / 2;
    final rects = [
      Rect.fromLTWH(pad, pad, hw, hh),
      Rect.fromLTWH(pad + hw + gap, pad, hw, hh),
      Rect.fromLTWH(pad, pad + hh + gap, hw, hh),
      Rect.fromLTWH(pad + hw + gap, pad + hh + gap, hw, hh),
    ];
    for (final rect in rects) {
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(r));
      if (active) {
        canvas.drawRRect(rr, _fp(_kGreen));
      } else {
        canvas.drawRRect(rr, _sp);
      }
    }
  }

  // ── Scan: corner brackets + horizontal scan line ──────────────────────────
  void _scan(Canvas canvas, Size s) {
    const m = 2.0;
    final bL = s.width * 0.34;
    final lines = [
      // TL
      [Offset(m, m + bL), Offset(m, m)], [Offset(m, m), Offset(m + bL, m)],
      // TR
      [Offset(s.width - m - bL, m), Offset(s.width - m, m)],
      [Offset(s.width - m, m), Offset(s.width - m, m + bL)],
      // BL
      [Offset(m, s.height - m - bL), Offset(m, s.height - m)],
      [Offset(m, s.height - m), Offset(m + bL, s.height - m)],
      // BR
      [Offset(s.width - m - bL, s.height - m), Offset(s.width - m, s.height - m)],
      [Offset(s.width - m, s.height - m), Offset(s.width - m, s.height - m - bL)],
    ];
    for (final ln in lines) {
      canvas.drawLine(ln[0], ln[1], _sp);
    }
    // Scan line
    final sy = s.height * 0.5;
    canvas.drawLine(
      Offset(m + 3, sy),
      Offset(s.width - m - 3, sy),
      Paint()
        ..color = active ? _kAccent : _kFaint
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  // ── Entry: document with + badge ──────────────────────────────────────────
  void _entry(Canvas canvas, Size s) {
    const dX = 2.0, dY = 2.5;
    final dW = s.width * 0.74;
    final dH = s.height * 0.83;
    final doc = RRect.fromRectAndRadius(
        Rect.fromLTWH(dX, dY, dW, dH), const Radius.circular(4));
    if (active) canvas.drawRRect(doc, _fp(_kTint));
    canvas.drawRRect(doc, _sp);

    // Horizontal lines
    final lp = Paint()
      ..color = active ? _kGreen : _kFaint
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final x1 = dX + dW * 0.2, x2 = dX + dW * 0.82;
    canvas.drawLine(Offset(x1, dY + dH * 0.30), Offset(x2 * 0.88, dY + dH * 0.30), lp);
    canvas.drawLine(Offset(x1, dY + dH * 0.50), Offset(x2, dY + dH * 0.50), lp);
    canvas.drawLine(Offset(x1, dY + dH * 0.68), Offset(x2 * 0.78, dY + dH * 0.68), lp);

    // + badge
    final bx = dX + dW - 1, by = dY;
    canvas.drawCircle(Offset(bx, by), 5.5,
        _fp(active ? _kGreen : _kGrey));
    final wp = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(bx - 2.6, by), Offset(bx + 2.6, by), wp);
    canvas.drawLine(Offset(bx, by - 2.6), Offset(bx, by + 2.6), wp);
  }

  // ── Ledger: open book ─────────────────────────────────────────────────────
  void _ledger(Canvas canvas, Size s) {
    const top = 2.5, bot = 24.0, le = 1.5, re = 24.5, cr = 3.0;
    final mx = s.width / 2;

    Path _page(bool left) {
      final x = left ? le : mx;
      final xEnd = left ? mx : re;
      return Path()
        ..moveTo(mx, top)
        ..lineTo(x + (left ? cr : -cr), top)
        ..quadraticBezierTo(x, top, x, top + cr)
        ..lineTo(x, bot - cr)
        ..quadraticBezierTo(x, bot, x + (left ? cr : -cr), bot)
        ..lineTo(mx, bot);
    }

    final lp = _page(true), rp = _page(false);
    if (active) {
      canvas.drawPath(lp, _fp(_kTint));
      canvas.drawPath(rp, _fp(_kTint));
    }
    canvas.drawPath(lp, _sp);
    canvas.drawPath(rp, _sp);
    canvas.drawLine(const Offset(mx, top + 1), Offset(mx, bot - 1), _sp);

    // Page lines
    final lnP = Paint()
      ..color = active ? _kGreen : _kFaint
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final hw = (mx - le) * 0.32;
    final lc = (le + mx) / 2, rc = (mx + re) / 2;
    for (final y in [top + (bot - top) * 0.32, top + (bot - top) * 0.52, top + (bot - top) * 0.70]) {
      canvas.drawLine(Offset(lc - hw, y), Offset(lc + hw, y), lnP);
      canvas.drawLine(Offset(rc - hw, y), Offset(rc + hw, y), lnP);
    }
  }

  // ── Suppliers: two overlapping people ────────────────────────────────────
  void _suppliers(Canvas canvas, Size s) {
    // Back person
    final backPaint = Paint()
      ..color = active ? _kAccent : _kFaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final bx = s.width * 0.62, by = s.height * 0.27;
    canvas.drawCircle(Offset(bx, by), s.width * 0.13, backPaint);
    final backBody = Path()
      ..moveTo(bx - s.width * 0.20, s.height - 1.5)
      ..quadraticBezierTo(bx, s.height * 0.52, bx + s.width * 0.22, s.height - 1.5);
    canvas.drawPath(backBody, backPaint);

    // Front person
    final fx = s.width * 0.40, fy = s.height * 0.25;
    canvas.drawCircle(Offset(fx, fy), s.width * 0.16, _sp);
    final frontBody = Path()
      ..moveTo(fx - s.width * 0.27, s.height - 1.0)
      ..quadraticBezierTo(fx, s.height * 0.50, fx + s.width * 0.27, s.height - 1.0);
    canvas.drawPath(frontBody, _sp);
  }

  // ── Reports: 3 bars + trend line + dots ──────────────────────────────────
  void _reports(Canvas canvas, Size s) {
    final baseY = s.height - 2.5;
    const barW = 5.0;
    const gap = 3.2;
    final offX = (s.width - barW * 3 - gap * 2) / 2;
    final heights = [s.height * 0.44, s.height * 0.64, s.height * 0.54];

    for (int i = 0; i < 3; i++) {
      final x = offX + i * (barW + gap);
      final bh = heights[i];
      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseY - bh, barW, bh),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(
        rr,
        active
            ? _fp(_kGreen)
            : (Paint()
              ..color = _kGrey
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round),
      );
    }

    // Trend line
    final centers = List.generate(3, (i) => offX + i * (barW + gap) + barW / 2);
    final trendPaint = Paint()
      ..color = active ? _kAccent : _kFaint
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 2; i++) {
      canvas.drawLine(
        Offset(centers[i], baseY - heights[i] - 3),
        Offset(centers[i + 1], baseY - heights[i + 1] - 3),
        trendPaint,
      );
    }
    for (int i = 0; i < 3; i += 2) {
      canvas.drawCircle(
        Offset(centers[i], baseY - heights[i] - 3),
        2.2,
        _fp(active ? _kAccent : _kFaint),
      );
    }
  }

  // ── Finance: wallet ───────────────────────────────────────────────────────
  void _finance(Canvas canvas, Size s) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(1.5, s.height * 0.24, s.width - 3, s.height * 0.65),
      const Radius.circular(4.5),
    );
    if (active) canvas.drawRRect(body, _fp(_kTint));
    canvas.drawRRect(body, _sp);
    // Card slot line
    canvas.drawLine(
      Offset(1.5, s.height * 0.43),
      Offset(s.width - 1.5, s.height * 0.43),
      _sp,
    );
    // Coin
    canvas.drawCircle(
      Offset(s.width * 0.72, s.height * 0.64),
      s.width * 0.13,
      _sp,
    );
  }

  @override
  bool shouldRepaint(_NavPainter o) => o.active != active || o.type != type;
}
