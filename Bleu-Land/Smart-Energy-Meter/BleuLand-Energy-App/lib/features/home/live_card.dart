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
    if (offline) return _OfflineCard(lastSeen: r?.ts);
    final known = !widget.loading;
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
                Text(
                  'Using now',
                  style: t.titleSmall?.copyWith(color: C.text2),
                ),
                const SizedBox(height: S.xl),
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
                            Text(
                              'Connecting…',
                              style: t.displaySmall?.copyWith(color: C.text2),
                            ),
                            const SizedBox(height: S.sm),
                            Text(
                              'Getting the latest reading.',
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

/// The meter isn't reporting: "last seen" and the Offline pill on one line,
/// one short headline with one short reason under it, and a softly breathing
/// icon with ripples that shows the app is still listening for the meter.
class _OfflineCard extends StatefulWidget {
  const _OfflineCard({this.lastSeen});
  final DateTime? lastSeen;

  @override
  State<_OfflineCard> createState() => _OfflineCardState();
}

class _OfflineCardState extends State<_OfflineCard>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const accent = C.criticalText;
    final seen = widget.lastSeen;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF33201F), C.surface, C.surface],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: C.outline.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.lg, S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  seen == null ? 'Not seen yet' : 'Last seen ${fmtAgo(seen)}',
                  style: t.titleSmall?.copyWith(color: C.text2),
                ),
              ),
              const StatusPill(kind: PillKind.offline, label: 'Offline'),
            ],
          ),
          const SizedBox(height: S.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Meter is offline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.headlineSmall,
                    ),
                    const SizedBox(height: S.xs),
                    Text(
                      'Power or internet may be down.',
                      style: t.bodyMedium?.copyWith(color: C.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.md),
              SizedBox(
                width: 80,
                height: 80,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) {
                    // one full sine wave per loop, so the end meets the start
                    final breath = (1 - cos(2 * pi * _pulse.value)) / 2;
                    return CustomPaint(
                      painter: _PulsePainter(_pulse.value, accent),
                      child: Center(
                        child: Transform.scale(
                          scale: 1 + 0.06 * breath,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(
                                alpha: 0.12 + 0.08 * breath,
                              ),
                            ),
                            child: const Icon(
                              Icons.power_off_rounded,
                              color: accent,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two ripples growing out from the icon, half a loop apart. Each fades in
/// and out, so none pops into view when the loop restarts.
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r0 = 23.0; // the icon's circle
    final rMax = size.shortestSide / 2 - 1;
    for (final phase in [0.0, 0.5]) {
      final p = (t + phase) % 1.0;
      final fade = sin(pi * p); // 0 -> 1 -> 0
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.5 * fade);
      canvas.drawCircle(
        c,
        r0 + (rMax - r0) * Curves.easeOut.transform(p),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t;
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
