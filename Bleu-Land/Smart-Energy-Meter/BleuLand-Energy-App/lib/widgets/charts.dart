// Charts, following the data-viz rules: one series in the chart teal,
// 2px lines with a 10 % wash, bars at most 24px wide with 4px rounded tops,
// hairline solid gridlines, clean round ticks. Touch: the value shows in the
// chart's title row (never under the finger) and stays after lifting it.
import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../theme/tokens.dart';

/// Round axis maximum and step: 0 / 0.5 / 1 / 1.5 ... (1-2-5 steps, 4 lines).
({double max, double step}) niceAxis(double dataMax, {int lines = 4}) {
  if (dataMax <= 0) return (max: 1, step: 0.25);
  final raw = dataMax / lines;
  final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
  final norm = raw / mag;
  final step =
      (norm <= 1
          ? 1
          : norm <= 2
          ? 2
          : norm <= 2.5
          ? 2.5
          : norm <= 5
          ? 5
          : 10) *
      mag;
  return (max: step * (dataMax / step).ceil(), step: step);
}

/// Axis label with as many decimals as the step needs (0.25 → 2, 0.5 → 1, 2 → 0).
String _tick(double v, double step) {
  if (v.abs() < 1e-9) return '0';
  var decimals = 0;
  while (decimals < 3 &&
      ((step * pow(10, decimals)) - (step * pow(10, decimals)).roundToDouble())
              .abs() >
          1e-6) {
    decimals++;
  }
  return NumberFormat('#,##0${decimals > 0 ? '.${'0' * decimals}' : ''}')
      .format(v);
}

const _axisStyle = TextStyle(
  fontFamily: 'Poppins',
  fontSize: 11,
  color: C.text3,
  fontFeatures: [FontFeature.tabularFigures()],
);

FlGridData _grid(double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) => const FlLine(color: C.grid, strokeWidth: 1),
);

/// The chart's title row: the title, plus a quiet summary (e.g. the peak) on
/// the right. While a point is picked the whole row becomes its readout:
/// ‹ value · time › and a x to clear. The arrows step one point at a time
/// (hold to keep going), for exact picks where the points are close.
class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.title,
    this.value,
    this.when,
    this.summary,
    this.onClear,
    this.onPrev,
    this.onNext,
  });
  final String title;
  final String? value, when; // picked point
  final String? summary; // shown when nothing is picked
  final VoidCallback? onClear, onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final picked = value != null;
    return Padding(
      padding: const EdgeInsets.only(left: S.sm, bottom: S.md),
      child: SizedBox(
        height: 36,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: picked
              ? Container(
                  key: const ValueKey('picked'),
                  decoration: BoxDecoration(
                    color: C.surface2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    children: [
                      _StepButton(
                        icon: Icons.chevron_left_rounded,
                        onStep: onPrev,
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                value!,
                                style: t.titleSmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                when ?? '',
                                style: t.labelMedium?.copyWith(color: C.text2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _StepButton(
                        icon: Icons.chevron_right_rounded,
                        onStep: onNext,
                      ),
                      Container(width: 1, height: 18, color: C.outline),
                      SizedBox(
                        width: 40,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          tooltip: 'Clear',
                          onPressed: onClear,
                          icon: const Icon(Icons.close_rounded, color: C.text3),
                        ),
                      ),
                    ],
                  ),
                )
              : Row(
                  key: const ValueKey('title'),
                  children: [
                    Text(title, style: t.labelMedium?.copyWith(color: C.text2)),
                    const Spacer(),
                    Text(
                      summary ?? '',
                      style: t.labelSmall?.copyWith(color: C.text3),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// ‹ / › : tap for one step, hold to keep stepping. Greyed out at the ends.
class _StepButton extends StatefulWidget {
  const _StepButton({required this.icon, this.onStep});
  final IconData icon;
  final VoidCallback? onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onStep != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStep,
      onLongPressStart: on
          ? (_) => _repeat = Timer.periodic(
              const Duration(milliseconds: 110),
              (_) => widget.onStep?.call(),
            )
          : null,
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: SizedBox(
        width: 44,
        height: 36,
        child: Icon(
          widget.icon,
          size: 24,
          color: on ? C.text : C.text3.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// 24 h · 6 h · 1 h: how much of the day the power chart shows.
class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.hours, required this.onChanged});
  final int hours;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final h in const [24, 6, 1])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => onChanged(h),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: h == hours
                      ? C.series.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$h h',
                  style: t.labelMedium?.copyWith(
                    color: h == hours ? C.brand : C.text3,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Glowing dot for the picked / peak point: soft halo, teal ring, white core.
class _GlowDot extends FlDotPainter {
  const _GlowDot();

  @override
  void draw(Canvas canvas, FlSpot spot, Offset c) {
    canvas.drawCircle(
      c,
      15,
      Paint()..color = _powerLine.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      c,
      9,
      Paint()
        ..color = _powerLine.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(c, 6, Paint()..color = _powerLine);
    canvas.drawCircle(c, 3, Paint()..color = Colors.white);
  }

  @override
  Size getSize(FlSpot spot) => const Size(30, 30);

  @override
  Color get mainColor => _powerLine;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => const [];
}

const _powerLine = Color(0xFF3FD9B3); // a lighter teal for the line on dark

/// One time slot of the power chart. [w] is the real average (null = the
/// meter wasn't reporting: drawn as a gap); [shown] is what the line draws
/// (lightly smoothed at 24 h, so the fridge switching doesn't zig-zag it).
class _Slot {
  _Slot(this.start, this.w);
  final DateTime start;
  final double? w;
  double? shown;
}

/// Power over the last 24 h, in kW: a soft area with a bubble. The bubble
/// marks the peak until you tap or slide; then it shows that moment and
/// stays there after the finger lifts. 24 h / 6 h / 1 h under the chart,
/// and ‹ › in the title row step one slot at a time.
class PowerAreaChart extends StatefulWidget {
  const PowerAreaChart({
    super.key,
    required this.points,
    this.title = 'Power, kW',
    this.height = 190,
  });
  final List<PowerPoint> points;
  final String title;
  final double height;

  @override
  State<PowerAreaChart> createState() => _PowerAreaChartState();
}

class _PowerAreaChartState extends State<PowerAreaChart> {
  DateTime? _picked; // the picked moment; survives new data and range changes
  int _hours = 24; // 24 / 6 / 1

  /// 15-minute slots at 24 h, the meter's own 5-minute records at 6 h / 1 h.
  List<_Slot> _slots() {
    final all = widget.points;
    if (all.isEmpty) return const [];
    final step = _hours >= 24 ? 15 : 5;
    final end = all.last.ts;
    final from = end.subtract(Duration(hours: _hours));
    DateTime floor(DateTime t) =>
        DateTime(t.year, t.month, t.day, t.hour, t.minute - t.minute % step);
    final sums = <DateTime, List<double>>{};
    for (final p in all) {
      if (!p.ts.isAfter(from)) continue;
      (sums[floor(p.ts)] ??= []).add(p.avgW);
    }
    if (sums.isEmpty) return const [];
    final slots = <_Slot>[];
    for (
      var t = floor(sums.keys.reduce((a, b) => a.isBefore(b) ? a : b));
      !t.isAfter(floor(end));
      t = t.add(Duration(minutes: step))
    ) {
      final v = sums[t];
      slots.add(
        _Slot(t, v == null ? null : v.reduce((a, b) => a + b) / v.length),
      );
    }
    for (var i = 0; i < slots.length; i++) {
      final w = slots[i].w;
      if (w == null) continue;
      if (_hours < 24) {
        slots[i].shown = w;
        continue;
      }
      // light smoothing that never bridges a gap
      final near = [
        w,
        if (i > 0 && slots[i - 1].w != null) slots[i - 1].w!,
        if (i < slots.length - 1 && slots[i + 1].w != null) slots[i + 1].w!,
      ];
      slots[i].shown = near.reduce((a, b) => a + b) / near.length;
    }
    return slots;
  }

  int? _indexOf(List<_Slot> slots, DateTime? t) {
    if (t == null) return null;
    final step = _hours >= 24 ? 15 : 5;
    final i = slots.indexWhere(
      (s) =>
          !t.isBefore(s.start) &&
          t.isBefore(s.start.add(Duration(minutes: step))),
    );
    return i < 0 || slots[i].w == null ? null : i;
  }

  /// The next slot with data in direction [dir] (-1 / +1), or null.
  int? _step(List<_Slot> slots, int from, int dir) {
    for (var i = from + dir; i >= 0 && i < slots.length; i += dir) {
      if (slots[i].w != null) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final slots = _slots();
    final withData = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i].w != null) i,
    ];
    final picked = _indexOf(slots, _picked);
    final prev = picked == null ? null : _step(slots, picked, -1);
    final next = picked == null ? null : _step(slots, picked, 1);

    final header = Padding(
      padding: const EdgeInsets.only(left: S.sm, bottom: S.md),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Text(widget.title, style: t.labelMedium?.copyWith(color: C.text2)),
            const Spacer(),
            if (picked != null) ...[
              _StepButton(
                icon: Icons.chevron_left_rounded,
                onStep: prev == null
                    ? null
                    : () => setState(() => _picked = slots[prev].start),
              ),
              _StepButton(
                icon: Icons.chevron_right_rounded,
                onStep: next == null
                    ? null
                    : () => setState(() => _picked = slots[next].start),
              ),
              SizedBox(
                width: 40,
                height: 36,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  tooltip: 'Back to the peak',
                  onPressed: () => setState(() => _picked = null),
                  icon: const Icon(Icons.close_rounded, color: C.text3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final chips = [
      const SizedBox(height: S.sm),
      _RangeChips(hours: _hours, onChanged: (h) => setState(() => _hours = h)),
    ];

    if (withData.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(
            height: widget.height,
            child: Center(
              child: Text(
                'Not enough data yet',
                style: _axisStyle.copyWith(fontSize: 13),
              ),
            ),
          ),
          if (widget.points.length >= 2) ...chips,
        ],
      );
    }

    // x = minutes since midnight, so time labels land on round times
    final first = slots.first.start;
    final origin = DateTime(first.year, first.month, first.day);
    double x(DateTime t) => t.difference(origin).inSeconds / 60;
    final labelEvery = switch (_hours) {
      1 => 15,
      6 => 120,
      _ => 360,
    }; // minutes
    final peak = withData.reduce((a, b) => slots[b].w! > slots[a].w! ? b : a);
    final top =
        withData.map((i) => max(slots[i].w!, slots[i].shown!)).reduce(max) /
        1000;
    final axis = niceAxis(top * 1.25); // room above the line for the bubble
    final mark = picked ?? peak; // where the bubble sits
    final bar = LineChartBarData(
      spots: [
        for (final s in slots)
          s.shown == null
              ? FlSpot.nullSpot
              : FlSpot(x(s.start), s.shown! / 1000),
      ],
      isCurved: true,
      curveSmoothness: 0.3,
      preventCurveOverShooting: true,
      color: _powerLine,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: _hours == 1,
      ), // at 1 h every 5-minute record is a dot
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _powerLine.withValues(alpha: 0.45),
            _powerLine.withValues(alpha: 0.04),
          ],
        ),
      ),
      showingIndicators: [mark],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: widget.height,
          child: LineChart(
            LineChartData(
              minX: x(first),
              maxX: x(slots.last.start),
              minY: 0,
              maxY: axis.max,
              gridData: _grid(axis.step / 2),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: axis.step,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(_tick(v, axis.step), style: _axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: labelEvery.toDouble(),
                    getTitlesWidget: (v, meta) {
                      // only round times (not the chart's first/last point)
                      if (v.round() % labelEvery != 0) {
                        return const SizedBox.shrink();
                      }
                      final t = origin.add(Duration(minutes: v.round()));
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          DateFormat('HH:mm').format(t),
                          style: _axisStyle,
                        ),
                      );
                    },
                  ),
                ),
              ),
              showingTooltipIndicators: [
                ShowingTooltipIndicators([
                  LineBarSpot(bar, 0, bar.spots[mark]),
                ]),
              ],
              lineTouchData: LineTouchData(
                // our own handling: the bubble moves to the touched moment and stays
                handleBuiltInTouches: false,
                touchSpotThreshold: double.infinity,
                distanceCalculator: (touch, spot) =>
                    (touch.dx - spot.dx).abs(), // nearest in time
                getTouchLineStart: (_, _) => 0,
                getTouchLineEnd: (bar, i) => bar.spots[i].y,
                touchCallback: (event, resp) {
                  if (!event.isInterestedForInteractions) return;
                  final hit = resp?.lineBarSpots;
                  if (hit == null || hit.isEmpty) return;
                  final s = slots[hit.first.spotIndex];
                  if (s.w != null && s.start != _picked) {
                    setState(() => _picked = s.start);
                  }
                },
                getTouchedSpotIndicator: (bar, idx) => [
                  for (final _ in idx)
                    TouchedSpotIndicatorData(
                      FlLine(
                        color: _powerLine.withValues(alpha: 0.6),
                        strokeWidth: 1.2,
                        dashArray: const [4, 4],
                      ),
                      FlDotData(
                        getDotPainter: (_, _, _, _) => const _GlowDot(),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => C.surface2,
                  tooltipBorder: BorderSide(
                    color: _powerLine.withValues(alpha: 0.5),
                  ),
                  tooltipBorderRadius: BorderRadius.circular(10),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  tooltipMargin: 22,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final _ in spots)
                      LineTooltipItem(
                        '${fmtPowerText(slots[mark].w!)}\n',
                        const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: C.text,
                        ),
                        children: [
                          TextSpan(
                            text:
                                '${picked == null ? 'Peak · ' : ''}${DateFormat('HH:mm').format(slots[mark].start)}',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: C.text2,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [bar],
            ),
            duration: const Duration(milliseconds: 250),
          ),
        ),
        ...chips,
      ],
    );
  }
}

/// kWh per hour / day / month as columns. Tap or slide across to see a value.
class EnergyBarChart extends StatefulWidget {
  const EnergyBarChart({
    super.key,
    required this.points,
    required this.bucket,
    required this.title,
    this.height = 220,
    this.highlight,
    this.labelEvery = 1,
  });

  final List<EnergyPoint> points;
  final Bucket bucket;
  final String title;
  final double height;
  final DateTime? highlight; // e.g. today
  final int labelEvery;

  @override
  State<EnergyBarChart> createState() => _EnergyBarChartState();
}

class _EnergyBarChartState extends State<EnergyBarChart> {
  int? _sel;

  @override
  void didUpdateWidget(EnergyBarChart old) {
    super.didUpdateWidget(old);
    // another period or bucket: start without a pick
    final same =
        old.bucket == widget.bucket &&
        old.points.length == widget.points.length &&
        (widget.points.isEmpty ||
            old.points.first.start == widget.points.first.start);
    if (!same) _sel = null;
  }

  String _label(DateTime t) => switch (widget.bucket) {
    Bucket.hour => DateFormat('HH').format(t),
    Bucket.day =>
      widget.points.length <= 7
          ? DateFormat('E').format(t)
          : DateFormat('d').format(t),
    Bucket.month => DateFormat('MMM').format(t),
  };

  String _peakLabel(DateTime t) => switch (widget.bucket) {
    Bucket.hour => DateFormat('HH:00').format(t),
    Bucket.day => DateFormat('EEE d').format(t),
    Bucket.month => DateFormat('MMM').format(t),
  };

  String _when(DateTime t) => switch (widget.bucket) {
    Bucket.hour =>
      '${DateFormat('HH:00').format(t)}–${DateFormat('HH:00').format(t.add(const Duration(hours: 1)))}',
    Bucket.day => DateFormat('EEE d MMM').format(t),
    Bucket.month => DateFormat('MMM yyyy').format(t),
  };

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final maxY = points.isEmpty ? 0.0 : points.map((p) => p.kwh).reduce(max);
    final axis = niceAxis(maxY * 1.08);
    final peak = points.isEmpty
        ? null
        : points.reduce((a, b) => b.kwh > a.kwh ? b : a);
    final sel = _sel != null && _sel! < points.length ? _sel : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartHeader(
          title: widget.title,
          value: sel == null ? null : fmtKwh(points[sel].kwh),
          when: sel == null ? null : _when(points[sel].start),
          summary: peak != null && peak.kwh > 0
              ? 'Peak ${_peakLabel(peak.start)} · ${fmtKwh(peak.kwh)}'
              : null,
          onClear: () => setState(() => _sel = null),
          onPrev: sel != null && sel > 0
              ? () => setState(() => _sel = sel - 1)
              : null,
          onNext: sel != null && sel < points.length - 1
              ? () => setState(() => _sel = (_sel ?? sel) + 1)
              : null,
        ),
        LayoutBuilder(
          builder: (context, box) {
            final slot = (box.maxWidth - 40) / max(points.length, 1);
            final barW = min(24.0, max(3.0, slot * 0.62));
            return SizedBox(
              height: widget.height,
              child: BarChart(
                BarChartData(
                  maxY: axis.max,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: _grid(axis.step),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: axis.step,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(_tick(v, axis.step), style: _axisStyle),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 ||
                              i >= points.length ||
                              i % widget.labelEvery != 0) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _label(points[i].start),
                              style: _axisStyle,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    // our own handling: no floating tooltip, and the pick stays;
                    // the whole column (not just the bar) answers the finger
                    handleBuiltInTouches: false,
                    allowTouchBarBackDraw: true,
                    touchExtraThreshold: EdgeInsets.symmetric(
                      horizontal: slot / 2,
                    ),
                    touchCallback: (event, resp) {
                      if (!event.isInterestedForInteractions) return;
                      final i = resp?.spot?.touchedBarGroupIndex;
                      if (i != null && i != _sel) setState(() => _sel = i);
                    },
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: points[i].kwh,
                            width: barW,
                            color: i == sel
                                ? C.brand
                                : sel != null
                                ? C.series.withValues(
                                    alpha: 0.55,
                                  ) // others step back while one is picked
                                : widget.highlight != null &&
                                      points[i].start == widget.highlight
                                ? C.brand
                                : C.series,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 300),
              ),
            );
          },
        ),
      ],
    );
  }
}
