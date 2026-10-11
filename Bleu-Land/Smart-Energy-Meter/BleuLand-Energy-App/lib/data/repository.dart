import 'models.dart';

/// Everything the screens need. Two implementations: the real cloud
/// ([SupabaseRepository]) and a simulated home ([DemoRepository]).
abstract class EnergyRepository {
  Future<List<Meter>> meters();
  Stream<LiveReading?> live(String meterId);

  /// "Someone is looking at live values": the meter reports every 2 s instead
  /// of every 10 s for the next ~45 s. Call it about every 30 s while shown.
  Future<void> watch(String meterId);

  /// Is the cloud reachable? The answer goes to [cloudReachProvider]; called
  /// when the phone's network changes.
  Future<void> checkReach();

  /// kWh per hour/day/month between [from] and [to] (local time).
  Future<List<EnergyPoint>> energy(String meterId, DateTime from, DateTime to, Bucket bucket);

  /// 5-minute average/peak power since [from].
  Future<List<PowerPoint>> power(String meterId, DateTime from);

  Future<List<AlertItem>> alerts(String meterId);
  Future<void> updateMeter(Meter m);

  Future<ClaimResult> claim(String meterId, String pop, String name);

  /// Changing the meter's WiFi (owner). Asks an online meter to open
  /// Bluetooth setup; returns whether the meter was online.
  Future<bool> requestWifiSetup(String meterId);

  /// The 8-character code from the label (owner only, if known), needed for
  /// Bluetooth setup.
  Future<String?> setupCode(String meterId);

  /// Firmware updates over WiFi (owner taps "Update").
  Future<FirmwareStatus> firmware(String meterId);
  Future<UpdateRequest> requestUpdate(String meterId);
  Future<void> cancelUpdate(String meterId);

  /// "Start fresh" (owner only): delete the meter's energy history and
  /// alerts, so the bill, charts and History start from zero. The meter and
  /// its settings stay.
  Future<void> resetData(String meterId);

  Future<List<Invite>> invites(String meterId);
  Future<int> memberCount(String meterId);
  Future<void> invite(String meterId, String email);
  Future<void> cancelInvite(String inviteId);

  bool get isDemo;
}
