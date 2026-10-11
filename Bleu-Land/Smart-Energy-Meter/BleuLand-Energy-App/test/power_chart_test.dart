import 'package:bleuland_energy/data/models.dart';
import 'package:bleuland_energy/widgets/charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fox's real readings of 10-11 Oct (gaps included), newest first as the
/// cloud sends them. The chart once said "Not enough data yet" for them.
void main() {
  testWidgets('power chart: today hour by hour, AM half labelled 1-12', (t) async {
    final raw = [
      ('2026-10-10T08:15:00Z', 0.0),
      ('2026-10-10T08:20:00Z', 0.0),
      ('2026-10-10T08:25:00Z', 0.0),
      ('2026-10-10T08:30:00Z', 0.0),
      ('2026-10-10T08:35:00Z', 0.0),
      ('2026-10-10T08:40:00Z', 0.0),
      ('2026-10-10T08:45:00Z', 0.0),
      ('2026-10-10T08:50:00Z', 0.0),
      ('2026-10-10T08:55:00Z', 0.0),
      ('2026-10-10T09:00:00Z', 0.0),
      ('2026-10-10T09:05:00Z', 0.0),
      ('2026-10-10T09:10:00Z', 0.0),
      ('2026-10-10T09:15:00Z', 0.0),
      ('2026-10-10T09:20:00Z', 0.0),
      ('2026-10-10T09:25:00Z', 0.0),
      ('2026-10-10T09:30:00Z', 0.0),
      ('2026-10-10T09:35:00Z', 0.0),
      ('2026-10-10T09:40:00Z', 0.0),
      ('2026-10-10T09:45:00Z', 0.0),
      ('2026-10-10T09:50:00Z', 0.0),
      ('2026-10-10T09:55:00Z', 0.0),
      ('2026-10-10T10:00:00Z', 0.0),
      ('2026-10-10T10:05:00Z', 0.0),
      ('2026-10-10T10:10:00Z', 0.0),
      ('2026-10-10T10:15:00Z', 0.0),
      ('2026-10-10T10:20:00Z', 0.0),
      ('2026-10-10T10:25:00Z', 0.0),
      ('2026-10-10T10:30:00Z', 0.0),
      ('2026-10-10T10:35:00Z', 0.0),
      ('2026-10-10T10:40:00Z', 0.0),
      ('2026-10-10T10:45:00Z', 0.0),
      ('2026-10-10T10:50:00Z', 0.0),
      ('2026-10-10T10:55:00Z', 0.0),
      ('2026-10-10T11:00:00Z', 0.0),
      ('2026-10-10T11:05:00Z', 0.0),
      ('2026-10-10T11:10:00Z', 0.0),
      ('2026-10-10T11:15:00Z', 0.0),
      ('2026-10-10T11:20:00Z', 0.0),
      ('2026-10-10T11:25:00Z', 0.0),
      ('2026-10-10T11:30:00Z', 0.0),
      ('2026-10-10T11:35:00Z', 0.0),
      ('2026-10-10T11:40:00Z', 0.0),
      ('2026-10-10T11:45:00Z', 0.0),
      ('2026-10-10T11:50:00Z', 0.0),
      ('2026-10-10T11:55:00Z', 0.0),
      ('2026-10-10T14:15:00Z', 0.0),
      ('2026-10-10T14:20:00Z', 0.0),
      ('2026-10-10T14:25:00Z', 0.0),
      ('2026-10-11T05:35:00Z', 60.0),
      ('2026-10-11T05:40:00Z', 60.0),
      ('2026-10-11T05:45:00Z', 60.0),
      ('2026-10-11T05:50:00Z', 60.0),
      ('2026-10-11T05:55:00Z', 60.0),
      ('2026-10-11T06:00:00Z', 660),
      ('2026-10-11T06:05:00Z', 4561),
      ('2026-10-11T06:10:00Z', 60.0),
      ('2026-10-11T06:15:00Z', 885),
      ('2026-10-11T06:20:00Z', 60.0),
      ('2026-10-11T06:25:00Z', 60.0),
      ('2026-10-11T06:30:00Z', 60.0),
      ('2026-10-11T06:35:00Z', 60.0),
      ('2026-10-11T06:40:00Z', 60.0),
      ('2026-10-11T06:45:00Z', 60.0),
      ('2026-10-11T06:50:00Z', 60.0),
      ('2026-10-11T06:55:00Z', 60.0),
      ('2026-10-11T07:00:00Z', 60.0),
      ('2026-10-11T07:05:00Z', 60.0),
      ('2026-10-11T07:10:00Z', 7939),
      ('2026-10-11T07:15:00Z', 60.0),
      ('2026-10-11T07:20:00Z', 5720),
      ('2026-10-11T07:25:00Z', 60.0),
      ('2026-10-11T07:30:00Z', 60.0),
      ('2026-10-11T07:35:00Z', 60.0),
      ('2026-10-11T07:40:00Z', 923),
      ('2026-10-11T07:45:00Z', 3582),
      ('2026-10-11T07:50:00Z', 60.0),
    ];
    final pts = [for (final r in raw.reversed) PowerPoint(DateTime.parse(r.$1).toLocal(), r.$2.toDouble(), 130)];
    final now = DateTime.parse('2026-10-11T07:55:00Z').toLocal();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PowerAreaChart(points: pts, now: now))));
    await t.pumpAndSettle();
    // 10:55 local: opens on the morning; readings from 8:35 on
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('No readings this morning'), findsNothing);
    for (final h in ['1', '6', '12']) {
      expect(find.text(h), findsOneWidget);
    }
    // the afternoon is one swipe / arrow away and hasn't started yet
    await t.tap(find.byIcon(Icons.chevron_right_rounded));
    await t.pumpAndSettle();
    expect(find.text('PM'), findsOneWidget);
    expect(find.text("The afternoon hasn't started yet"), findsOneWidget);
  });

  testWidgets('power chart: nothing recorded this morning', (t) async {
    final now = DateTime(2026, 10, 11, 9, 30);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PowerAreaChart(points: const [], now: now))));
    expect(find.text('No readings this morning'), findsOneWidget);
  });
}
