// How to describe a power or voltage reading in words. Pure logic (unit
// tested), so the screens only decide how it looks.

/// How much the whole house is drawing right now.
enum UsageLevel { light, moderate, high, veryHigh }

UsageLevel usageLevel(double watts) {
  if (watts < 1000) return UsageLevel.light;
  if (watts < 3000) return UsageLevel.moderate;
  if (watts < 5000) return UsageLevel.high;
  return UsageLevel.veryHigh;
}

extension UsageLevelText on UsageLevel {
  String get label => switch (this) {
        UsageLevel.light => 'Light use',
        UsageLevel.moderate => 'Moderate use',
        UsageLevel.high => 'High use',
        UsageLevel.veryHigh => 'Very high use',
      };

  String get range => switch (this) {
        UsageLevel.light => 'under 1 kW',
        UsageLevel.moderate => '1–3 kW',
        UsageLevel.high => '3–5 kW',
        UsageLevel.veryHigh => 'over 5 kW',
      };
}

/// Right now compared with the average power so far today.
/// Null when there isn't enough of today yet to compare with.
String? versusToday(double watts, {required double todayKwh, required DateTime now}) {
  final hours = now.hour + now.minute / 60;
  if (hours < 1 || todayKwh < 0.05) return null;
  final avgW = todayKwh * 1000 / hours;
  final ratio = watts / avgW;
  if (ratio >= 1.5) return '${ratio >= 10 ? ratio.round() : ratio.toStringAsFixed(1)}× your average today';
  if (ratio > 1.15) return 'Above your average today';
  if (ratio >= 0.85) return 'About your average today';
  return 'Below your average today';
}

/// Mains voltage against the owner's normal range. Up to 3 V past a limit
/// still counts as normal (that's within the meter's own tolerance, and a
/// 230.1 V blip is harmless). "A little" outside is from there to 10 V beyond
/// the range; further than that is serious.
enum VoltStatus { normal, lowMild, lowSerious, highMild, highSerious }

const voltGrace = 3.0;
const voltSeriousMargin = 10.0;

VoltStatus voltStatus(double v, {required double min, required double max}) {
  if (v < min - voltSeriousMargin) return VoltStatus.lowSerious;
  if (v < min - voltGrace) return VoltStatus.lowMild;
  if (v > max + voltSeriousMargin) return VoltStatus.highSerious;
  if (v > max + voltGrace) return VoltStatus.highMild;
  return VoltStatus.normal;
}

extension VoltStatusText on VoltStatus {
  bool get serious => this == VoltStatus.lowSerious || this == VoltStatus.highSerious;
  bool get low => this == VoltStatus.lowMild || this == VoltStatus.lowSerious;

  String get label => switch (this) {
        VoltStatus.normal => 'Normal',
        VoltStatus.lowMild => 'A bit low',
        VoltStatus.lowSerious => 'Too low',
        VoltStatus.highMild => 'A bit high',
        VoltStatus.highSerious => 'Too high',
      };

  /// What it means for the home, in one short line (the chip already says
  /// how low or high). Null when everything is fine.
  String? get advice => switch (this) {
        VoltStatus.normal => null,
        VoltStatus.lowMild => 'Motors like the fridge and AC run hotter.',
        VoltStatus.lowSerious => 'Can damage fridge and AC. Switch them off.',
        VoltStatus.highMild => 'Lamps and electronics wear out faster.',
        VoltStatus.highSerious => 'Can damage electronics. Unplug them now.',
      };
}
