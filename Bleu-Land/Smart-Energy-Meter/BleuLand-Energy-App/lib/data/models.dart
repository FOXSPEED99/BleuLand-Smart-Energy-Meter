import '../core/tariff.dart';

class Meter {
  const Meter({
    required this.id,
    required this.name,
    required this.role,
    this.fw,
    this.lastSeen,
    this.timezone = 'Asia/Damascus',
    this.currency = 'SYP',
    this.tariff = Tariff.syriaHousehold,
    this.billingDay = 1,
    this.alertPowerW,
    this.alertOfflineMin = 15,
    this.voltMin = 200,
    this.voltMax = 230,
  });

  final String id; // "SEM1-8B6204"
  final String name; // "My home"
  final String role; // owner | member
  final String? fw;
  final DateTime? lastSeen;
  final String timezone;
  final String currency;
  final Tariff tariff;
  final int billingDay;
  final int? alertPowerW;
  final int alertOfflineMin;
  final double voltMin, voltMax; // normal mains voltage for this home

  bool get isOwner => role == 'owner';

  Meter withFw(String version) => Meter(
        id: id,
        name: name,
        role: role,
        fw: version,
        lastSeen: lastSeen,
        timezone: timezone,
        currency: currency,
        tariff: tariff,
        billingDay: billingDay,
        alertPowerW: alertPowerW,
        alertOfflineMin: alertOfflineMin,
        voltMin: voltMin,
        voltMax: voltMax,
      );

  Meter copyWith({
    String? name,
    String? currency,
    Tariff? tariff,
    int? billingDay,
    int? alertPowerW,
    bool clearAlertPower = false,
    int? alertOfflineMin,
    double? voltMin,
    double? voltMax,
  }) =>
      Meter(
        id: id,
        name: name ?? this.name,
        role: role,
        fw: fw,
        lastSeen: lastSeen,
        timezone: timezone,
        currency: currency ?? this.currency,
        tariff: tariff ?? this.tariff,
        billingDay: billingDay ?? this.billingDay,
        alertPowerW: clearAlertPower ? null : (alertPowerW ?? this.alertPowerW),
        alertOfflineMin: alertOfflineMin ?? this.alertOfflineMin,
        voltMin: voltMin ?? this.voltMin,
        voltMax: voltMax ?? this.voltMax,
      );
}

/// Latest values from the meter (every 10 s via the cloud, every 2 s while
/// the app shows them).
class LiveReading {
  const LiveReading({
    required this.ts,
    required this.watts,
    required this.volts,
    required this.amps,
    required this.pf,
    required this.kwhTotal,
    this.rssi,
    this.ssid,
    this.day,
    this.dayVmin,
    this.dayVminAt,
    this.dayVmax,
    this.dayVmaxAt,
  });

  final DateTime ts;
  final double watts, volts, amps, pf;
  final double kwhTotal; // meter's lifetime counter
  final int? rssi;
  final String? ssid; // WiFi the meter is on

  /// Lowest/highest mains voltage on [day] (the meter's local date).
  final DateTime? day;
  final double? dayVmin, dayVmax;
  final DateTime? dayVminAt, dayVmaxAt;

  /// Today's lowest/highest, or null if none yet today.
  ({double min, DateTime? minAt, double max, DateTime? maxAt})? voltToday(DateTime now) {
    final d = day;
    if (d == null || dayVmin == null || dayVmax == null) return null;
    if (d.year != now.year || d.month != now.month || d.day != now.day) return null;
    return (min: dayVmin!, minAt: dayVminAt, max: dayVmax!, maxAt: dayVmaxAt);
  }
}

enum Bucket { hour, day, month }

class EnergyPoint {
  const EnergyPoint(this.start, this.kwh);
  final DateTime start; // local time, start of the hour/day/month
  final double kwh;
}

class PowerPoint {
  const PowerPoint(this.ts, this.avgW, this.maxW);
  final DateTime ts;
  final double avgW, maxW;
}

enum AlertKind { highPower, offline, voltLow, voltHigh }

class AlertItem {
  const AlertItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.value,
    this.resolvedAt,
    this.severity = 1,
  });
  final int id;
  final AlertKind kind;
  final double? value; // watts, or the worst voltage
  final int severity; // voltage: 1 = a little outside the range, 2 = far outside
  final DateTime createdAt;
  final DateTime? resolvedAt;
  bool get active => resolvedAt == null;
}

class Invite {
  const Invite({required this.id, required this.email, required this.createdAt, this.acceptedAt});
  final String id;
  final String email;
  final DateTime createdAt;
  final DateTime? acceptedAt;
}

enum ClaimResult { ok, wrongCode, notOnlineYet, alreadyClaimed, failed }

/// Firmware on the meter and the newest one it may install.
enum UpdateStage { none, requested, downloading, installing, done, failed }

class FirmwareRelease {
  const FirmwareRelease({required this.version, this.notes, this.size, this.beta = false, this.createdAt});
  final String version;
  final String? notes;
  final int? size; // bytes
  final bool beta;
  final DateTime? createdAt;
}

class FirmwareStatus {
  const FirmwareStatus({
    this.current,
    this.latest,
    this.beta = false,
    this.stage = UpdateStage.none,
    this.target,
    this.error,
    this.stageAt,
  });
  final String? current;
  final FirmwareRelease? latest; // null = up to date
  final bool beta; // this meter is on the test channel
  final UpdateStage stage;
  final String? target; // version being installed
  final String? error;
  final DateTime? stageAt;

  bool get updating =>
      stage == UpdateStage.requested || stage == UpdateStage.downloading || stage == UpdateStage.installing;
}

enum UpdateRequest { ok, upToDate, busy, notOwner, failed }
