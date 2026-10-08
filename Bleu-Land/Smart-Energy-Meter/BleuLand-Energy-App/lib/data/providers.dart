// App state, wired with Riverpod. Screens "watch" these and rebuild when the
// data changes (new live reading, settings saved, meter switched...).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Bucket;

import '../core/tariff.dart';
import 'demo_repository.dart';
import 'models.dart';
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

final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authChangesProvider);
  return Supabase.instance.client.auth.currentSession;
});

final repositoryProvider = Provider<EnergyRepository>((ref) {
  if (ref.watch(demoModeProvider)) return DemoRepository();
  return SupabaseRepository(Supabase.instance.client);
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

final liveProvider = StreamProvider.family<LiveReading?, String>(
  (ref, id) => ref.watch(repositoryProvider).live(id),
);

typedef EnergyQuery = ({String id, DateTime from, DateTime to, Bucket bucket});

final energyProvider = FutureProvider.family<List<EnergyPoint>, EnergyQuery>(
  (ref, q) => ref.watch(repositoryProvider).energy(q.id, q.from, q.to, q.bucket),
);

final power24hProvider = FutureProvider.family<List<PowerPoint>, String>(
  (ref, id) => ref.watch(repositoryProvider).power(id, DateTime.now().subtract(const Duration(hours: 24))),
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
  });

  final BillingPeriod period;
  final double kwh, cost; // so far this billing period
  final double todayKwh, todayCost, yesterdayKwh;
  final double projectedKwh, projectedCost; // at this pace, by the end of the period
  final TierPosition tier;
  final DateTime? tierCrossDate; // when the cheap block will run out, at this pace
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
  );
});
