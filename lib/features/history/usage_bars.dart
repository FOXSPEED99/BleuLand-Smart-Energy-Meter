import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// Energy per hour / day / month as bars, each with its own name underneath
/// (no value axis: the busiest bar and the one you tap carry their number).
/// Bars grow in when the period changes; the bar happening now pulses.
class UsageBars extends StatefulWidget {
  const UsageBars({
    super.key,
    required this.points,
    required this.bucket,
    required this.now,
    this.costs,
    this.currency = 'SYP',
    this.barsHeight = 150,
  });

  final List<EnergyPoint> points; // one per slot, in order, the whole period
  final Bucket bucket;
  final DateTime now;
  final List<double?>? costs; // what each bar added to the bill
  final String currency;
  final double barsHeight; // the tallest bar

  @override
  State<UsageBars> createState() => _UsageBarsState();
}

class _UsageBarsState extends State<UsageBars> with SingleTickerProviderStateMixin {
  // narrower than this, the chart scrolls (a day's 24 hours always fit)
  double get _minSlot => widget.bucket == Bucket.hour ? 11.0 : 18.0;
  static const _valueRow = 20.0;

  int? _sel;
  late final _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))..forward();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNow());
  }

  @override
  void didUpdateWidget(UsageBars old) {
    super.didUpdateWidget(old);
    final same = old.bucket == widget.bucket &&
        old.points.length == widget.points.length &&
        (widget.points.isEmpty || old.points.first.start == widget.points.first.start);
    if (!same) {
      // another period: start without a pick, and grow the new bars in
      _sel = null;
      _grow.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNow());
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int? get _nowIndex {
    final i = widget.points.indexWhere((p) => p.start == _slotOf(widget.now));
    return i < 0 ? null : i;
  }

  DateTime _slotOf(DateTime t) => switch (widget.bucket) {
        Bucket.hour => DateTime(t.year, t.month, t.day, t.hour),
        Bucket.day => DateTime(t.year, t.month, t.day),
        Bucket.month => DateTime(t.year, t.month),
      };

  /// A wide (scrolling) chart opens with "now" in view, else at the start.
  void _showNow() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final i = _nowIndex;
    if (i == null) {
      _scroll.jumpTo(0);
      return;
    }
    final slot = (pos.maxScrollExtent + pos.viewportDimension) / widget.points.length;
    _scroll.jumpTo(((i + 3) * slot - pos.viewportDimension).clamp(0.0, pos.maxScrollExtent));
  }

  void _pick(double dx, double slot) {
    final i = (dx / slot).floor().clamp(0, widget.points.length - 1);
    if (i != _sel) setState(() => _sel = i);
  }

  // ------------------------------------------------------------ names

  String _name(DateTime t) => switch (widget.bucket) {
        Bucket.hour => DateFormat('h').format(t),
        Bucket.day => widget.points.length <= 7 ? DateFormat('E').format(t) : DateFormat('d').format(t),
        Bucket.month => DateFormat('MMM').format(t),
      };

  String? _subName(DateTime t) =>
      widget.bucket == Bucket.day && widget.points.length <= 7 ? DateFormat('d').format(t) : null;

  String _when(DateTime t) => switch (widget.bucket) {
        Bucket.hour => () {
            final end = t.add(const Duration(hours: 1));
            final a = DateFormat('a').format(t), b = DateFormat('a').format(end);
            return a == b
                ? '${DateFormat('h').format(t)}–${DateFormat('h a').format(end)}'
                : '${DateFormat('h a').format(t)}–${DateFormat('h a').format(end)}';
          }(),
        Bucket.day => DateFormat('EEE d MMM').format(t),
        Bucket.month => DateFormat('MMMM yyyy').format(t),
      };

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final sel = _sel != null && _sel! < pts.length ? _sel : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(context, sel),
      const SizedBox(height: S.md),
      LayoutBuilder(builder: (context, box) {
        final fits = box.maxWidth / max(pts.length, 1) >= _minSlot;
        final slot = fits ? box.maxWidth / max(pts.length, 1) : _minSlot;
        final chart = SizedBox(
          width: slot * pts.length,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition.dx, slot),
            // sliding picks too, unless sliding scrolls the chart
            onHorizontalDragStart: fits ? (d) => _pick(d.localPosition.dx, slot) : null,
            onHorizontalDragUpdate: fits ? (d) => _pick(d.localPosition.dx, slot) : null,
            child: AnimatedBuilder(
              animation: _grow,
              builder: (context, _) => _bars(context, slot, sel),
            ),
          ),
        );
        return fits
            ? chart
            : SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal, child: chart);
      }),
    ]);
  }

  Widget _header(BuildContext context, int? sel) {
    final t = Theme.of(context).textTheme;
    final pts = widget.points;
    final title = switch (widget.bucket) {
      Bucket.hour => 'Every hour',
      Bucket.day => 'Every day',
      Bucket.month => 'Every month',
    };
    final cost = sel == null ? null : widget.costs?[sel];
    return SizedBox(
      height: 36,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: sel == null
            ? Row(key: const ValueKey('title'), children: [
                const Icon(Icons.bar_chart_rounded, size: 18, color: C.brand),
                const SizedBox(width: 6),
                Text(title, style: t.titleSmall),
                const Spacer(),
                const Icon(Icons.touch_app_outlined, size: 14, color: C.text3),
                const SizedBox(width: 4),
                Text('Tap a bar', style: t.labelSmall?.copyWith(color: C.text3)),
              ])
            : Container(
                key: const ValueKey('picked'),
                decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(99)),
                child: Row(children: [
                  _step(Icons.chevron_left_rounded, sel > 0 ? () => setState(() => _sel = sel - 1) : null),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_when(pts[sel].start), style: t.labelMedium?.copyWith(color: C.text2)),
                        const SizedBox(width: 8),
                        Text(
                          fmtKwh(pts[sel].kwh),
                          style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        if (cost != null && pts[sel].kwh > 0) ...[
                          Text('  ·  ', style: t.labelMedium?.copyWith(color: C.text3)),
                          Text(fmtMoney(cost, widget.currency), style: t.labelLarge?.copyWith(color: C.money)),
                        ],
                      ]),
                    ),
                  ),
                  _step(
                    Icons.chevron_right_rounded,
                    sel < pts.length - 1 ? () => setState(() => _sel = sel + 1) : null,
                  ),
                  Container(width: 1, height: 18, color: C.outline),
                  SizedBox(
                    width: 40,
                    height: 36,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: 'Clear',
                      onPressed: () => setState(() => _sel = null),
                      icon: const Icon(Icons.close_rounded, color: C.text3),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback? onTap) => SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          onPressed: onTap,
          icon: Icon(icon, color: onTap == null ? C.outline : C.text2),
        ),
      );

  Widget _bars(BuildContext context, double slot, int? sel) {
    final t = Theme.of(context).textTheme;
    final pts = widget.points;
    final top = pts.isEmpty ? 0.0 : pts.map((p) => p.kwh).reduce(max);
    final peak = top > 0 ? pts.indexWhere((p) => p.kwh == top) : -1;
    final nowI = _nowIndex;
    final grow = Curves.easeOutCubic.transform(_grow.value);
    final barW = min(22.0, max(4.0, slot * 0.58));
    final small = slot < 16 ? 9.5 : 10.5;
    final nameStyle = t.labelSmall?.copyWith(fontSize: small, color: C.text3, letterSpacing: 0);

    Widget column(int i) {
      final p = pts[i];
      final future = p.start.isAfter(widget.now);
      final isNow = i == nowI;
      final picked = i == sel;
      final color = picked || (sel == null && isNow)
          ? C.brand
          : sel != null
              ? C.series.withValues(alpha: 0.45) // the others step back while one is picked
              : C.series;
      final h = top <= 0 ? 0.0 : widget.barsHeight * (p.kwh / top) * grow;
      // above the bar: its number when picked or the busiest, else a pulse for "now"
      final Widget above = picked || (sel == null && i == peak)
          ? OverflowBox(
              maxWidth: 80,
              child: Text(
                fmtKwh(p.kwh, unit: false),
                maxLines: 1,
                style: t.labelSmall?.copyWith(
                  fontSize: 10.5,
                  color: picked ? C.brand : C.text2,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            )
          : isNow
              ? const PulseDot(color: C.brand)
              : const SizedBox.shrink();
      final sub = _subName(p.start);
      final strong = isNow || picked;
      return SizedBox(
        width: slot,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: widget.barsHeight + _valueRow,
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              SizedBox(height: _valueRow - 4, child: Center(child: Opacity(opacity: grow, child: above))),
              const SizedBox(height: 4),
              if (p.kwh > 0 && h >= 2)
                Container(
                  width: barW,
                  height: h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(min(6.0, barW / 2))),
                  ),
                )
              else
                // nothing used (or still to come): a dot keeps the slot visible
                Container(
                  width: min(barW, 5),
                  height: min(barW, 5),
                  decoration: BoxDecoration(
                    color: future ? C.grid : C.outline,
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            _name(p.start),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: nameStyle?.copyWith(
              color: strong ? (picked ? C.text : C.brand) : (future ? C.outline : (sub != null ? C.text2 : C.text3)),
              fontWeight: strong ? FontWeight.w600 : null,
            ),
          ),
          if (sub != null)
            Text(sub, style: nameStyle?.copyWith(color: strong ? C.text : C.text3)),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        // the floor the bars stand on
        Positioned(
          left: 0,
          right: 0,
          top: widget.barsHeight + _valueRow,
          child: Container(height: 1, color: C.grid),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < pts.length; i++) column(i)]),
      ]),
      if (widget.bucket == Bucket.hour && pts.length == 24) ...[
        const SizedBox(height: 6),
        Row(children: [
          for (final half in const ['AM', 'PM'])
            SizedBox(width: slot * 12, child: _Bracket(label: half, style: nameStyle)),
        ]),
      ],
    ]);
  }
}

/// "└──── AM ────┘" under twelve hours.
class _Bracket extends StatelessWidget {
  const _Bracket({required this.label, this.style});
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    Widget line(bool left) => Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(left: left ? 4 : 6, right: left ? 6 : 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide.none,
                bottom: const BorderSide(color: C.outline),
                left: left ? const BorderSide(color: C.outline) : BorderSide.none,
                right: left ? BorderSide.none : const BorderSide(color: C.outline),
              ),
            ),
          ),
        );
    return Row(children: [
      line(true),
      Text(label, style: style?.copyWith(color: C.text2, fontWeight: FontWeight.w600)),
      line(false),
    ]);
  }
}
