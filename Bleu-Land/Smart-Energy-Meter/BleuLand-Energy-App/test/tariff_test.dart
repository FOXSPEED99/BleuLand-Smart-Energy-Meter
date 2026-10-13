import 'package:bleuland_energy/core/tariff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t = Tariff.syriaHousehold; // 300 kWh at 6, then 14, per 2 months

  group('tiered cost', () {
    test('inside the first block', () => expect(t.costFor(100), 600));
    test('exactly at the limit', () => expect(t.costFor(300), 1800));
    test('across the limit', () => expect(t.costFor(400), 300 * 6 + 100 * 14)); // the SANA example
    test('zero and negative', () {
      expect(t.costFor(0), 0);
      expect(t.costFor(-5), 0);
    });
    test('marginal cost crosses blocks', () => expect(t.marginalCost(290, 20), 10 * 6 + 10 * 14));
    test('fixed fee is added once', () {
      const f = Tariff(tiers: [TariffTier(price: 2)], fixedPerPeriod: 50);
      expect(f.costFor(10), 70);
      expect(f.costFor(0), 50);
    });
    test('not set = free', () => expect(const Tariff(tiers: []).costFor(100), 0));
  });

  group('tier position', () {
    test('first block', () {
      final p = t.position(220);
      expect(p.index, 0);
      expect(p.remainingFrom(220), 80);
    });
    test('second block is open ended', () {
      final p = t.position(310);
      expect(p.index, 1);
      expect(p.tierEnd, isNull);
    });
  });

  group('billing period', () {
    test('monthly, day 1', () {
      final p = BillingPeriod.containing(DateTime(2026, 10, 8));
      expect(p.start, DateTime(2026, 10, 1));
      expect(p.end, DateTime(2026, 11, 1));
    });
    test('two-month cycles start in odd months', () {
      final p = BillingPeriod.containing(DateTime(2026, 10, 8), periodMonths: 2);
      expect(p.start, DateTime(2026, 9, 1));
      expect(p.end, DateTime(2026, 11, 1));
      expect(p.days, 61);
    });
    test('billing day later in the month rolls back', () {
      final p = BillingPeriod.containing(DateTime(2026, 9, 3), billingDay: 15, periodMonths: 2);
      expect(p.start, DateTime(2026, 7, 15));
      expect(p.end, DateTime(2026, 9, 15));
    });
    test('across the new year', () {
      final p = BillingPeriod.containing(DateTime(2027, 1, 20), periodMonths: 2);
      expect(p.start, DateTime(2027, 1, 1));
      expect(p.end, DateTime(2027, 3, 1));
    });
  });

  test('json round trip', () {
    final back = Tariff.fromJson(t.toJson());
    expect(back.costFor(400), t.costFor(400));
    expect(back.periodMonths, 2);
  });

  group('match your bill', () {
    // Syrian cycle Sep–Oct 2026; matched on 21 Sep at noon
    final period = BillingPeriod.containing(DateTime(2026, 10, 12), periodMonths: 2);
    final at = DateTime(2026, 9, 21, 12);

    test('cycle is Sep–Oct', () {
      expect(period.start, DateTime(2026, 9, 1));
      expect(period.end, DateTime(2026, 11, 1));
    });
    test('exact with the last bill reading', () {
      final m = BillMatch(at: at, houseKwh: 12480, cycleStartKwh: 12300, meterKwh: 3.2);
      expect(m.before(period), 180);
    });
    test('no guessing without it', () {
      final m = BillMatch(at: at, houseKwh: 12480, meterKwh: 3.2);
      expect(m.before(period), isNull);
    });
    test('a bill reading above the house meter counts as 0', () {
      final m = BillMatch(at: at, houseKwh: 100, cycleStartKwh: 150, meterKwh: 0);
      expect(m.before(period), 0);
    });
    test('outside the cycle = the BleuLand meter measured it all', () {
      final m = BillMatch(at: DateTime(2026, 8, 30), houseKwh: 1, cycleStartKwh: 0, meterKwh: 0);
      expect(m.before(period), isNull);
    });
    test('house meter now follows the BleuLand counter', () {
      final m = BillMatch(at: at, houseKwh: 12480, meterKwh: 3.2);
      expect(m.houseNow(53.2), closeTo(12530, 1e-9));
      expect(m.houseNow(1), 12480); // counter reset = no change
    });
    test('saved and read back with the tariff', () {
      final m = BillMatch(at: at, houseKwh: 12480, cycleStartKwh: 12300, meterKwh: 3.2);
      final back = Tariff.fromJson(t.copyWith(match: m).toJson()).match!;
      expect(back.at, at);
      expect(back.houseKwh, 12480);
      expect(back.cycleStartKwh, 12300);
      expect(back.meterKwh, 3.2);
      expect(Tariff.fromJson(t.toJson()).match, isNull);
    });
    test('copyWith keeps or clears the match', () {
      final m = BillMatch(at: at, houseKwh: 1, meterKwh: 0);
      final withMatch = t.copyWith(match: m);
      expect(withMatch.copyWith(periodMonths: 1).match, same(m));
      expect(withMatch.copyWith(clearMatch: true).match, isNull);
    });
  });

  group('cost of each bar', () {
    BillingPeriod cycleOf(DateTime d) => BillingPeriod.containing(d, periodMonths: 2);
    ({DateTime start, double kwh}) day(int m, int d, double kwh) => (start: DateTime(2026, m, d), kwh: kwh);

    test('cheap until the cycle passes 300 kWh, then dear', () {
      final c = t.priceInOrder([day(9, 1, 250), day(9, 2, 100)], cycleOf);
      expect(c[DateTime(2026, 9, 1)], 250 * 6);
      expect(c[DateTime(2026, 9, 2)], 50 * 6 + 50 * 14);
    });
    test('a new cycle starts cheap again', () {
      final c = t.priceInOrder([day(10, 31, 400), day(11, 1, 10)], cycleOf);
      expect(c[DateTime(2026, 11, 1)], 60);
    });
    test('order of the list does not matter', () {
      final c = t.priceInOrder([day(9, 2, 100), day(9, 1, 250)], cycleOf);
      expect(c[DateTime(2026, 9, 2)], 50 * 6 + 50 * 14);
    });
    test('a matched bill counts from its total on', () {
      final c = t.priceInOrder(
        [day(9, 20, 5), day(9, 21, 10), day(9, 22, 10)],
        cycleOf,
        known: (at: DateTime(2026, 9, 21), kwh: 295),
      );
      expect(c[DateTime(2026, 9, 20)], 30); // before the match: what the meter saw
      expect(c[DateTime(2026, 9, 21)], 5 * 6 + 5 * 14); // 295 → 305
      expect(c[DateTime(2026, 9, 22)], 10 * 14);
    });
  });
}
