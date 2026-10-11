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

/// "6 AM", "12 PM".
String _hourText(DateTime t) => DateFormat('h a').format(t);

/// "2–3 PM", "11 AM–12 PM".
String _hourRange(DateTime t) {
  final end = DateTime(t.year, t.month, t.day, t.hour + 1);
  return DateFormat('a').format(t) == DateFormat('a').format(end)
      ? '${DateFormat('h').format(t)}–${_hourText(end)}'
      : '${_hourText(t)}–${_hourText(end)}';
}

/// Today's power, hour by hour (the average of the meter's 5-minute
/// records), as a soft area with a bubble. Two halves of 12 hours, AM and
/// PM: swipe the chart or use ‹ AM › in the title row. Each hour is labelled
/// by the hour it ends on, 1 … 12, so a half reads like a clock face; the
/// bubble spells it out ("1.2 kW · 8–9 AM"). It sits on the busiest hour of
/// the half until you tap another one (tap it again to go back).
class PowerAreaChart extends StatefulWidget {
  const PowerAreaChart({
    super.key,
    required this.points,
    this.height = 190,
    this.now,
  });
  final List<PowerPoint> points;
  final double height;
  final DateTime? now; // for tests

  @override
  State<PowerAreaChart> createState() => _PowerAreaChartState();
}

class _PowerAreaChartState extends State<PowerAreaChart> {
  late int _half = _currentHalf; // 0 = AM, 1 = PM
  late final PageController _pages = PageController(initialPage: _half);
  int? _picked; // hour of today, 0..23

  DateTime get _now => widget.now ?? DateTime.now();
  int get _currentHalf => _now.hour < 12 ? 0 : 1; // opens where "now" is

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Today's 24 hours: [h] = average power from h:00 to h+1:00, null when
  /// the meter recorded nothing then.
  List<double?> _hours() {
    final now = _now;
    final sum = List<double>.filled(24, 0);
    final n = List<int>.filled(24, 0);
    for (final p in widget.points) {
      // a record is stamped at the end of its 5 minutes
      final t = p.ts.subtract(const Duration(minutes: 1));
      if (t.year != now.year || t.month != now.month || t.day != now.day) {
        continue;
      }
      sum[t.hour] += p.avgW;
      n[t.hour]++;
    }
    return [for (var h = 0; h < 24; h++) n[h] == 0 ? null : sum[h] / n[h]];
  }

  void _show(int half) {
    if (half == _half) return;
    setState(() {
      _half = half;
      _picked = null;
    });
    _pages.animateToPage(
      half,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hours = _hours();
    final values = hours.whereType<double>();
    final top = values.isEmpty ? 0.0 : values.reduce(max);

    final header = Padding(
      padding: const EdgeInsets.only(left: S.sm, bottom: S.sm),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Text('Average per hour', style: t.labelMedium?.copyWith(color: C.text2)),
            const Spacer(),
            _HalfSwitch(half: _half, onChanged: _show),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: widget.height,
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() {
              _half = i;
              _picked = null;
            }),
            children: [
              for (final half in const [0, 1]) _page(half, hours, top),
            ],
          ),
        ),
      ],
    );
  }

  /// One half: 12 hours, labelled 1 … 12.
  Widget _page(int half, List<double?> hours, double top) {
    final first = half * 12;
    final w = hours.sublist(first, first + 12);
    final withData = [
      for (var i = 0; i < 12; i++)
        if (w[i] != null) i,
    ];
    final now = _now;
    if (withData.isEmpty) {
      final future = first > now.hour;
      return Center(
        child: Text(
          future
              ? 'The afternoon hasn\'t started yet'
              : half == 0
              ? 'No readings this morning'
              : 'No readings this afternoon',
          style: _axisStyle.copyWith(fontSize: 13),
        ),
      );
    }

    final day = DateTime(now.year, now.month, now.day);
    final picked = _picked != null && _picked! ~/ 12 == half
        ? _picked! - first
        : null;
    final mark =
        picked ?? withData.reduce((a, b) => w[b]! > w[a]! ? b : a); // busiest
    final scale = top >= 1000 ? 1000.0 : 1.0;
    bool alone(int i) =>
        (i == 0 || w[i - 1] == null) && (i == 11 || w[i + 1] == null);

    final bar = LineChartBarData(
      spots: [
        for (var i = 0; i < 12; i++)
          w[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), w[i]! / scale),
      ],
      isCurved: true,
      curveSmoothness: 0.3,
      preventCurveOverShooting: true,
      color: _powerLine,
      barWidth: 2.5,
      isStrokeCapRound: true,
      // an hour with no neighbours has no line to sit on: a dot (unless it's
      // ~0 W, which would only look like a stray mark on the baseline)
      dotData: FlDotData(
        checkToShowDot: (spot, _) =>
            alone(spot.x.round()) && w[spot.x.round()]! >= 1,
        getDotPainter: (_, _, _, _) =>
            FlDotCirclePainter(radius: 3.5, color: _powerLine, strokeWidth: 0),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _powerLine.withValues(alpha: 0.45),
            _powerLine.withValues(alpha: 0.03),
          ],
        ),
      ),
      showingIndicators: [mark],
    );

    final maxY = max(top / scale, 1e-6) * 1.55; // room above for the bubble
    final chart = LineChart(
      LineChartData(
        minX: -1.05, // room for the clock icon and the first hour's glow
        maxX: 11.65,
        minY: 0,
        maxY: maxY,
        // faint guide lines, no numbers: the bubble gives the value
        gridData: _grid(maxY / 4),
        borderData: FlBorderData(
          show: true,
          border: const Border(bottom: BorderSide(color: C.grid)),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i > 11) {
                  return const SizedBox.shrink();
                }
                final current = first + i == now.hour;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${i + 1}',
                    style: _axisStyle.copyWith(
                      color: i == mark
                          ? C.text
                          : current
                          ? C.brand
                          : C.text3,
                      fontWeight: i == mark || current
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        showingTooltipIndicators: [
          ShowingTooltipIndicators([LineBarSpot(bar, 0, bar.spots[mark])]),
        ],
        lineTouchData: LineTouchData(
          // our own handling: tap an hour to put the bubble there
          handleBuiltInTouches: false,
          touchSpotThreshold: double.infinity,
          distanceCalculator: (touch, spot) => (touch.dx - spot.dx).abs(),
          getTouchLineStart: (_, _) => 0,
          getTouchLineEnd: (bar, i) => bar.spots[i].y,
          touchCallback: (event, resp) {
            if (event is! FlTapUpEvent) return;
            final hit = resp?.lineBarSpots;
            if (hit == null || hit.isEmpty) return;
            final i = hit.first.spotIndex;
            if (w[i] == null) return;
            setState(() => _picked = picked == i ? null : first + i);
          },
          getTouchedSpotIndicator: (bar, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(
                  color: _powerLine.withValues(alpha: 0.6),
                  strokeWidth: 1.2,
                  dashArray: const [4, 4],
                ),
                FlDotData(getDotPainter: (_, _, _, _) => const _GlowDot()),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => C.surface2,
            tooltipBorder: BorderSide(color: _powerLine.withValues(alpha: 0.5)),
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
                  '${fmtPowerText(w[mark]!)}\n',
                  const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: C.text,
                  ),
                  children: [
                    TextSpan(
                      text: _hourRange(
                        DateTime(day.year, day.month, day.day, first + mark),
                      ),
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
    );
    // a small clock before the 1 … 12: these are hours
    return Stack(
      children: [
        chart,
        const Positioned(
          left: 0,
          bottom: 6,
          child: Icon(Icons.schedule_rounded, size: 14, color: C.text3),
        ),
      ],
    );
  }
}

/// ‹ AM › — which half of the day the power chart shows.
class _HalfSwitch extends StatelessWidget {
  const _HalfSwitch({required this.half, required this.onChanged});
  final int half; // 0 = AM, 1 = PM
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget arrow(IconData icon, int to, bool enabled) => SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 22,
        onPressed: enabled ? () => onChanged(to) : null,
        icon: Icon(icon, color: enabled ? C.text : C.text3.withValues(alpha: 0.35)),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.chevron_left_rounded, 0, half == 1),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              key: ValueKey(half),
              width: 30,
              child: Text(
                half == 0 ? 'AM' : 'PM',
                textAlign: TextAlign.center,
                style: t.labelMedium?.copyWith(
                  color: C.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          arrow(Icons.chevron_right_rounded, 1, half == 0),
        ],
      ),
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
    Bucket.hour => DateFormat('h a').format(t),
    Bucket.day =>
      widget.points.length <= 7
          ? DateFormat('E').format(t)
          : DateFormat('d').format(t),
    Bucket.month => DateFormat('MMM').format(t),
  };

  String _peakLabel(DateTime t) => switch (widget.bucket) {
    Bucket.hour => _hourText(t),
    Bucket.day => DateFormat('EEE d').format(t),
    Bucket.month => DateFormat('MMM').format(t),
  };

  String _when(DateTime t) => switch (widget.bucket) {
    Bucket.hour => _hourRange(t),
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
