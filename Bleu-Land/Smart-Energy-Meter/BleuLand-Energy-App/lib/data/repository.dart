import 'models.dart';

/// Everything the screens need. Two implementations: the real cloud
/// ([SupabaseRepository]) and a simulated home ([DemoRepository]).
abstract class EnergyRepository {
  Future<List<Meter>> meters();
  Stream<LiveReading?> live(String meterId);

  /// "Someone is looking at live values": the meter reports every 2 s instead
  /// of every 10 s for the next ~45 s. Call it about every 30 s while shown.
  Future<void> watch(String meterId);

  /// kWh per hour/day/month between [from] and [to] (local time).
  Future<List<EnergyPoint>> energy(String meterId, DateTime from, DateTime to, Bucket bucket);

  /// 5-minute average/peak power since [from].
  Future<List<PowerPoint>> power(String meterId, DateTime from);

  Future<List<AlertItem>> alerts(String meterId);
  Future<void> updateMeter(Meter m);

  Future<ClaimResult> claim(String meterId, String pop, String name);

  Future<List<Invite>> invites(String meterId);
  Future<int> memberCount(String meterId);
  Future<void> invite(String meterId, String email);
  Future<void> cancelInvite(String inviteId);

  bool get isDemo;
}
