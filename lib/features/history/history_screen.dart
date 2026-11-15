import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';
import 'usage_bars.dart';

enum Range { day, week, month, year }

typedef _Window = ({DateTime from, DateTime to, Bucket bucket, String title, String sub});

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  Range range = Range.week;
  int offset = 0; // 0 = current period, -1 = previous ...

  static final _d = DateFormat('d MMM');

  _Window _window(int offset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (range) {
      case Range.day:
        final d = today.add(Duration(days: offset));
        return (
          from: d,
          to: d.add(const Duration(days: 1)),
          bucket: Bucket.hour,
          title: offset == 0 ? 'Today' : offset == -1 ? 'Yesterday' : DateFormat('EEEE').format(d),
          sub: DateFormat('EEE d MMMM').format(d),
        );
      case Range.week:
        final end = today.add(Duration(days: 1 + 7 * offset));
        final start = end.subtract(const Duration(days: 7));
        return (
          from: start,
          to: end,
          bucket: Bucket.day,
          title: offset == 0 ? 'Last 7 days' : '${_d.format(start)} – ${_d.format(end.subtract(const Duration(days: 1)))}',
          sub: offset == 0 ? '${_d.format(start)} – ${_d.format(end.subtract(const Duration(days: 1)))}' : '7 days',
        );
      case Range.month:
        final m = DateTime(now.year, now.month + offset);
        return (
          from: m,
          to: DateTime(m.year, m.month + 1),
          bucket: Bucket.day,
          title: offset == 0 ? 'This month' : DateFormat('MMMM').format(m),
          sub: DateFormat('MMMM yyyy').format(m),
        );
      case Range.year:
        final y = now.year + offset;
        return (
          from: DateTime(y),
          to: DateTime(y + 1),
          bucket: Bucket.month,
          title: offset == 0 ? 'This year' : '$y',
          sub: 'Jan – Dec $y',
        );
    }
  }

  /// "vs yesterday", "vs week before" ...
  String get _versus => switch (range) {
        Range.day => offset == 0 ? 'yesterday' : 'day before',
        Range.week => 'week before',
        Range.month => 'month before',
        Range.year => 'year before',
      };

  /// Fill missing buckets with zero, so the axis always shows the whole
  /// period (future slots stay empty).
  List<EnergyPoint> _complete(List<EnergyPoint> pts, DateTime from, DateTime to, Bucket b) {
    final byStart = {for (final p in pts) p.start: p.kwh};
    final out = <EnergyPoint>[];
    var t = from;
    while (t.isBefore(to)) {
      out.add(EnergyPoint(t, byStart[t] ?? 0));
      t = switch (b) {
        Bucket.hour => t.add(const Duration(hours: 1)),
        Bucket.day => DateTime(t.year, t.month, t.day + 1),
        Bucket.month => DateTime(t.year, t.month + 1),
      };
    }
    return out;
  }

  void _go(int to) => setState(() => offset = to);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meter = ref.watch(currentMeterProvider).value;
    if (meter == null) {
      return const Scaffold(body: Center(child: Text('Add a meter to see its history.')));
    }
    final w = _window(offset);
    final q = (id: meter.id, from: w.from, to: w.to, bucket: w.bucket);
    final data = ref.watch(energyProvider(q));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
        children: [
          if (ref.watch(phoneOfflineProvider)) ...[
            OfflineNote(savedAt: ref.watch(savedAtProvider)),
            const SizedBox(height: S.md),
          ],
          SegmentedButton<Range>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: Range.day, label: Text('Day')),
              ButtonSegment(value: Range.week, label: Text('Week')),
              ButtonSegment(value: Range.month, label: Text('Month')),
              ButtonSegment(value: Range.year, label: Text('Year')),
            ],
            selected: {range},
            onSelectionChanged: (s) => setState(() {
              range = s.first;
              offset = 0;
            }),
          ),
          const SizedBox(height: S.lg),
          _PeriodBar(
            title: w.title,
            sub: w.sub,
            live: offset == 0,
            onPrev: () => _go(offset - 1),
            onNext: offset < 0 ? () => _go(offset + 1) : null,
          ),
          const SizedBox(height: S.lg),
          data.when(
            loading: () => const LoadingPanel(height: 420),
            error: (e, _) => ErrorPanel(message: 'Could not load the history.', onRetry: () => ref.invalidate(energyProvider)),
            data: (raw) {
              final pts = _complete(raw, w.from, w.to, w.bucket);
              final total = pts.fold<double>(0, (a, p) => a + p.kwh);
              final costs = ref.watch(costProvider(q)).value;
              final cost = costs == null ? null : pts.fold<double>(0, (a, p) => a + (costs[p.start] ?? 0));

              // the period before, up to the same point (today so far vs yesterday so far)
              final pw = _window(offset - 1);
              final prevRaw = ref.watch(energyProvider((id: meter.id, from: pw.from, to: pw.to, bucket: pw.bucket))).value;
              final shift = w.from.difference(pw.from);
              final prev = prevRaw
                  ?.where((p) => p.start.add(shift).isBefore(now))
                  .fold<double>(0, (a, p) => a + p.kwh);

              return _FadeIn(
                key: ValueKey('${range.name}$offset'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: _Figure(
                        icon: Icons.bolt_rounded,
                        color: C.brand,
                        label: 'Used',
                        value: total,
                        format: (v) => fmtKwh(v, unit: false),
                        unit: 'kWh',
                        sub: _delta(t, total, prev),
                      ),
                    ),
                    const SizedBox(width: S.md),
                    Expanded(
                      child: _Figure(
                        icon: Icons.payments_rounded,
                        color: C.money,
                        label: 'Cost',
                        value: cost,
                        format: (v) => fmtMoney(v, '').trim(),
                        unit: meter.currency,
                        sub: cost == null || total <= 0
                            ? null
                            : Text(
                                'Average ${fmtMoney(cost / total, '').trim()} ${meter.currency}/kWh',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.labelSmall?.copyWith(color: C.text2),
                              ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: S.md),
                  Panel(
                    padding: const EdgeInsets.fromLTRB(S.md, S.md, S.md, S.lg),
                    child: total == 0
                        ? SizedBox(
                            height: 240,
                            child: EmptyState(
                              icon: Icons.bar_chart_rounded,
                              title: 'Nothing recorded',
                              body: offset == 0
                                  ? 'Usage shows up here as your meter measures it.'
                                  : 'Your meter has no data for this period.',
                            ),
                          )
                        : UsageBars(
                            points: pts,
                            bucket: w.bucket,
                            now: now,
                            costs: costs == null ? null : [for (final p in pts) costs[p.start]],
                            currency: meter.currency,
                          ),
                  ),
                  if (total > 0) ..._highlights(t, pts, w.bucket, now),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget? _delta(TextTheme t, double total, double? prev) {
    if (prev == null || prev <= 0.05) return null;
    final f = (total - prev) / prev;
    // a huge % only means the period before had little data
    if (f > 3) {
      return Text(
        '${_versus[0].toUpperCase()}${_versus.substring(1)} ${fmtKwh(prev)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.labelSmall?.copyWith(color: C.text2),
      );
    }
    return DeltaText(fraction: f, versus: _versus);
  }

  /// Busiest, quietest and average slot of the period (only slots that have
  /// passed and have data count, so a meter that was off doesn't drag it down).
  List<Widget> _highlights(TextTheme t, List<EnergyPoint> pts, Bucket b, DateTime now) {
    final done = pts.where((p) => p.kwh > 0 && !p.start.isAfter(now)).toList();
    if (done.isEmpty) return const [];
    final busiest = done.reduce((a, c) => c.kwh > a.kwh ? c : a);
    final quietest = done.reduce((a, c) => c.kwh < a.kwh ? c : a);
    final avg = done.fold<double>(0, (a, p) => a + p.kwh) / done.length;
    final (unit, at) = switch (b) {
      Bucket.hour => ('hour', (DateTime d) => DateFormat('h a').format(d)),
      Bucket.day => ('day', (DateTime d) => DateFormat('EEE d').format(d)),
      Bucket.month => ('month', (DateTime d) => DateFormat('MMMM').format(d)),
    };
    return [
      const SectionHeader('Highlights'),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _Insight(
              icon: Icons.local_fire_department_rounded,
              color: C.serious,
              label: 'Busiest $unit',
              value: fmtKwh(busiest.kwh),
              when: at(busiest.start),
            ),
          ),
          const SizedBox(width: S.sm),
          Expanded(
            child: _Insight(
              icon: Icons.nightlight_round,
              color: C.money,
              label: 'Quietest $unit',
              value: fmtKwh(quietest.kwh),
              when: at(quietest.start),
            ),
          ),
          const SizedBox(width: S.sm),
          Expanded(
            child: _Insight(
              icon: Icons.insights_rounded,
              color: C.brand,
              label: 'Average $unit',
              value: fmtKwh(avg),
              // per hour, kWh and kW are the same number: say it as power too
              when: b == Bucket.hour ? 'about ${fmtPowerText(avg * 1000)}' : '${done.length} ${unit}s',
            ),
          ),
        ]),
      ),
    ];
  }
}

/// ‹  Today  ›  with the dates underneath and a pulse while it's the current period.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.title, required this.sub, required this.live, this.onPrev, this.onNext});
  final String title, sub;
  final bool live;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget arrow(IconData icon, String tip, VoidCallback? on) => IconButton.filledTonal(
          tooltip: tip,
          onPressed: on,
          style: IconButton.styleFrom(
            backgroundColor: C.surface,
            disabledBackgroundColor: C.surface.withValues(alpha: 0.4),
          ),
          icon: Icon(icon, color: on == null ? C.outline : C.text),
        );
    return Row(children: [
      arrow(Icons.chevron_left_rounded, 'Earlier', onPrev),
      Expanded(
        child: Column(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(title, key: ValueKey(title), style: t.titleMedium, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (live) ...[const PulseDot(color: C.brand), const SizedBox(width: 6)],
            Text(sub, style: t.labelSmall?.copyWith(color: live ? C.brand : C.text3)),
          ]),
        ]),
      ),
      arrow(Icons.chevron_right_rounded, 'Later', onNext),
    ]);
  }
}

/// Big number with a coloured badge; counts up when it changes.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.format,
    required this.unit,
    this.sub,
  });
  final IconData icon;
  final Color color;
  final String label;
  final double? value; // null while it loads
  final String Function(double) format;
  final String unit;
  final Widget? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Badge(icon: icon, color: color),
          const SizedBox(width: S.sm),
          Text(label, style: t.labelMedium?.copyWith(color: C.text2)),
        ]),
        const SizedBox(height: S.md),
        if (value == null)
          Text('—', style: t.headlineSmall?.copyWith(color: C.text3))
        else
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text.rich(
              TextSpan(children: [
                TextSpan(text: format(v), style: t.headlineSmall),
                TextSpan(text: ' $unit', style: t.bodyMedium?.copyWith(color: color)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: S.xs),
        SizedBox(height: 18, child: sub ?? const SizedBox.shrink()),
      ]),
    );
  }
}

class _Insight extends StatelessWidget {
  const _Insight({required this.icon, required this.color, required this.label, required this.value, required this.when});
  final IconData icon;
  final Color color;
  final String label, value, when;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(S.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Badge(icon: icon, color: color, size: 26),
        const SizedBox(height: S.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(label, style: t.labelSmall?.copyWith(color: C.text2)),
        ),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: t.titleSmall)),
        const SizedBox(height: 2),
        Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: color)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color, this.size = 28});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.6, color: color),
      );
}

/// Slides the period's content up into place when it changes.
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
        ),
        child: child,
      );
}
