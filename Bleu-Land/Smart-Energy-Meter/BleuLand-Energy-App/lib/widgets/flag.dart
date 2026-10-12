import 'dart:math';

import 'package:flutter/material.dart';

/// A country's flag waving gently in a loop (the bill card, the country
/// picker). Pauses on its own when the screen isn't shown.
class WavingFlag extends StatefulWidget {
  const WavingFlag({super.key, required this.regionId, this.width = 30, this.height = 20, this.wave = true});
  final String regionId;
  final double width, height;
  final bool wave; // false: still (lists)

  @override
  State<WavingFlag> createState() => _WavingFlagState();
}

class _WavingFlagState extends State<WavingFlag> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.wave) _anim.repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.width / 14),
          child: CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _FlagPainter(widget.regionId, _anim, widget.wave),
          ),
        ),
      );
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.id, this.t, this.wave) : super(repaint: t);
  final String id;
  final Animation<double> t;
  final bool wave;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t.value * 2 * pi;
    final amp = wave ? size.height * 0.07 : 0.0; // room is kept above and below
    final flag = Size(size.width, size.height - amp * 2);
    // thin slices (about 1 px) so the wave is smooth, not stepped
    final strips = max(18, (size.width / 1.1).round());
    final w = size.width / strips;
    for (var i = 0; i < strips; i++) {
      final x = i * w;
      // the wave grows away from the pole (left edge moves least)
      final k = x / size.width;
      final a = k * 2 * pi * 0.9 - phase;
      final dy = sin(a) * amp * (0.35 + k);
      final shade = wave ? cos(a) * 0.10 * (0.35 + k) : 0.0;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(x - 0.3, 0, w + 0.6, size.height));
      canvas.translate(0, amp + dy);
      _drawFlag(canvas, flag);
      // light and shadow across the folds
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w, flag.height), // edge to edge: no darker seams
        Paint()..color = (shade > 0 ? Colors.white : Colors.black).withValues(alpha: shade.abs()),
      );
      canvas.restore();
    }
  }

  void _drawFlag(Canvas canvas, Size s) {
    switch (id) {
      case 'sy':
      default:
        // Syria: green, white and black bands, three red stars on the white
        final band = s.height / 3;
        canvas.drawRect(Rect.fromLTWH(0, 0, s.width, band), Paint()..color = const Color(0xFF007A3D));
        canvas.drawRect(Rect.fromLTWH(0, band, s.width, band), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(0, band * 2, s.width, band), Paint()..color = const Color(0xFF000000));
        final star = Paint()..color = const Color(0xFFCE1126);
        final r = band * 0.42;
        for (final fx in const [0.3, 0.5, 0.7]) {
          canvas.drawPath(_star(Offset(s.width * fx, band * 1.5), r), star);
        }
    }
  }

  static Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final rr = i.isEven ? r : r * 0.4;
      final pt = Offset(c.dx + rr * cos(a), c.dy + rr * sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.id != id || old.wave != wave;
}
