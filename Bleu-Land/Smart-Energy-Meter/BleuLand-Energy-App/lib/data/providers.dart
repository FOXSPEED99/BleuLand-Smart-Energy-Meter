// App state, wired with Riverpod. Screens "watch" these and rebuild when the
// data changes (new live reading, settings saved, meter switched...).
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Bucket;

import '../core/region.dart';
import '../core/tariff.dart';
import 'demo_repository.dart';
import 'models.dart';
import 'offline_cache.dart';
import 'repository.dart';
import 'supabase_repository.dart';

/// Set in main() once SharedPreferences has loaded.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// Demo mode: a simulated home instead of the cloud.
class DemoMode extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).getBool('demo') ?? false;

  void set(bool on) {
    ref.read(prefsProvider).setBool('demo', on);
    state = on;
  }
}

final demoModeProvider = NotifierProvider<DemoMode, bool>(DemoMode.new);

/// Fires on every login / logout.
final authChangesProvider = StreamProvider<AuthState>((ref) => Supabase.instance.client.auth.onAuthStateChange);

/// The user's country (null: not picked yet). Kept in the account itself,
/// so it comes along to a new phone.
final regionProvider = Provider<String?>((ref) {
  if (ref.watch(demoModeProvider)) return 'sy';
  ref.watch(authChangesProvider);
  return userRegion();
});

String? userRegion() {
  final v = Supabase.instance.client.auth.currentUser?.userMetadata?['region'];
  return v is String ? v : null;
}

Future<void> saveRegion(String id) =>
    Supabase.instance.client.auth.updateUser(UserAttributes(data: {'region': id}));

final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authChangesProvider);
  return Supabase.instance.client.auth.currentSession;
});

final repositoryProvider = Provider<EnergyRepository>((ref) {
  if (ref.watch(demoModeProvider)) return DemoRepository();
  final reach = ref.read(cloudReachProvider.notifier);
  return SupabaseRepository(
    Supabase.instance.client,
    OfflineCache(
      ref.read(prefsProvider),
      onReached: reach.reached,
      onUnreachable: reach.unreachable,
      isOffline: () => ref.read(phoneOfflineProvider),
      hasNetwork: () async => hasNetwork(await Connectivity().checkConnectivity()),
    ),
  );
});

// ---------- is the phone online? ----------

/// Wi-Fi, mobile data or cable is on. A VPN alone doesn't count: with Wi-Fi
/// and data off, a VPN app can stay "connected" with nothing under it.
bool hasNetwork(List<ConnectivityResult> r) =>
    r.any((x) => x != ConnectivityResult.none && x != ConnectivityResult.vpn);

/// Every change of the phone's network (Wi-Fi on/off, switched to data...).
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  final c = Connectivity();
  yield await c.checkConnectivity();
  yield* c.onConnectivityChanged;
});

/// The phone's own network: Wi-Fi or mobile data switched on (true) or not.
/// Gone only once it stays gone for a few seconds: phones report a short
/// "no network" while Wi-Fi hands over or reconnects.
class NetworkUp extends Notifier<bool> {
  static const settle = Duration(seconds: 4);
  Timer? _down;

  @override
  bool build() {
    ref.onDispose(() => _down?.cancel());
    ref.listen(connectivityProvider, (_, next) {
      final r = next.value;
      if (r == null) return;
      if (hasNetwork(r)) {
        _down?.cancel();
        _down = null;
        state = true;
      } else {
        _down ??= Timer(settle, () {
          _down = null;
          state = false;
        });
      }
    });
    final r = ref.read(connectivityProvider).value;
    return r == null || hasNetwork(r);
  }
}

final networkProvider = NotifierProvider<NetworkUp, bool>(NetworkUp.new);

/// Whether the last cloud request got through. Catches Wi-Fi or data that's
/// connected but has no internet, which the phone itself reports as online.
/// Remembered between launches, so an app opened without internet shows the
/// saved data at once (the first "still there?" check corrects it).
///
/// One failed request right after one that got through isn't "no internet":
/// on a slow or patchy line a request times out now and then while live data
/// keeps arriving, and flipping to offline (and back, reloading everything)
/// each time made the offline note blink. A failure counts only when nothing
/// got through for [grace].
class CloudReach extends Notifier<bool> {
  static const _key = 'cloud_reach';
  static const grace = Duration(seconds: 30);
  DateTime? _lastReached;

  @override
  bool build() => ref.read(prefsProvider).getBool(_key) ?? true;

  void reached() {
    _lastReached = DateTime.now();
    _set(true);
  }

  void unreachable() {
    final last = _lastReached;
    if (last != null && DateTime.now().difference(last) < grace) return;
    _set(false);
  }

  void _set(bool v) {
    if (state == v) return;
    state = v;
    ref.read(prefsProvider).setBool(_key, v);
  }
}

final cloudReachProvider = NotifierProvider<CloudReach, bool>(CloudReach.new);

/// No internet on the phone: screens show saved data and say so.
final phoneOfflineProvider = Provider<bool>((ref) {
  if (ref.watch(demoModeProvider)) return false;
  return !ref.watch(networkProvider) || !ref.watch(cloudReachProvider);
});

/// When the shown cloud data was saved (for "saved at 14:32").
final savedAtProvider = Provider<DateTime?>((ref) {
  ref.watch(phoneOfflineProvider);
  return OfflineCache.savedAt(ref.read(prefsProvider));
});

final metersProvider = FutureProvider<List<Meter>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (!repo.isDemo && ref.watch(sessionProvider) == null) return const [];
  return repo.meters();
});

/// Which meter the screens show (remembered between launches).
class SelectedMeterId extends Notifier<String?> {
  @override
  String? build() => ref.read(prefsProvider).getString('meter');

  void select(String id) {
    ref.read(prefsProvider).setString('meter', id);
    state = id;
  }
}

final selectedMeterIdProvider = NotifierProvider<SelectedMeterId, String?>(SelectedMeterId.new);

final currentMeterProvider = Provider<AsyncValue<Meter?>>((ref) {
  final wanted = ref.watch(selectedMeterIdProvider);
  return ref.watch(metersProvider).whenData((list) {
    if (list.isEmpty) return null;
    return list.firstWhere((m) => m.id == wanted, orElse: () => list.first);
  });
});

final liveProvider = StreamProvider.family<LiveReading?, String>((ref, id) => ref.watch(repositoryProvider).live(id));

typedef EnergyQuery = ({String id, DateTime from, DateTime to, Bucket bucket});

final energyProvider = FutureProvider.family<List<EnergyPoint>, EnergyQuery>(
  (ref, q) => ref.watch(repositoryProvider).energy(q.id, q.from, q.to, q.bucket),
);

/// What each bar in History added to the bill, keyed by bar start: walks
/// usage from the start of the billing cycle the bars begin in, so the price
/// block each kWh fell in is right (see Tariff.priceInOrder).
final costProvider = FutureProvider.family<Map<DateTime, double>, EnergyQuery>((ref, q) async {
  final meter = (await ref.watch(metersProvider.future)).firstWhere((m) => m.id == q.id);
  final t = meter.tariff;
  BillingPeriod cycleOf(DateTime d) =>
      BillingPeriod.containing(d, billingDay: meter.billingDay, periodMonths: t.periodMonths);
  final first = cycleOf(q.from).start;
  final usage = [
    if (first.isBefore(q.from))
      ...await ref.watch(energyProvider((id: q.id, from: first, to: q.from, bucket: Bucket.day)).future),
    ...await ref.watch(energyProvider(q).future),
  ];
  // "Match your bill": this cycle also has the days before the meter
  ({DateTime at, double kwh})? known;
  final match = regionById(ref.watch(regionProvider))?.billMatch == true ? t.match : null;
  if (match != null) {
    final c = await ref.watch(cycleProvider(q.id).future);
    if (c.beforeKwh != null) known = (at: match.at, kwh: c.beforeKwh!);
  }
  return t.priceInOrder([for (final p in usage) (start: p.start, kwh: p.kwh)], cycleOf, known: known);
});

final power24hProvider =FutureProvider.family<List<PowerPoint>, String>(
  (ref, id) => ref.watch(repositoryProvider).power(id, DateTime.now().subtract(const Duration(hours: 24))),
);

final firmwareProvider = FutureProvider.family<FirmwareStatus, String>(
  (ref, id) => ref.watch(repositoryProvider).firmware(id),
);

final alertsProvider = FutureProvider.family<List<AlertItem>, String>(
  (ref, id) => ref.watch(repositoryProvider).alerts(id),
);

/// Everything the "this bill" card needs.
class CycleSummary {
  const CycleSummary({
    required this.period,
    required this.kwh,
    required this.cost,
    required this.todayKwh,
    required this.todayCost,
    required this.yesterdayKwh,
    required this.projectedKwh,
    required this.projectedCost,
    required this.tier,
    this.tierCrossDate,
    this.beforeKwh,
    this.beforeEstimated = false,
    this.measuredKwh,
  });

  final BillingPeriod period;
  final double kwh, cost; // so far this billing period
  final double todayKwh, todayCost, yesterdayKwh;
  final double projectedKwh, projectedCost; // at this pace, by the end of the period
  final TierPosition tier;
  final DateTime? tierCrossDate; // when the cheap block will run out, at this pace
  // "Match your bill" in this cycle: used before the BleuLand meter (from the
  // house meter, or estimated) + measured by it since
  final double? beforeKwh;
  final bool beforeEstimated;
  final double? measuredKwh;
}

/// A normal day's use, for estimating days the meter didn't see: the
/// average of whole days it measured. Not today (still going), and not the
/// first day with data (it started part-way through, at install or after a
/// reset). Null until there's at least one such day: a few hours say little,
/// as nights and evenings differ a lot.
double? typicalDailyKwh(List<EnergyPoint> days, DateTime today) {
  final measured = [
    for (final d in [...days]..sort((a, b) => a.start.compareTo(b.start)))
      if (d.kwh > 0 && d.start.isBefore(today)) d.kwh,
  ];
  if (measured.length < 2) return null;
  final whole = measured.sublist(1);
  return whole.reduce((a, b) => a + b) / whole.length;
}

final cycleProvider = FutureProvider.family<CycleSummary, String>((ref, id) async {
  final meter = (await ref.watch(metersProvider.future)).firstWhere((m) => m.id == id);
  final repo = ref.watch(repositoryProvider);
  final now = DateTime.now();
  final t = meter.tariff;
  final period = BillingPeriod.containing(now, billingDay: meter.billingDay, periodMonths: t.periodMonths);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  // always include all of yesterday, for the "vs yesterday" comparison
  final from = period.start.isBefore(yesterday) ? period.start : yesterday;
  final days = await repo.energy(id, from, now, Bucket.day);
  double kwh = 0, todayKwh = 0, yesterdayKwh = 0;
  for (final d in days) {
    if (!d.start.isBefore(period.start)) kwh += d.kwh;
    if (d.start == today) todayKwh = d.kwh;
    if (d.start == yesterday) yesterdayKwh = d.kwh;
  }

  // "Match your bill" (where the country supports it): the part of the cycle
  // before the house meter was read comes from its numbers, the rest from
  // what the BleuLand meter measured since
  double? beforeKwh, measuredKwh;
  var beforeEstimated = false;
  final match = regionById(ref.watch(regionProvider))?.billMatch == true ? t.match : null;
  if (match != null && !match.at.isBefore(period.start) && match.at.isBefore(now)) {
    final since = await repo.energy(id, match.at, now, Bucket.hour);
    final sinceKwh = since.fold(0.0, (s, p) => s + p.kwh);
    final before = match.before(period, dailyKwh: typicalDailyKwh(days, today));
    if (before != null) {
      kwh = before.kwh + sinceKwh;
      beforeKwh = before.kwh;
      beforeEstimated = before.estimated;
      measuredKwh = sinceKwh;
    }
  }

  final elapsed = now.difference(period.start).inMinutes / (24 * 60);
  final perDay = elapsed > 0.5 ? kwh / elapsed : 0.0;
  final projected = elapsed > 0.5 ? perDay * period.days : kwh;

  final tier = t.position(kwh);
  DateTime? cross;
  if (tier.tierEnd != null && perDay > 0 && projected > tier.tierEnd!) {
    final daysLeft = (tier.tierEnd! - kwh) / perDay;
    cross = now.add(Duration(minutes: (daysLeft * 24 * 60).round()));
  }

  return CycleSummary(
    period: period,
    kwh: kwh,
    cost: t.costFor(kwh),
    todayKwh: todayKwh,
    todayCost: t.marginalCost(kwh - todayKwh, todayKwh),
    yesterdayKwh: yesterdayKwh,
    projectedKwh: projected,
    projectedCost: t.costFor(projected),
    tier: tier,
    tierCrossDate: cross,
    beforeKwh: beforeKwh,
    beforeEstimated: beforeEstimated,
    measuredKwh: measuredKwh,
  );
});
