import 'models.dart';

/// Everything the screens need. Two implementations: the real cloud
/// ([SupabaseRepository]) and a simulated home ([DemoRepository]).
abstract class EnergyRepository {
  Future<List<Meter>> meters();
  Stream<LiveReading?> live(String meterId);

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
