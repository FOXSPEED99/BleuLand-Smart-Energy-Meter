import 'package:bleuland_energy/data/models.dart';
import 'package:bleuland_energy/data/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 13);
  EnergyPoint day(int d, double kwh) => EnergyPoint(DateTime(2026, 10, d), kwh);

  test('average of whole days: not the first (part) day, not today', () {
    // installed on the 11th in the afternoon; today is still going
    expect(typicalDailyKwh([day(11, 3.6), day(12, 4.9), day(13, 6.5)], today), closeTo(4.9, 1e-9));
    expect(typicalDailyKwh([day(10, 2), day(11, 6), day(12, 8)], today), 7);
  });
  test('nothing to go on until one whole day is measured', () {
    expect(typicalDailyKwh([day(12, 4.9), day(13, 6.5)], today), isNull);
    expect(typicalDailyKwh([day(13, 6.5)], today), isNull);
    expect(typicalDailyKwh([], today), isNull);
  });
  test('days without data (before the meter) are skipped', () {
    expect(typicalDailyKwh([day(1, 0), day(2, 0), day(11, 3), day(12, 5)], today), 5);
  });
}
