import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// The hero: what the house is using right now.
class LiveCard extends StatelessWidget {
  const LiveCard({super.key, required this.reading, required this.meter, this.loading = false});
  final LiveReading? reading;
  final Meter meter;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = reading;
    final age = r == null ? null : DateTime.now().difference(r.ts);
    final offline = r == null || age! > AppConfig.offlineAfter;
    final watts = offline ? 0.0 : r.watts;
    final p = fmtPower(watts);

    // ring scale: the alert threshold if set, otherwise 5 kW
    final scale = (meter.alertPowerW ?? 5000).toDouble();
    final frac = (watts / scale).clamp(0.0, 1.0);
    final ringColor = frac >= 1 ? C.critical : (frac >= 0.8 ? C.warning : C.brand);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16302A), C.surface, C.surface],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: C.outline.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Using now', style: t.titleSmall?.copyWith(color: C.text2)),
          const Spacer(),
          if (loading)
            const StatusPill(kind: PillKind.info, label: 'Connecting…')
          else if (offline)
            StatusPill(
              kind: PillKind.offline,
              label: r == null ? 'No data yet' : 'Offline · ${fmtAgo(r.ts)}',
            )
          else
            const StatusPill(kind: PillKind.live, label: 'Live'),
        ]),
        const SizedBox(height: S.md),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: watts),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) {
                  final pv = fmtPower(v);
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: pv.value, style: t.displayLarge),
                      TextSpan(text: ' ${p.unit}', style: t.titleLarge?.copyWith(color: C.text2)),
                    ])),
                  );
                },
              ),
              const SizedBox(height: S.xs),
              Text(
                offline
                    ? 'The meter is not reporting. Power cut, or no internet at home.'
                    : _hint(watts),
                style: t.bodySmall?.copyWith(color: C.text2),
              ),
            ]),
          ),
          const SizedBox(width: S.lg),
          _Ring(fraction: frac, color: ringColor, dim: offline),
        ]),
        const SizedBox(height: S.lg),
        const Divider(),
        const SizedBox(height: S.md),
        Row(children: [
          _Mini(label: 'Voltage', value: offline ? '–' : fmtVolts(r.volts)),
          _Mini(label: 'Current', value: offline ? '–' : fmtAmps(r.amps)),
          _Mini(label: 'Power factor', value: offline ? '–' : fmtPf(r.pf)),
        ]),
      ]),
    );
  }

  static String _hint(double w) {
    if (w < 150) return 'Only standby and the fridge.';
    if (w < 600) return 'Normal, light use.';
    if (w < 1500) return 'Several appliances are on.';
    if (w < 3000) return 'Heavy use: heater, kettle or washer.';
    return 'Very high use right now.';
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelSmall?.copyWith(color: C.text3)),
        const SizedBox(height: 2),
        Text(value, style: t.titleSmall),
      ]),
    );
  }
}

/// Meter ring: fill = share of the alert threshold (teal → amber → red).
class _Ring extends StatelessWidget {
  const _Ring({required this.fraction, required this.color, required this.dim});
  final double fraction;
  final Color color;
  final bool dim;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 92,
        height: 92,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, f, _) => CustomPaint(
            painter: _RingPainter(f, dim ? C.text3 : color),
            child: Center(
              child: Icon(
                dim ? Icons.power_off_rounded : Icons.bolt_rounded,
                color: dim ? C.text3 : color,
                size: 34,
              ),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.f, this.color);
  final double f;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    const start = pi * 0.75, sweep = pi * 1.5; // 270° gauge, open at the bottom
    final track = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, start, sweep, false, track);
    if (f > 0.005) {
      final fill = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arc, start, sweep * f, false, fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.f != f || o.color != color;
}
