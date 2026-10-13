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

/// "Match your bill" (Syria): numbers from the electricity company's own
/// meter, so the bill here matches the paper bill even though the BleuLand
/// meter was installed in the middle of a cycle. The house meter never goes
/// back to zero, so:
///   used before installing = house meter now - "current reading" on the
///   last bill (that reading is where this cycle started).
/// Without the last bill, the days before are estimated from the daily
/// average measured since.
class BillMatch {
  const BillMatch({
    required this.at,
    required this.houseKwh,
    this.cycleStartKwh,
    this.lastBillAmount,
    required this.meterKwh,
  });

  final DateTime at; // when the house meter was read
  final double houseKwh; // the house meter then
  final double? cycleStartKwh; // "current reading" on the last bill
  final double? lastBillAmount; // what the last bill cost (e.g. paid in Sham Cash)
  final double meterKwh; // the BleuLand meter's own counter then

  /// kWh used in [period] before [at]: exact with the last bill's reading,
  /// estimated from [dailyKwh] otherwise; null when [at] isn't in [period]
  /// (the BleuLand meter then measured the whole cycle) or nothing to go on.
  ({double kwh, bool estimated})? before(BillingPeriod period, {double? dailyKwh}) {
    if (at.isBefore(period.start) || !at.isBefore(period.end)) return null;
    if (cycleStartKwh != null) {
      final used = houseKwh - cycleStartKwh!;
      return (kwh: used < 0 ? 0 : used, estimated: false);
    }
    if (dailyKwh == null) return null;
    return (kwh: dailyKwh * at.difference(period.start).inMinutes / 1440, estimated: true);
  }

  /// What the house meter should show when the BleuLand counter reads [meterNow].
  double houseNow(double meterNow) => houseKwh + (meterNow > meterKwh ? meterNow - meterKwh : 0);

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'house_kwh': houseKwh,
        if (cycleStartKwh != null) 'cycle_start_kwh': cycleStartKwh,
        if (lastBillAmount != null) 'last_bill_amount': lastBillAmount,
        'meter_kwh': meterKwh,
      };

  static BillMatch? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return BillMatch(
        at: DateTime.parse(j['at'] as String).toLocal(),
        houseKwh: (j['house_kwh'] as num).toDouble(),
        cycleStartKwh: (j['cycle_start_kwh'] as num?)?.toDouble(),
        lastBillAmount: (j['last_bill_amount'] as num?)?.toDouble(),
        meterKwh: (j['meter_kwh'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

class Tariff {
  const Tariff({required this.tiers, this.fixedPerPeriod = 0, this.periodMonths = 1, this.match});

  final List<TariffTier> tiers;
  final double fixedPerPeriod;
  final int periodMonths;
  final BillMatch? match; // "Match your bill", if set up

  Tariff copyWith({List<TariffTier>? tiers, int? periodMonths, BillMatch? match, bool clearMatch = false}) => Tariff(
        tiers: tiers ?? this.tiers,
        fixedPerPeriod: fixedPerPeriod,
        periodMonths: periodMonths ?? this.periodMonths,
        match: clearMatch ? null : (match ?? this.match),
      );

  static const syriaHousehold = Tariff(
    tiers: [TariffTier(uptoKwh: 300, price: 6), TariffTier(price: 14)],
    periodMonths: 2,
  );

  bool get isSet => tiers.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'tiers': tiers.map((t) => t.toJson()).toList(),
        'fixed_per_period': fixedPerPeriod,
        'period_months': periodMonths,
        if (match != null) 'bill_match': match!.toJson(),
      };

  factory Tariff.fromJson(Map<String, dynamic>? j) {
    if (j == null) return syriaHousehold;
    return Tariff(
      tiers: ((j['tiers'] as List?) ?? const [])
          .map((t) => TariffTier.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      fixedPerPeriod: (j['fixed_per_period'] as num?)?.toDouble() ?? 0,
      periodMonths: (j['period_months'] as num?)?.toInt() ?? 1,
      match: BillMatch.fromJson(j['bill_match']),
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

  /// The other way round: how many kWh a bill of [amount] paid for, block
  /// by block (≈: a real bill may add small fees on top).
  double kwhFor(double amount) {
    var left = amount - fixedPerPeriod;
    if (!isSet || left <= 0) return 0;
    double done = 0;
    for (final t in tiers) {
      final size = (t.uptoKwh ?? double.infinity) - done;
      if (t.price <= 0) return t.uptoKwh ?? done; // free block: can't tell how far it went
      final inTier = left / t.price;
      if (inTier <= size) return done + inTier;
      left -= size * t.price;
      done += size;
    }
    return done;
  }

  /// A day's use going by the last bill: its kWh over the days of the cycle
  /// before [current] (the one that bill was for).
  double dailyFromLastBill(double amount, BillingPeriod current, {int billingDay = 1}) {
    final last = BillingPeriod.containing(
      current.start.subtract(const Duration(days: 1)),
      billingDay: billingDay,
      periodMonths: periodMonths,
    );
    return kwhFor(amount) / last.days;
  }

  /// What each slice of [usage] added to the bill. Price blocks restart every
  /// billing cycle, so the same kWh is cheap early in a cycle and dear once
  /// the cheap block is used up: [usage] must cover each cycle from its start.
  /// [known] is a cycle's total at a moment ("Match your bill"): from there
  /// that cycle counts on from it. Keyed by slice start.
  Map<DateTime, double> priceInOrder(
    List<({DateTime start, double kwh})> usage,
    BillingPeriod Function(DateTime) cycleOf, {
    ({DateTime at, double kwh})? known,
  }) {
    final used = <DateTime, double>{}; // per cycle start
    final out = <DateTime, double>{};
    final knownCycle = known == null ? null : cycleOf(known.at).start;
    var anchored = known == null;
    for (final u in [...usage]..sort((a, b) => a.start.compareTo(b.start))) {
      final c = cycleOf(u.start).start;
      if (!anchored && c == knownCycle && !u.start.isBefore(known!.at)) {
        used[c] = known.kwh;
        anchored = true;
      }
      final soFar = used[c] ?? 0;
      out[u.start] = marginalCost(soFar, u.kwh);
      used[c] = soFar + u.kwh;
    }
    return out;
  }

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
