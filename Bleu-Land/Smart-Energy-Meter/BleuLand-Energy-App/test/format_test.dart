import 'package:bleuland_energy/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 9, 18);
  String ago(Duration d) => fmtAgoLong(now.subtract(d), now: now);

  test('fmtAgoLong spells the time out', () {
    expect(ago(const Duration(seconds: 30)), 'just now');
    expect(ago(const Duration(minutes: 1)), '1 minute ago');
    expect(ago(const Duration(minutes: 12)), '12 minutes ago');
    expect(ago(const Duration(hours: 1)), '1 hour ago');
    expect(ago(const Duration(hours: 5)), '5 hours ago');
    expect(ago(const Duration(hours: 30)), 'yesterday');
    expect(ago(const Duration(days: 3)), '3 days ago');
    expect(ago(const Duration(days: 10)), 'on 29 Sep');
  });
}
