import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/levels.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// Mains voltage: live value on a scale with the home's normal range, a
/// plain-words status, and today's lowest and highest. The range itself is
/// changed in Settings.
class VoltageCard extends StatefulWidget {
  const VoltageCard({super.key, required this.reading, required this.meter});
  final LiveReading? reading;
  final Meter meter;

  @override
  State<VoltageCard> createState() => _VoltageCardState();
}

class _VoltageCardState extends State<VoltageCard> {
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
    final m = widget.meter;
    final r = widget.reading;
    final now = DateTime.now();
    // Nothing to show while the meter is offline: hide the whole card.
    final reporting =
        r != null && now.difference(r.ts) <= AppConfig.offlineAfter;
    if (!reporting) return const SizedBox.shrink();
    final live = r.volts >= 100; // below 100 V = no mains (e.g. bench supply)
    final v = live ? r.volts : null;
    final status = v == null
        ? null
        : voltStatus(v, min: m.voltMin, max: m.voltMax);
    final today = r.voltToday(now);

    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Panel(
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
                if (v == null)
                  Text(
                    'No mains voltage',
                    style: t.titleMedium?.copyWith(color: C.text2),
                  )
                else ...[
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
                ],
                const Spacer(),
                if (status != null) _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: S.md),
            _VoltScale(min: m.voltMin, max: m.voltMax, value: v),
            if (status?.advice != null) ...[
              const SizedBox(height: S.md),
              Container(
                padding: const EdgeInsets.all(S.md),
                decoration: BoxDecoration(
                  color: _color(status!).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icon(status), size: 18, color: _color(status)),
                    const SizedBox(width: S.sm),
                    Expanded(
                      child: Text(
                        status.advice!,
                        style: t.bodySmall?.copyWith(color: C.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: S.md),
            // lowest on the left edge, highest on the right edge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DayStat(
                  label: 'Lowest today',
                  v: today?.min,
                  at: today?.minAt,
                  m: m,
                ),
                _DayStat(
                  label: 'Highest today',
                  v: today?.max,
                  at: today?.maxAt,
                  m: m,
                  end: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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

class _DayStat extends StatelessWidget {
  const _DayStat({
    required this.label,
    required this.v,
    required this.at,
    required this.m,
    this.end = false,
  });
  final String label;
  final bool end; // right-aligned
  final double? v;
  final DateTime? at;
  final Meter m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final value = v;
    final s = value == null
        ? null
        : voltStatus(value, min: m.voltMin, max: m.voltMax);
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelSmall?.copyWith(color: C.text3)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value == null ? '–' : fmtVolts(value), style: t.titleSmall),
            if (s != null && s != VoltStatus.normal) ...[
              const SizedBox(width: 4),
              Icon(Icons.warning_amber_rounded, size: 14, color: _color(s)),
            ],
            if (at != null) ...[
              const SizedBox(width: 6),
              Text(
                DateFormat('HH:mm').format(at!),
                style: t.labelSmall?.copyWith(color: C.text3),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A horizontal scale: serious | a little low | normal | a little high | serious,
/// with the live value as a dot.
class _VoltScale extends StatelessWidget {
  const _VoltScale({required this.min, required this.max, this.value});
  final double min, max;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final lo = min - voltSeriousMargin * 2.5,
        hi = max + voltSeriousMargin * 2.5;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) {
        double x(double v) =>
            ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * box.maxWidth;
        Widget label(double v) => Positioned(
          left: x(v) - 20,
          width: 40,
          top: 22,
          child: Text(
            '${v.round()}',
            textAlign: TextAlign.center,
            style: t.labelSmall?.copyWith(color: C.text3),
          ),
        );
        return SizedBox(
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                bottom: 22,
                child: CustomPaint(painter: _ScalePainter(lo, hi, min, max)),
              ),
              if (value != null)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: x(value!)),
                  duration: const Duration(milliseconds: 1600),
                  curve: Curves.easeInOutCubic,
                  builder: (_, px, _) => Positioned(
                    left: px - 7,
                    top: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: C.text,
                        shape: BoxShape.circle,
                        border: Border.all(color: C.surface, width: 3),
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
  _ScalePainter(this.lo, this.hi, this.min, this.max);
  final double lo, hi, min, max;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * size.width;
    const h = 6.0;
    final y = 9.0 - h / 2;
    final zones = [
      (lo, min - voltSeriousMargin, C.critical.withValues(alpha: 0.45)),
      (min - voltSeriousMargin, min, C.warning.withValues(alpha: 0.45)),
      (min, max, C.series),
      (max, max + voltSeriousMargin, C.warning.withValues(alpha: 0.45)),
      (max + voltSeriousMargin, hi, C.critical.withValues(alpha: 0.45)),
    ];
    for (var i = 0; i < zones.length; i++) {
      final (a, b, c) = zones[i];
      // 2px gaps between zones keep them readable without relying on hue
      final left = x(a) + (i == 0 ? 0 : 1),
          right = x(b) - (i == zones.length - 1 ? 0 : 1);
      final rr = RRect.fromLTRBAndCorners(
        left,
        y,
        right,
        y + h,
        topLeft: Radius.circular(i == 0 ? h / 2 : 0),
        bottomLeft: Radius.circular(i == 0 ? h / 2 : 0),
        topRight: Radius.circular(i == zones.length - 1 ? h / 2 : 0),
        bottomRight: Radius.circular(i == zones.length - 1 ? h / 2 : 0),
      );
      canvas.drawRRect(rr, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_ScalePainter o) => o.min != min || o.max != max;
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
