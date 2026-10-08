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

  bool get isOwner => role == 'owner';

  Meter copyWith({
    String? name,
    String? currency,
    Tariff? tariff,
    int? billingDay,
    int? alertPowerW,
    bool clearAlertPower = false,
    int? alertOfflineMin,
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
      );
}

/// Latest values from the meter (every 10 s via the cloud).
class LiveReading {
  const LiveReading({
    required this.ts,
    required this.watts,
    required this.volts,
    required this.amps,
    required this.pf,
    required this.kwhTotal,
    this.rssi,
  });

  final DateTime ts;
  final double watts, volts, amps, pf;
  final double kwhTotal; // meter's lifetime counter
  final int? rssi;
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

enum AlertKind { highPower, offline }

class AlertItem {
  const AlertItem({required this.id, required this.kind, required this.createdAt, this.value, this.resolvedAt});
  final int id;
  final AlertKind kind;
  final double? value;
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
