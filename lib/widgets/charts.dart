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
/// records), as one soft line across the whole day. 12 hours show at a time:
/// glide the chart (it settles on the morning or the afternoon) or use
/// ‹ AM › in the title row. Hours are labelled by the hour they end on,
/// 1 … 12, like a clock face; the single bubble spells it out ("1.2 kW ·
/// 8–9 AM"). It sits on the busiest hour of the half in view until you tap
/// another hour (tap it again to go back).
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

// Room around the 12 hours in view: the clock icon left of the 1, and the
// glow of the first / last hour.
const _padL = 1.55, _padR = 0.65;
const _labelRow = 26.0; // height of the hour-label row

final _softGrid = FlLine(color: C.grid.withValues(alpha: 0.6), strokeWidth: 1);

class _PowerAreaChartState extends State<PowerAreaChart> {
  final _scroll = ScrollController();
  int _half = 0; // 0 = AM, 1 = PM
  bool _placed = false; // the starting half has been chosen
  int? _picked; // hour of today, 0..23

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scroll.position;
    if (!p.hasContentDimensions || p.maxScrollExtent <= 0) return;
    final half = p.pixels > p.maxScrollExtent / 2 ? 1 : 0;
    if (half != _half) {
      setState(() {
        _half = half;
        _picked = null; // the bubble moves to the busiest hour in view
      });
    }
  }

  void _show(int half) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      half == 0 ? 0 : _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hours = _hours();
    if (!_placed) {
      // open on the half "now" is in, unless it's still empty and the
      // other one isn't (just after noon, the morning is the news)
      _placed = true;
      bool any(int half) =>
          hours.sublist(half * 12, half * 12 + 12).any((w) => w != null);
      final current = _now.hour < 12 ? 0 : 1;
      _half = !any(current) && any(1 - current) ? 1 - current : current;
      if (_half == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: S.sm, bottom: S.sm),
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                Text(
                  'Average per hour',
                  style: t.labelMedium?.copyWith(color: C.text2),
                ),
                const Spacer(),
                _HalfSwitch(half: _half, onChanged: _show),
              ],
            ),
          ),
        ),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final view = box.maxWidth;
              final unit = view / (11 + _padL + _padR); // px per hour
              return SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const _HalfSnap(),
                child: SizedBox(
                  width: (23 + _padL + _padR) * unit,
                  height: widget.height,
                  child: _dayChart(hours, unit, view),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayChart(List<double?> hours, double unit, double view) {
    final now = _now;
    final day = DateTime(now.year, now.month, now.day);
    final values = hours.whereType<double>();
    final top = values.isEmpty ? 0.0 : values.reduce(max);
    final scale = top >= 1000 ? 1000.0 : 1.0;
    final maxY = max(top / scale, 1e-6) * 1.55; // room above for the bubble
    // square cells: the levels are as far apart as the hours
    final levelStep = maxY * unit / max(widget.height - _labelRow, 1);

    int? busiest(int half) {
      int? best;
      for (var h = half * 12; h < half * 12 + 12; h++) {
        if (hours[h] != null && (best == null || hours[h]! > hours[best]!)) {
          best = h;
        }
      }
      return best;
    }

    final mark = _picked ?? busiest(_half);
    bool alone(int i) =>
        (i == 0 || hours[i - 1] == null) && (i == 23 || hours[i + 1] == null);

    final bar = LineChartBarData(
      spots: [
        for (var i = 0; i < 24; i++)
          hours[i] == null
              ? FlSpot.nullSpot
              : FlSpot(i.toDouble(), hours[i]! / scale),
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
            alone(spot.x.round()) && hours[spot.x.round()]! >= 1,
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
      showingIndicators: [?mark],
    );

    // keep the bubble inside the 12 hours in view
    final local = mark == null ? 6 : mark - _half * 12;
    final align = local <= 0
        ? FLHorizontalAlignment.right
        : local >= 10
        ? FLHorizontalAlignment.left
        : FLHorizontalAlignment.center;

    final chart = LineChart(
      LineChartData(
        minX: -_padL,
        maxX: 23 + _padR,
        minY: 0,
        maxY: maxY,
        // a faint grid of squares (a column per hour), no numbers: the
        // bubble gives the value
        gridData: FlGridData(
          horizontalInterval: levelStep,
          verticalInterval: 1,
          checkToShowVerticalLine: (v) => v > -0.5,
          getDrawingHorizontalLine: (_) => _softGrid,
          getDrawingVerticalLine: (_) => _softGrid,
        ),
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
              reservedSize: _labelRow,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < -1 || i > 23) {
                  return const SizedBox.shrink();
                }
                if (i == -1) {
                  // a small clock before the 1 … 12: these are hours
                  return SideTitleWidget(
                    meta: meta,
                    child: const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: C.text3,
                    ),
                  );
                }
                final current = i == now.hour;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${i % 12 + 1}',
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
          if (mark != null)
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
            if (hours[i] == null) return;
            setState(() => _picked = _picked == i ? null : i);
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
            tooltipHorizontalAlignment: align,
            tooltipHorizontalOffset: align == FLHorizontalAlignment.left
                ? 10
                : align == FLHorizontalAlignment.right
                ? -10
                : 0,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final _ in spots)
                LineTooltipItem(
                  '${fmtPowerText(hours[mark!]!)}\n',
                  const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: C.text,
                  ),
                  children: [
                    TextSpan(
                      text: _hourRange(
                        DateTime(day.year, day.month, day.day, mark),
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

    // a half with nothing in it says so, in the middle of its 12 hours
    String? emptyText(int half) {
      if (busiest(half) != null) return null;
      final part = half == 0 ? 'morning' : 'afternoon';
      final nowHalf = now.hour < 12 ? 0 : 1;
      if (half > nowHalf) return 'The afternoon hasn\'t started yet';
      return half == nowHalf ? 'Nothing yet this $part' : 'No readings this $part';
    }

    return Stack(
      children: [
        chart,
        for (final half in const [0, 1])
          if (emptyText(half) != null)
            Positioned(
              left: half * 12 * unit,
              width: view,
              top: 0,
              bottom: _labelRow,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    emptyText(half)!,
                    style: _axisStyle.copyWith(fontSize: 13),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Settles on the morning or the afternoon after a glide (or a flick).
class _HalfSnap extends ScrollPhysics {
  const _HalfSnap({super.parent});

  @override
  _HalfSnap applyTo(ScrollPhysics? ancestor) =>
      _HalfSnap(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final lo = position.minScrollExtent, hi = position.maxScrollExtent;
    final target = velocity.abs() > 250
        ? (velocity > 0 ? hi : lo)
        : (position.pixels > (lo + hi) / 2 ? hi : lo);
    if ((target - position.pixels).abs() < 0.5) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
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
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: enabled ? () => onChanged(to) : null,
        icon: Icon(
          icon,
          color: enabled ? C.text : C.text3.withValues(alpha: 0.35),
        ),
      ),
    );
    return Container(
      height: 28,
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
              width: 24,
              child: Text(
                half == 0 ? 'AM' : 'PM',
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(
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

/// A tiny live signal: a soft wave gliding by in a loop, so the Home screen
/// feels alive. Pauses on its own when the screen isn't shown.
class LiveWave extends StatefulWidget {
  const LiveWave({super.key, this.width = 34, this.height = 18});
  final double width, height;

  @override
  State<LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<LiveWave>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _WavePainter(_anim),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t.value * 2 * pi;
    final mid = size.height / 2;
    final path = Path();
    for (var x = 0.0; x <= size.width; x += 1) {
      final k = x / size.width * 2 * pi;
      // two waves together: a calm swell with a small ripple on top
      final y =
          mid -
          sin(k * 1.5 - phase) * size.height * 0.28 -
          sin(k * 4 - phase * 2) * size.height * 0.08;
      x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fade = LinearGradient(
      colors: [
        _powerLine.withValues(alpha: 0),
        _powerLine,
        _powerLine,
        _powerLine.withValues(alpha: 0),
      ],
      stops: const [0, 0.25, 0.75, 1],
    ).createShader(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = fade
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
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
