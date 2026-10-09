import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/levels.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// The hero: what the house is using right now.
class LiveCard extends StatefulWidget {
  const LiveCard({
    super.key,
    required this.reading,
    required this.meter,
    this.loading = false,
    this.todayKwh,
  });
  final LiveReading? reading;
  final Meter meter;
  final bool loading;
  final double? todayKwh; // for "compared with your average today"

  @override
  State<LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<LiveCard> {
  // Re-check the reading's age even when no new value arrives, so a meter
  // that stops reporting turns "offline" on its own.
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 5),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = widget.reading;
    final now = DateTime.now();
    final offline =
        !widget.loading &&
        (r == null || now.difference(r.ts) > AppConfig.offlineAfter);
    final known = !widget.loading && !offline;
    final watts = known ? r!.watts : 0.0;

    // ring scale: the alert threshold if set, otherwise 5 kW
    final scale = (widget.meter.alertPowerW ?? 5000).toDouble();
    final frac = (watts / scale).clamp(0.0, 1.0);
    final ringColor = frac >= 1
        ? C.critical
        : (frac >= 0.8 ? C.warning : C.brand);

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
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Offline: the "last seen" pill takes the title's place.
                if (offline)
                  StatusPill(
                    kind: PillKind.offline,
                    label: r == null
                        ? 'No data yet'
                        : 'Last seen ${fmtAgo(r.ts)}',
                  )
                else
                  Text(
                    'Using now',
                    style: t.titleSmall?.copyWith(color: C.text2),
                  ),
                SizedBox(height: offline ? S.lg : S.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (known) ...[
                            _CountingPower(watts: watts),
                            const SizedBox(height: S.sm),
                            _UsageNote(watts: watts, todayKwh: widget.todayKwh),
                          ] else ...[
                            // Offline: no number at all, the usage is simply unknown.
                            Text(
                              widget.loading ? 'Connecting…' : 'Offline',
                              style: t.displaySmall?.copyWith(color: C.text2),
                            ),
                            const SizedBox(height: S.sm),
                            Text(
                              widget.loading ? 'Getting the latest reading.' : 'The meter may have lost power or internet. It keeps recording and catches up when it\'s back.',
                              style: t.bodySmall?.copyWith(color: C.text2),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: S.lg),
                    _Ring(fraction: frac, color: ringColor, dim: !known),
                  ],
                ),
                if (known) ...[
                  const SizedBox(height: S.lg),
                  const Divider(),
                  const SizedBox(height: S.md),
                  Row(
                    children: [
                      _Mini(
                        label: 'Voltage',
                        value: r!.volts,
                        format: fmtVolts,
                      ),
                      _Mini(label: 'Current', value: r.amps, format: fmtAmps),
                      _Mini(label: 'Power factor', value: r.pf, format: fmtPf),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // status sits in the card's corner, clear of the ring
          if (!offline)
            Positioned(
              top: S.md,
              right: S.md,
              child: widget.loading
                  ? const StatusPill(kind: PillKind.info, label: 'Connecting…')
                  : const StatusPill(kind: PillKind.live, label: 'Live'),
            ),
        ],
      ),
    );
  }
}

/// The big number. Glides between readings (they arrive every 2 s while the
/// app is open) so it counts like a live meter instead of jumping.
class _CountingPower extends StatelessWidget {
  const _CountingPower({required this.watts});
  final double watts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: watts),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeInOutCubic,
      builder: (_, v, _) {
        final p = fmtPower(v);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: p.value,
                  style: t.displayLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: ' ${p.unit}',
                  style: t.titleLarge?.copyWith(color: C.text2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Light use · under 1 kW" and how it compares with today so far.
class _UsageNote extends StatelessWidget {
  const _UsageNote({required this.watts, this.todayKwh});
  final double watts;
  final double? todayKwh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final level = usageLevel(watts);
    final (Color c, IconData icon) = switch (level) {
      UsageLevel.light => (C.brand, Icons.eco_rounded),
      UsageLevel.moderate => (C.brand, Icons.bolt_rounded),
      UsageLevel.high => (C.warning, Icons.trending_up_rounded),
      UsageLevel.veryHigh => (C.serious, Icons.warning_amber_rounded),
    };
    final vs = todayKwh == null
        ? null
        : versusToday(watts, todayKwh: todayKwh!, now: DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Row(
            key: ValueKey(level),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: c),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: level.label,
                        style: t.labelLarge?.copyWith(color: C.text),
                      ),
                      TextSpan(
                        text: ' · ${level.range}',
                        style: t.labelLarge?.copyWith(
                          color: C.text2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (vs != null) ...[
          const SizedBox(height: 2),
          Text(vs, style: t.bodySmall?.copyWith(color: C.text2)),
        ],
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, required this.format});
  final String label;
  final double value;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: C.text3)),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: const Duration(milliseconds: 1600),
            curve: Curves.easeInOutCubic,
            builder: (_, x, _) => Text(
              format(x),
              style: t.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
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
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeInOutCubic,
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
