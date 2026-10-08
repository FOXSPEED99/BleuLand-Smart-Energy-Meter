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
}
