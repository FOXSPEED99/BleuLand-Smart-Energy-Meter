import 'package:bleuland_energy/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
  });
  tearDown(() => c.dispose());

  test('one failed request right after one that got through is not "offline"', () {
    final reach = c.read(cloudReachProvider.notifier);
    reach.reached();
    reach.unreachable(); // a slow request timed out while live data flows
    expect(c.read(cloudReachProvider), isTrue);
  });

  test('a failure with nothing through yet means offline, and the next success brings it back', () {
    final reach = c.read(cloudReachProvider.notifier);
    reach.unreachable();
    expect(c.read(cloudReachProvider), isFalse);
    reach.reached();
    expect(c.read(cloudReachProvider), isTrue);
  });
}
