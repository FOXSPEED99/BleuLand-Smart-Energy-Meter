import 'package:bleuland_energy/core/levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('usage level', () {
    test('bands at 1, 3 and 5 kW', () {
      expect(usageLevel(0), UsageLevel.light);
      expect(usageLevel(999), UsageLevel.light);
      expect(usageLevel(1000), UsageLevel.moderate);
      expect(usageLevel(2999), UsageLevel.moderate);
      expect(usageLevel(3000), UsageLevel.high);
      expect(usageLevel(5000), UsageLevel.veryHigh);
    });

    test('compared with today so far', () {
      final noon = DateTime(2026, 10, 9, 12);
      // 6 kWh in 12 h = 500 W on average
      expect(versusToday(500, todayKwh: 6, now: noon), 'About your average today');
      expect(versusToday(200, todayKwh: 6, now: noon), 'Below your average today');
      expect(versusToday(650, todayKwh: 6, now: noon), 'Above your average today');
      expect(versusToday(1500, todayKwh: 6, now: noon), '3.0× your average today');
      expect(versusToday(6000, todayKwh: 6, now: noon), '12× your average today');
    });

    test('no comparison too early in the day', () {
      expect(versusToday(500, todayKwh: 0.3, now: DateTime(2026, 10, 9, 0, 30)), isNull);
      expect(versusToday(500, todayKwh: 0, now: DateTime(2026, 10, 9, 12)), isNull);
    });
  });

  group('voltage status (normal 200–230 V)', () {
    VoltStatus s(double v) => voltStatus(v, min: 200, max: 230);

    test('inside the range is normal, edges included', () {
      expect(s(200), VoltStatus.normal);
      expect(s(215), VoltStatus.normal);
      expect(s(230), VoltStatus.normal);
    });

    test('a little outside is mild', () {
      expect(s(195), VoltStatus.lowMild);
      expect(s(190), VoltStatus.lowMild);
      expect(s(235), VoltStatus.highMild);
      expect(s(240), VoltStatus.highMild);
    });

    test('more than 10 V outside is serious', () {
      expect(s(189.9), VoltStatus.lowSerious);
      expect(s(240.1), VoltStatus.highSerious);
      expect(s(160), VoltStatus.lowSerious);
      expect(s(260), VoltStatus.highSerious);
    });

    test('only abnormal readings get advice', () {
      expect(VoltStatus.normal.advice, isNull);
      for (final v in VoltStatus.values.skip(1)) {
        expect(v.advice, isNotNull);
      }
    });
  });
}
