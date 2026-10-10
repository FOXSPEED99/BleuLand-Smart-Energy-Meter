// Charts, following the data-viz rules: one series in the chart teal,
// 2px lines with a 10 % wash, bars at most 24px wide with 4px rounded tops,
// hairline solid gridlines, clean round ticks. Touch: the value shows in the
// chart's title row (never under the finger) and stays after lifting it.
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
  final step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;
  return (max: step * (dataMax / step).ceil(), step: step);
}

/// Axis label with as many decimals as the step needs (0.25 → 2, 0.5 → 1, 2 → 0).
String _tick(double v, double step) {
  if (v.abs() < 1e-9) return '0';
  var decimals = 0;
  while (decimals < 3 && ((step * pow(10, decimals)) - (step * pow(10, decimals)).roundToDouble()).abs() > 1e-6) {
    decimals++;
  }
  return NumberFormat('#,##0${decimals > 0 ? '.${'0' * decimals}' : ''}').format(v);
}

const _axisStyle = TextStyle(fontFamily: 'Poppins', fontSize: 11, color: C.text3, fontFeatures: [FontFeature.tabularFigures()]);

FlGridData _grid(double step) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (_) => const FlLine(color: C.grid, strokeWidth: 1),
    );

/// The chart's title row: the title on the left; on the right the touched
/// value and time (with a × to clear), or a quiet summary such as the peak.
class _ChartHeader extends StatelessWidget {
  const _ChartHeader({required this.title, this.value, this.when, this.summary, this.onClear});
  final String title;
  final String? value, when; // touched point
  final String? summary; // shown when nothing is touched
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final picked = value != null;
    return Padding(
      padding: const EdgeInsets.only(left: S.sm, bottom: S.md),
      child: SizedBox(
        height: 30,
        child: Row(children: [
          Text(title, style: t.labelMedium?.copyWith(color: C.text2)),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: picked
                ? Container(
                    key: const ValueKey('picked'),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(value!, style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(width: 6),
                      Text(when ?? '', style: t.labelSmall?.copyWith(color: C.text2)),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          tooltip: 'Clear',
                          onPressed: onClear,
                          icon: const Icon(Icons.close_rounded, color: C.text3),
                        ),
                      ),
                    ]),
                  )
                : Text(summary ?? '', key: const ValueKey('summary'), style: t.labelSmall?.copyWith(color: C.text3)),
          ),
        ]),
      ),
    );
  }
}

/// Power over the last 24 h (5-minute averages), in kW.
class PowerAreaChart extends StatefulWidget {
  const PowerAreaChart({super.key, required this.points, this.title = 'Power, kW', this.height = 180});
  final List<PowerPoint> points;
  final String title;
  final double height;

  @override
  State<PowerAreaChart> createState() => _PowerAreaChartState();
}

class _PowerAreaChartState extends State<PowerAreaChart> {
  int? _sel; // touched point; stays after the finger lifts

  @override
  void didUpdateWidget(PowerAreaChart old) {
    super.didUpdateWidget(old);
    // new data every few minutes: keep the same moment selected if it's still there
    if (_sel != null) {
      final ts = _sel! < old.points.length ? old.points[_sel!].ts : null;
      final i = ts == null ? -1 : widget.points.indexWhere((p) => p.ts == ts);
      _sel = i < 0 ? null : i;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final height = widget.height;
    if (points.length < 2) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ChartHeader(title: widget.title),
        SizedBox(
          height: height,
          child: Center(child: Text('Not enough data yet', style: _axisStyle.copyWith(fontSize: 13))),
        ),
      ]);
    }
    final t0 = points.first.ts;
    double x(DateTime t) => t.difference(t0).inMinutes.toDouble();
    final spots = [for (final p in points) FlSpot(x(p.ts), p.avgW / 1000)];
    final peak = points.reduce((a, b) => b.avgW > a.avgW ? b : a);
    final axis = niceAxis(peak.avgW / 1000 * 1.1);
    final span = x(points.last.ts);
    final sel = _sel;
    final bar = LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.15,
      preventCurveOverShooting: true,
      color: C.series,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, color: C.seriesWash),
      showingIndicators: sel == null ? const [] : [sel],
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ChartHeader(
        title: widget.title,
        value: sel == null ? null : fmtPowerText(points[sel].avgW),
        when: sel == null ? null : DateFormat('HH:mm').format(points[sel].ts),
        summary: peak.avgW > 0 ? 'Peak ${fmtPowerText(peak.avgW)} · ${DateFormat('HH:mm').format(peak.ts)}' : null,
        onClear: () => setState(() => _sel = null),
      ),
      SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: span,
            minY: 0,
            maxY: axis.max,
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
                  getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(_tick(v, axis.step), style: _axisStyle)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: 60,
                  getTitlesWidget: (v, meta) {
                    final t = t0.add(Duration(minutes: v.round()));
                    // label only round 6-hour marks
                    if (t.minute > 4 || t.hour % 6 != 0) return const SizedBox.shrink();
                    return SideTitleWidget(meta: meta, child: Text(DateFormat('HH:mm').format(t), style: _axisStyle));
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              // our own handling: no floating tooltip, and the pick stays
              handleBuiltInTouches: false,
              touchSpotThreshold: double.infinity,
              distanceCalculator: (touch, spot) => (touch.dx - spot.dx).abs(), // nearest in time
              touchCallback: (event, resp) {
                if (!event.isInterestedForInteractions) return;
                final hit = resp?.lineBarSpots;
                if (hit == null || hit.isEmpty) return;
                if (hit.first.spotIndex != _sel) setState(() => _sel = hit.first.spotIndex);
              },
              getTouchedSpotIndicator: (bar, idx) => [
                for (final _ in idx)
                  TouchedSpotIndicatorData(
                    const FlLine(color: C.text2, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 5,
                        color: C.brand,
                        strokeWidth: 2,
                        strokeColor: C.surface, // 2px surface ring
                      ),
                    ),
                  ),
              ],
            ),
            lineBarsData: [bar],
          ),
          duration: const Duration(milliseconds: 250),
        ),
      ),
    ]);
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
    final same = old.bucket == widget.bucket &&
        old.points.length == widget.points.length &&
        (widget.points.isEmpty || old.points.first.start == widget.points.first.start);
    if (!same) _sel = null;
  }

  String _label(DateTime t) => switch (widget.bucket) {
        Bucket.hour => DateFormat('HH').format(t),
        Bucket.day => widget.points.length <= 7 ? DateFormat('E').format(t) : DateFormat('d').format(t),
        Bucket.month => DateFormat('MMM').format(t),
      };

  String _peakLabel(DateTime t) => switch (widget.bucket) {
        Bucket.hour => DateFormat('HH:00').format(t),
        Bucket.day => DateFormat('EEE d').format(t),
        Bucket.month => DateFormat('MMM').format(t),
      };

  String _when(DateTime t) => switch (widget.bucket) {
        Bucket.hour => '${DateFormat('HH:00').format(t)}–${DateFormat('HH:00').format(t.add(const Duration(hours: 1)))}',
        Bucket.day => DateFormat('EEE d MMM').format(t),
        Bucket.month => DateFormat('MMM yyyy').format(t),
      };

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final maxY = points.isEmpty ? 0.0 : points.map((p) => p.kwh).reduce(max);
    final axis = niceAxis(maxY * 1.08);
    final peak = points.isEmpty ? null : points.reduce((a, b) => b.kwh > a.kwh ? b : a);
    final sel = _sel != null && _sel! < points.length ? _sel : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ChartHeader(
        title: widget.title,
        value: sel == null ? null : fmtKwh(points[sel].kwh),
        when: sel == null ? null : _when(points[sel].start),
        summary: peak != null && peak.kwh > 0 ? 'Peak ${_peakLabel(peak.start)} · ${fmtKwh(peak.kwh)}' : null,
        onClear: () => setState(() => _sel = null),
      ),
      LayoutBuilder(builder: (context, box) {
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
                    getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(_tick(v, axis.step), style: _axisStyle)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length || i % widget.labelEvery != 0) return const SizedBox.shrink();
                      return SideTitleWidget(meta: meta, child: Text(_label(points[i].start), style: _axisStyle));
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                // our own handling: no floating tooltip, and the pick stays;
                // the whole column (not just the bar) answers the finger
                handleBuiltInTouches: false,
                allowTouchBarBackDraw: true,
                touchExtraThreshold: EdgeInsets.symmetric(horizontal: slot / 2),
                touchCallback: (event, resp) {
                  if (!event.isInterestedForInteractions) return;
                  final i = resp?.spot?.touchedBarGroupIndex;
                  if (i != null && i != _sel) setState(() => _sel = i);
                },
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: points[i].kwh,
                      width: barW,
                      color: i == sel
                          ? C.brand
                          : sel != null
                              ? C.series.withValues(alpha: 0.55) // others step back while one is picked
                              : widget.highlight != null && points[i].start == widget.highlight
                                  ? C.brand
                                  : C.series,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]),
              ],
            ),
            duration: const Duration(milliseconds: 300),
          ),
        );
      }),
    ]);
  }
}
