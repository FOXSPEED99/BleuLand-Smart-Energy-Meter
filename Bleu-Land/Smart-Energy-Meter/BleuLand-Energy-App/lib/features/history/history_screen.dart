import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts.dart';
import '../../widgets/ui.dart';

enum Range { day, week, month, year }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  Range range = Range.week;
  int offset = 0; // 0 = current period, -1 = previous ...

  ({DateTime from, DateTime to, Bucket bucket, String title}) _window() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (range) {
      case Range.day:
        final d = today.add(Duration(days: offset));
        return (
          from: d,
          to: d.add(const Duration(days: 1)),
          bucket: Bucket.hour,
          title: offset == 0 ? 'Today' : offset == -1 ? 'Yesterday' : DateFormat('EEE d MMM').format(d),
        );
      case Range.week:
        final end = today.add(Duration(days: 1 + 7 * offset));
        final start = end.subtract(const Duration(days: 7));
        return (
          from: start,
          to: end,
          bucket: Bucket.day,
          title: offset == 0
              ? 'Last 7 days'
              : '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end.subtract(const Duration(days: 1)))}',
        );
      case Range.month:
        final m = DateTime(now.year, now.month + offset);
        return (
          from: m,
          to: DateTime(m.year, m.month + 1),
          bucket: Bucket.day,
          title: DateFormat('MMMM yyyy').format(m),
        );
      case Range.year:
        final y = now.year + offset;
        return (from: DateTime(y), to: DateTime(y + 1), bucket: Bucket.month, title: '$y');
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meter = ref.watch(currentMeterProvider).value;
    if (meter == null) {
      return const Scaffold(body: Center(child: Text('Add a meter to see its history.')));
    }
    final w = _window();
    final data = ref.watch(energyProvider((id: meter.id, from: w.from, to: w.to, bucket: w.bucket)));
    final now = DateTime.now();
    final highlight = switch (w.bucket) {
      Bucket.hour => DateTime(now.year, now.month, now.day, now.hour),
      Bucket.day => DateTime(now.year, now.month, now.day),
      Bucket.month => DateTime(now.year, now.month),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
        children: [
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
          Row(children: [
            IconButton(
              tooltip: 'Earlier',
              onPressed: () => setState(() => offset--),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(child: Text(w.title, textAlign: TextAlign.center, style: t.titleMedium)),
            IconButton(
              tooltip: 'Later',
              onPressed: offset < 0 ? () => setState(() => offset++) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          const SizedBox(height: S.sm),
          data.when(
            loading: () => const LoadingPanel(height: 360),
            error: (e, _) => ErrorPanel(message: 'Could not load the history.', onRetry: () => ref.invalidate(energyProvider)),
            data: (raw) {
              final pts = _complete(raw, w.from, w.to, w.bucket);
              final total = pts.fold<double>(0, (a, p) => a + p.kwh);
              final peak = pts.isEmpty ? null : pts.reduce((a, b) => a.kwh >= b.kwh ? a : b);
              // averages only count time that has already passed
              final end = w.to.isAfter(now) ? now : w.to;
              final elapsedH = end.difference(w.from).inMinutes / 60;
              final perUnit = w.bucket == Bucket.hour
                  ? total / (elapsedH < 1 ? 1 : elapsedH)
                  : total / (elapsedH < 24 ? 1 : elapsedH / 24);
              final peakLabel = peak == null
                  ? '–'
                  : switch (w.bucket) {
                      Bucket.hour => DateFormat('HH:00').format(peak.start),
                      Bucket.day => DateFormat('EEE d').format(peak.start),
                      Bucket.month => DateFormat('MMM').format(peak.start),
                    };
              return Column(children: [
                Row(children: [
                  Expanded(child: StatTile(label: 'Total', value: fmtKwh(total, unit: false), unit: 'kWh')),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: StatTile(
                      label: w.bucket == Bucket.hour ? 'Per hour' : 'Per day',
                      value: fmtKwh(perUnit, unit: false),
                      unit: 'kWh',
                    ),
                  ),
                ]),
                const SizedBox(height: S.md),
                Panel(
                  padding: const EdgeInsets.fromLTRB(S.sm, S.lg, S.lg, S.sm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(left: S.sm, bottom: S.md),
                      child: Row(children: [
                        Text(
                          switch (w.bucket) {
                            Bucket.hour => 'Energy per hour, kWh',
                            Bucket.day => 'Energy per day, kWh',
                            Bucket.month => 'Energy per month, kWh',
                          },
                          style: t.labelMedium?.copyWith(color: C.text2),
                        ),
                        const Spacer(),
                        if (peak != null && peak.kwh > 0)
                          Text('Peak $peakLabel · ${fmtKwh(peak.kwh)}', style: t.labelSmall?.copyWith(color: C.text3)),
                      ]),
                    ),
                    if (total == 0)
                      SizedBox(
                        height: 220,
                        child: Center(child: Text('No data for this period', style: t.bodyMedium?.copyWith(color: C.text3))),
                      )
                    else
                      EnergyBarChart(
                        points: pts,
                        bucket: w.bucket,
                        highlight: offset == 0 ? highlight : null,
                        labelEvery: switch (w.bucket) {
                          Bucket.hour => 3,
                          Bucket.day => pts.length > 10 ? 5 : 1,
                          Bucket.month => 1,
                        },
                      ),
                  ]),
                ),
                const SizedBox(height: S.md),
                Text(
                  'Tap a bar to see its value. Times are in the meter\'s time zone.',
                  style: t.labelSmall?.copyWith(color: C.text3),
                  textAlign: TextAlign.center,
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
