// Charts, following the data-viz rules: one series in the chart teal,
// 2px lines with a 10 % wash, bars at most 24px wide with 4px rounded tops,
// hairline solid gridlines, clean round ticks, and a tooltip on touch.
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
const _tipStyle = TextStyle(fontFamily: 'Poppins', fontSize: 12, color: C.text, fontWeight: FontWeight.w600);
const _tipSub = TextStyle(fontFamily: 'Poppins', fontSize: 11, color: C.text2, fontWeight: FontWeight.w400);

FlGridData _grid(double step) => FlGridData(
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (_) => const FlLine(color: C.grid, strokeWidth: 1),
    );

/// Power over the last 24 h (5-minute averages), in kW.
class PowerAreaChart extends StatelessWidget {
  const PowerAreaChart({super.key, required this.points, this.height = 180});
  final List<PowerPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(child: Text('Not enough data yet', style: _axisStyle.copyWith(fontSize: 13))),
      );
    }
    final t0 = points.first.ts;
    double x(DateTime t) => t.difference(t0).inMinutes.toDouble();
    final spots = [for (final p in points) FlSpot(x(p.ts), p.avgW / 1000)];
    final maxY = points.map((p) => p.avgW / 1000).reduce(max);
    final axis = niceAxis(maxY * 1.1);
    final span = x(points.last.ts);

    return SizedBox(
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
            getTouchedSpotIndicator: (bar, idx) => [
              for (final _ in idx)
                TouchedSpotIndicatorData(
                  const FlLine(color: C.text3, strokeWidth: 1),
                  FlDotData(
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 4,
                      color: C.brand,
                      strokeWidth: 2,
                      strokeColor: C.surface, // 2px surface ring
                    ),
                  ),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => C.surface2,
              tooltipBorderRadius: BorderRadius.circular(R.sm),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${fmtPowerText(s.y * 1000)}\n',
                    _tipStyle,
                    children: [
                      TextSpan(text: DateFormat('HH:mm').format(t0.add(Duration(minutes: s.x.round()))), style: _tipSub),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.15,
              preventCurveOverShooting: true,
              color: C.series,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: C.seriesWash),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
      ),
    );
  }
}

/// kWh per hour / day / month as columns. Tap a column to see its value.
class EnergyBarChart extends StatelessWidget {
  const EnergyBarChart({
    super.key,
    required this.points,
    required this.bucket,
    this.height = 220,
    this.highlight,
    this.labelEvery = 1,
  });

  final List<EnergyPoint> points;
  final Bucket bucket;
  final double height;
  final DateTime? highlight; // e.g. today
  final int labelEvery;

  String _label(DateTime t) => switch (bucket) {
        Bucket.hour => DateFormat('HH').format(t),
        Bucket.day => points.length <= 7 ? DateFormat('E').format(t) : DateFormat('d').format(t),
        Bucket.month => DateFormat('MMM').format(t),
      };

  String _tipTitle(DateTime t) => switch (bucket) {
        Bucket.hour => '${DateFormat('HH:00').format(t)} – ${DateFormat('HH:00').format(t.add(const Duration(hours: 1)))}',
        Bucket.day => DateFormat('EEE d MMM').format(t),
        Bucket.month => DateFormat('MMMM yyyy').format(t),
      };

  @override
  Widget build(BuildContext context) {
    final maxY = points.isEmpty ? 0.0 : points.map((p) => p.kwh).reduce(max);
    final axis = niceAxis(maxY * 1.08);
    return LayoutBuilder(builder: (context, box) {
      final slot = (box.maxWidth - 40) / max(points.length, 1);
      final barW = min(24.0, max(3.0, slot * 0.62));
      return SizedBox(
        height: height,
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
                    if (i < 0 || i >= points.length || i % labelEvery != 0) return const SizedBox.shrink();
                    return SideTitleWidget(meta: meta, child: Text(_label(points[i].start), style: _axisStyle));
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => C.surface2,
                tooltipBorderRadius: BorderRadius.circular(R.sm),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${fmtKwh(rod.toY)}\n',
                  _tipStyle,
                  children: [TextSpan(text: _tipTitle(points[group.x].start), style: _tipSub)],
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: points[i].kwh,
                    width: barW,
                    color: highlight != null && points[i].start == highlight ? C.brand : C.series,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]),
            ],
          ),
          duration: const Duration(milliseconds: 300),
        ),
      );
    });
  }
}
