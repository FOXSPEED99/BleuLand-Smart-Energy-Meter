// Electricity price with consumption blocks ("tiers"), as on Syrian bills:
// the first 300 kWh of each 2-month cycle cost 6 SYP/kWh, the rest 14 SYP/kWh
// (Ministry of Energy decision, 30 Oct 2025, new Syrian pounds).
// Stored per meter in the cloud as JSON; the owner can change it.

class TariffTier {
  const TariffTier({this.uptoKwh, required this.price});

  /// Upper limit of this block within one billing period; null = no limit.
  final double? uptoKwh;
  final double price; // currency per kWh

  Map<String, dynamic> toJson() => {if (uptoKwh != null) 'upto_kwh': uptoKwh, 'price': price};

  factory TariffTier.fromJson(Map<String, dynamic> j) => TariffTier(
        uptoKwh: (j['upto_kwh'] as num?)?.toDouble(),
        price: (j['price'] as num).toDouble(),
      );
}

class Tariff {
  const Tariff({required this.tiers, this.fixedPerPeriod = 0, this.periodMonths = 1});

  final List<TariffTier> tiers;
  final double fixedPerPeriod;
  final int periodMonths;

  static const syriaHousehold = Tariff(
    tiers: [TariffTier(uptoKwh: 300, price: 6), TariffTier(price: 14)],
    periodMonths: 2,
  );

  bool get isSet => tiers.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'tiers': tiers.map((t) => t.toJson()).toList(),
        'fixed_per_period': fixedPerPeriod,
        'period_months': periodMonths,
      };

  factory Tariff.fromJson(Map<String, dynamic>? j) {
    if (j == null) return syriaHousehold;
    return Tariff(
      tiers: ((j['tiers'] as List?) ?? const [])
          .map((t) => TariffTier.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      fixedPerPeriod: (j['fixed_per_period'] as num?)?.toDouble() ?? 0,
      periodMonths: (j['period_months'] as num?)?.toInt() ?? 1,
    );
  }

  /// Bill for [kwh] consumed within one billing period.
  double costFor(double kwh) {
    if (!isSet || kwh <= 0) return isSet ? fixedPerPeriod : 0;
    double cost = fixedPerPeriod, done = 0;
    for (final t in tiers) {
      final top = t.uptoKwh ?? double.infinity;
      if (kwh <= done) break;
      final inTier = (kwh < top ? kwh : top) - done;
      if (inTier > 0) cost += inTier * t.price;
      done = top;
    }
    return cost;
  }

  /// Extra cost of the next [kwh], given [usedSoFar] kWh already this period
  /// (e.g. "today cost" = costFor(used incl. today) - costFor(used before today)).
  double marginalCost(double usedSoFar, double kwh) => costFor(usedSoFar + kwh) - costFor(usedSoFar);

  /// Which block [kwh] falls in, and how much is left in it.
  TierPosition position(double kwh) {
    double start = 0;
    for (var i = 0; i < tiers.length; i++) {
      final top = tiers[i].uptoKwh;
      if (top == null || kwh < top) {
        return TierPosition(index: i, tierStart: start, tierEnd: top, price: tiers[i].price);
      }
      start = top;
    }
    final last = tiers.isEmpty ? const TariffTier(price: 0) : tiers.last;
    return TierPosition(index: tiers.length - 1, tierStart: start, tierEnd: null, price: last.price);
  }
}

class TierPosition {
  const TierPosition({required this.index, required this.tierStart, required this.tierEnd, required this.price});
  final int index; // 0 = cheapest block
  final double tierStart;
  final double? tierEnd; // null = last, open-ended block
  final double price;
  double? remainingFrom(double kwh) => tierEnd == null ? null : (tierEnd! - kwh).clamp(0, double.infinity);
}

/// Billing periods start on [billingDay] of every [periodMonths]-th month,
/// counted from January (2-month cycles: Jan, Mar, May, Jul, Sep, Nov).
class BillingPeriod {
  BillingPeriod(this.start, this.end);
  final DateTime start; // inclusive, local time
  final DateTime end; // exclusive

  int get days => end.difference(start).inDays;

  static BillingPeriod containing(DateTime now, {int billingDay = 1, int periodMonths = 1}) {
    final day = billingDay.clamp(1, 28);
    final months = periodMonths.clamp(1, 12);
    // months since the anchor (January of year 0) for a period starting this month
    var m = now.year * 12 + (now.month - 1);
    m -= m % months;
    var start = DateTime(m ~/ 12, m % 12 + 1, day);
    if (start.isAfter(now)) {
      m -= months;
      start = DateTime(m ~/ 12, m % 12 + 1, day);
    }
    final e = m + months;
    return BillingPeriod(start, DateTime(e ~/ 12, e % 12 + 1, day));
  }
}
