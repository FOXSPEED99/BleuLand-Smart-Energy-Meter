import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/levels.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

/// Mains voltage: live value on a scale with the home's normal range, a
/// plain-words status. The range itself is changed in Settings.
class VoltageCard extends StatefulWidget {
  const VoltageCard({super.key, required this.reading, required this.meter});
  final LiveReading? reading;
  final Meter meter;

  @override
  State<VoltageCard> createState() => _VoltageCardState();
}

class _VoltageCardState extends State<VoltageCard> {
  // hides itself on its own when the meter stops reporting (see LiveCard)
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = widget.meter;
    final r = widget.reading;
    final now = DateTime.now();
    // Nothing to show while the meter is offline, or when it reports no mains
    // (below 100 V, e.g. powered from USB): hide the whole card.
    final reporting =
        r != null && now.difference(r.ts) <= AppConfig.offlineAfter;
    if (!reporting || r.volts < 100) return const SizedBox.shrink();
    final v = r.volts;
    final status = voltStatus(v, min: m.voltMin, max: m.voltMax);

    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        // a soft wash in the top-right corner (the live card's is top-left)
        // that follows the status: green when normal, amber a bit off, red
        // when serious
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.lg),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [_wash(status), C.surface, C.surface],
            stops: const [0, 0.55, 1],
          ),
        ),
        padding: const EdgeInsets.all(S.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, size: 18, color: C.text2),
                const SizedBox(width: S.sm),
                Expanded(child: Text('Voltage', style: t.titleSmall)),
                Text(
                  'Normal ${m.voltMin.round()}–${m.voltMax.round()} V',
                  style: t.labelMedium?.copyWith(color: C.text2),
                ),
              ],
            ),
            const SizedBox(height: S.lg),
            Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(end: v),
                  duration: const Duration(milliseconds: 1600),
                  curve: Curves.easeInOutCubic,
                  builder: (_, x, _) => Text(
                    NumberFormat('0.0').format(x),
                    style: t.headlineMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 6),
                  child: Text(
                    'V',
                    style: t.titleMedium?.copyWith(color: C.text2),
                  ),
                ),
                const Spacer(),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: S.lg),
            _VoltScale(min: m.voltMin, max: m.voltMax, value: v),
            if (status.advice != null) ...[
              const SizedBox(height: S.md),
              Container(
                padding: const EdgeInsets.all(S.md),
                decoration: BoxDecoration(
                  color: _color(status).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icon(status), size: 18, color: _color(status)),
                    const SizedBox(width: S.sm),
                    // always one line; shrinks a little on very narrow phones
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          status.advice!,
                          maxLines: 1,
                          style: t.bodySmall?.copyWith(color: C.text),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _wash(VoltStatus s) => switch (s) {
  VoltStatus.normal => const Color(0xFF16302A),
  VoltStatus.lowMild || VoltStatus.highMild => const Color(0xFF332A14),
  VoltStatus.lowSerious || VoltStatus.highSerious => const Color(0xFF3A1E1F),
};

Color _color(VoltStatus s) => switch (s) {
  VoltStatus.normal => C.goodText,
  VoltStatus.lowMild || VoltStatus.highMild => C.warning,
  VoltStatus.lowSerious || VoltStatus.highSerious => C.criticalText,
};

IconData _icon(VoltStatus s) => switch (s) {
  VoltStatus.normal => Icons.check_circle_rounded,
  VoltStatus.lowMild || VoltStatus.lowSerious => Icons.south_rounded,
  VoltStatus.highMild || VoltStatus.highSerious => Icons.north_rounded,
};

/// Icon + word, never colour alone.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final VoltStatus status;

  @override
  Widget build(BuildContext context) {
    final c = _color(status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.serious ? Icons.warning_amber_rounded : _icon(status),
            size: 14,
            color: c,
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: C.text),
          ),
        ],
      ),
    );
  }
}

/// A horizontal scale: serious | a little low | normal | a little high | serious.
/// The zone the live value is in is drawn bright, the others dimmed, with the
/// value as a dot that glides along it.
class _VoltScale extends StatelessWidget {
  const _VoltScale({required this.min, required this.max, this.value});
  final double min, max;
  final double? value;

  static const _bar = 12.0, _dot = 26.0; // _dot: height of the needle area

  @override
  Widget build(BuildContext context) {
    final lo = min - voltSeriousMargin * 2.5,
        hi = max + voltSeriousMargin * 2.5;
    final t = Theme.of(context).textTheme;
    final v = value;
    final zone = v == null
        ? null
        : switch (voltStatus(v, min: min, max: max)) {
            VoltStatus.lowSerious => 0,
            VoltStatus.lowMild => 1,
            VoltStatus.normal => 2,
            VoltStatus.highMild => 3,
            VoltStatus.highSerious => 4,
          };
    return LayoutBuilder(
      builder: (context, box) {
        double x(double v) =>
            ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * box.maxWidth;
        Widget label(double v) => Positioned(
          left: x(v) - 20,
          width: 40,
          top: _dot + S.sm,
          child: Text(
            '${v.round()}',
            textAlign: TextAlign.center,
            style: t.labelSmall?.copyWith(color: C.text3),
          ),
        );
        return SizedBox(
          height: _dot + S.sm + 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: (_dot - _bar) / 2,
                height: _bar,
                child: CustomPaint(
                  painter: _ScalePainter(lo, hi, min, max, zone),
                ),
              ),
              if (v != null)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: x(v)),
                  duration: const Duration(milliseconds: 1600),
                  curve: Curves.easeInOutCubic,
                  // a slim white needle standing across the bar
                  builder: (_, px, _) => Positioned(
                    left: (px - 4).clamp(0.0, box.maxWidth - 8),
                    top: 0,
                    child: Container(
                      width: 8,
                      height: _dot,
                      decoration: BoxDecoration(
                        color: C.text,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: C.surface, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              label(min - voltSeriousMargin),
              label(min),
              label(max),
              label(max + voltSeriousMargin),
            ],
          ),
        );
      },
    );
  }
}

class _ScalePainter extends CustomPainter {
  _ScalePainter(this.lo, this.hi, this.min, this.max, this.active);
  final double lo, hi, min, max;
  final int? active; // zone the live value is in; null = no live value

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * size.width;
    final h = size.height;
    final zones = [
      (lo, min - voltSeriousMargin, C.critical),
      (min - voltSeriousMargin, min, C.warning),
      (min, max, C.series),
      (max, max + voltSeriousMargin, C.warning),
      (max + voltSeriousMargin, hi, C.critical),
    ];
    for (var i = 0; i < zones.length; i++) {
      final (a, b, c) = zones[i];
      final alpha = active == null
          ? (i == 2 ? 0.8 : 0.4)
          : (i == active ? 1.0 : 0.3);
      // 3 px gaps between zones keep them readable without relying on hue
      final left = x(a) + (i == 0 ? 0 : 1.5),
          right = x(b) - (i == zones.length - 1 ? 0 : 1.5);
      final r = Radius.circular(h / 2);
      final rr = RRect.fromLTRBAndCorners(
        left,
        0,
        right,
        h,
        topLeft: i == 0 ? r : const Radius.circular(3),
        bottomLeft: i == 0 ? r : const Radius.circular(3),
        topRight: i == zones.length - 1 ? r : const Radius.circular(3),
        bottomRight: i == zones.length - 1 ? r : const Radius.circular(3),
      );
      canvas.drawRRect(rr, Paint()..color = c.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_ScalePainter o) =>
      o.min != min || o.max != max || o.active != active;
}

/// Owner edits the home's normal voltage range.
Future<(double, double)?> showVoltageRangeSheet(BuildContext context, Meter m) {
  return showModalBottomSheet<(double, double)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RangeSheet(initial: RangeValues(m.voltMin, m.voltMax)),
  );
}

class _RangeSheet extends StatefulWidget {
  const _RangeSheet({required this.initial});
  final RangeValues initial;
  @override
  State<_RangeSheet> createState() => _RangeSheetState();
}

class _RangeSheetState extends State<_RangeSheet> {
  late RangeValues r = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lo = r.start.round(), hi = r.end.round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Normal voltage', style: t.titleLarge),
            const SizedBox(height: S.sm),
            Text(
              'More than ${voltGrace.round()} V outside this range gives a warning. More than ${voltSeriousMargin.round()} V outside is a serious warning.',
              style: t.bodyMedium?.copyWith(color: C.text2),
            ),
            const SizedBox(height: S.xl),
            Center(child: Text('$lo – $hi V', style: t.headlineMedium)),
            RangeSlider(
              values: r,
              min: 170,
              max: 260,
              divisions: 90,
              activeColor: C.brand,
              inactiveColor: C.surface2,
              labels: RangeLabels('$lo V', '$hi V'),
              onChanged: (v) {
                if (v.end - v.start >= 10) setState(() => r = v);
              },
            ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'A bit low: ${lo - voltSeriousMargin.round()}–${lo - voltGrace.round()} V · A bit high: ${hi + voltGrace.round()}–${hi + voltSeriousMargin.round()} V\n'
                    'Serious: below ${lo - voltSeriousMargin.round()} V or above ${hi + voltSeriousMargin.round()} V',
                    style: t.bodySmall?.copyWith(color: C.text2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.xl),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => r = const RangeValues(200, 230)),
                  child: const Text('Reset to 200–230 V'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    r.start.roundToDouble(),
                    r.end.roundToDouble(),
                  )),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
