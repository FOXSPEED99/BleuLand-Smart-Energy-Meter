import 'dart:async';
import 'dart:math';

import '../core/tariff.dart';
import 'models.dart';
import 'repository.dart';

/// A simulated Syrian home, so the app can be tried without a meter (and
/// reviewed by app stores). Averages ~5.5 kWh/day: morning and evening peaks,
/// more use in summer (fans/AC) and winter (heaters), and two scheduled
/// 2-hour power cuts a day (التقنين) during which consumption is zero.
class DemoRepository implements EnergyRepository {
  DemoRepository();

  @override
  bool get isDemo => true;

  Meter _meter = const Meter(
    id: 'SEM1-DE0001',
    name: 'Demo home',
    role: 'owner',
    fw: '0.1.0',
    alertPowerW: 2500,
  );
  final List<Invite> _invites = [];

  // ---------------------------------------------------------------- model

  static double _hash(int n) {
    // deterministic 0..1 noise per integer (same history every time)
    var x = (n * 0x9E3779B1) & 0xFFFFFFFF;
    x ^= x >> 15;
    x = (x * 0x85EBCA77) & 0xFFFFFFFF;
    x ^= x >> 13;
    return (x & 0xFFFFFF) / 0xFFFFFF;
  }

  static int _dayIndex(DateTime t) => DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;

  /// Scheduled cuts: two 2-hour blocks a day, rotating like real schedules.
  static bool _gridOff(DateTime t) {
    final d = _dayIndex(t);
    final a = 7 + (d * 5) % 6; // first cut starts between 07:00 and 12:00
    final b = a + 10;
    return (t.hour >= a && t.hour < a + 2) || (t.hour >= b && t.hour < b + 2);
  }

  static double _season(DateTime t) {
    const f = [1.45, 1.4, 1.15, 0.95, 1.0, 1.2, 1.35, 1.4, 1.2, 1.0, 1.1, 1.35];
    return f[t.month - 1];
  }

  /// Average household power for the hour containing [t], in watts.
  static double _hourWatts(DateTime t) {
    if (_gridOff(t)) return 0;
    const profile = [
      95, 85, 80, 80, 85, 110, 260, 380, 300, 210, 190, 200, //
      230, 240, 210, 190, 210, 300, 420, 470, 440, 380, 260, 150,
    ];
    final day = 0.82 + 0.36 * _hash(_dayIndex(t)); // some days use more
    final jitter = 0.85 + 0.3 * _hash(_dayIndex(t) * 24 + t.hour);
    return profile[t.hour] * _season(t) * day * jitter;
  }

  // ---------------------------------------------------------------- API

  @override
  Future<List<Meter>> meters() async => [_meter];

  /// Mains voltage: Syrian grids sag in the evening peak and run high late at night.
  static double _baseVolts(DateTime t) {
    final h = t.hour + t.minute / 60;
    return 216 + 7 * cos((h - 3) / 24 * 2 * pi) - (h >= 18 && h < 22 ? 9 : 0);
  }

  @override
  Stream<LiveReading?> live(String meterId) async* {
    final rnd = Random();
    var w = _hourWatts(DateTime.now());
    double total = 1284.6;
    final start = DateTime.now();
    // today so far: plausible lowest/highest before the app was opened
    var vMin = min(_baseVolts(start) - 4, 203.4);
    var vMax = max(_baseVolts(start) + 3, 224.8);
    DateTime? vMinAt = DateTime(start.year, start.month, start.day, min(start.hour, 19), 42);
    DateTime? vMaxAt = DateTime(start.year, start.month, start.day, min(start.hour, 3), 15);
    if (vMinAt.isAfter(start)) vMinAt = start;
    if (vMaxAt.isAfter(start)) vMaxAt = start;
    while (true) {
      final now = DateTime.now();
      final target = _hourWatts(now);
      // wander around the hour's average, with the odd appliance switching on
      w = target == 0 ? 0 : (w * 0.7 + target * 0.3 + (rnd.nextDouble() - 0.5) * target * 0.25);
      if (target > 0 && rnd.nextDouble() < 0.06) w += 1200 + rnd.nextDouble() * 900; // kettle / heater
      w = max(0, w);
      total += w * 2 / 3600000;
      final volts = target == 0 ? 0.0 : _baseVolts(now) + (rnd.nextDouble() - 0.5) * 3 - (w > 1500 ? 4 : 0);
      if (volts > 0 && volts < vMin) (vMin, vMinAt) = (volts, now);
      if (volts > vMax) (vMax, vMaxAt) = (volts, now);
      final pf = w > 0 ? 0.86 + rnd.nextDouble() * 0.1 : 0.0;
      yield LiveReading(
        ts: now,
        watts: w,
        volts: volts,
        amps: volts > 0 ? w / (volts * max(pf, 0.01)) : 0,
        pf: pf,
        kwhTotal: total,
        rssi: -55 - rnd.nextInt(10),
        day: DateTime(now.year, now.month, now.day),
        dayVmin: vMin,
        dayVminAt: vMinAt,
        dayVmax: vMax,
        dayVmaxAt: vMaxAt,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Future<void> watch(String meterId) async {}

  @override
  Future<List<EnergyPoint>> energy(String meterId, DateTime from, DateTime to, Bucket bucket) async {
    final now = DateTime.now();
    if (to.isAfter(now)) to = now;
    final out = <DateTime, double>{};
    var t = DateTime(from.year, from.month, from.day, from.hour);
    while (t.isBefore(to)) {
      final next = t.add(const Duration(hours: 1));
      final frac = next.isAfter(to) ? to.difference(t).inSeconds / 3600 : 1.0;
      final kwh = _hourWatts(t) * frac / 1000;
      final key = switch (bucket) {
        Bucket.hour => t,
        Bucket.day => DateTime(t.year, t.month, t.day),
        Bucket.month => DateTime(t.year, t.month),
      };
      out[key] = (out[key] ?? 0) + kwh;
      t = next;
    }
    return [for (final e in out.entries) EnergyPoint(e.key, e.value)];
  }

  @override
  Future<List<PowerPoint>> power(String meterId, DateTime from) async {
    final now = DateTime.now();
    final pts = <PowerPoint>[];
    var t = DateTime(from.year, from.month, from.day, from.hour, from.minute - from.minute % 5);
    while (t.isBefore(now)) {
      final base = _hourWatts(t);
      final n = _hash(t.millisecondsSinceEpoch ~/ 300000);
      final avg = base * (0.75 + 0.5 * n);
      final peak = base == 0 ? 0.0 : avg + (n > 0.8 ? 1500 * n : 300 * n);
      pts.add(PowerPoint(t, avg, peak));
      t = t.add(const Duration(minutes: 5));
    }
    return pts;
  }

  @override
  Future<List<AlertItem>> alerts(String meterId) async {
    final now = DateTime.now();
    final y = now.subtract(const Duration(days: 1));
    return [
      AlertItem(
        id: 4,
        kind: AlertKind.voltLow,
        value: 194.6,
        createdAt: DateTime(y.year, y.month, y.day, 20, 5),
        resolvedAt: DateTime(y.year, y.month, y.day, 20, 31),
      ),
      AlertItem(
        id: 3,
        kind: AlertKind.highPower,
        value: 3120,
        createdAt: DateTime(y.year, y.month, y.day, 19, 42),
        resolvedAt: DateTime(y.year, y.month, y.day, 19, 58),
      ),
      AlertItem(
        id: 2,
        kind: AlertKind.offline,
        createdAt: now.subtract(const Duration(days: 2, hours: 3)),
        resolvedAt: now.subtract(const Duration(days: 2, hours: 1)),
      ),
    ];
  }

  @override
  Future<void> updateMeter(Meter m) async => _meter = m;

  @override
  Future<ClaimResult> claim(String meterId, String pop, String name) async => ClaimResult.ok;

  @override
  Future<List<Invite>> invites(String meterId) async => List.of(_invites);

  @override
  Future<int> memberCount(String meterId) async => 1;

  @override
  Future<void> invite(String meterId, String email) async =>
      _invites.add(Invite(id: '${_invites.length + 1}', email: email, createdAt: DateTime.now()));

  @override
  Future<void> cancelInvite(String inviteId) async => _invites.removeWhere((i) => i.id == inviteId);

  // exposed for the tariff screen preview
  static Tariff get defaultTariff => Tariff.syriaHousehold;
}
