import 'dart:io';

import 'package:bleuland_energy/data/offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Bucket;

void main() {
  late SharedPreferences prefs;
  late List<String> events;
  late OfflineCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    events = [];
    cache = OfflineCache(prefs, onReached: () => events.add('ok'), onUnreachable: () => events.add('offline'));
  });

  test('saves what the cloud returned and gives it back without internet', () async {
    final rows = [
      {'ts': '2026-10-10T19:00:00Z', 'p_avg': 120},
    ];
    expect(await cache.rows('power.X', () async => rows), rows);
    await Future<void>.delayed(Duration.zero); // let the save finish
    expect(OfflineCache.savedAt(prefs), isNotNull);

    final offline = await cache.rows('power.X', () async => throw const SocketException('Failed host lookup'));
    expect(offline, rows);
    expect(events, ['ok', 'offline']);
  });

  test('without internet and nothing saved, the error is passed on', () async {
    await expectLater(cache.rows('alerts.X', () async => throw const SocketException('down')), throwsA(isA<SocketException>()));
    expect(events, ['offline']);
  });

  test('a server error is not "offline" and is not hidden by saved data', () async {
    await cache.rows('meters.u', () async => [1, 2]);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      cache.rows('meters.u', () async => throw const PostgrestException(message: 'permission denied', code: '42501')),
      throwsA(isA<PostgrestException>()),
    );
    expect(events, ['ok', 'ok']);
  });

  test('sign out clears everything saved', () async {
    await cache.rows('meters.u', () async => [1]);
    await Future<void>.delayed(Duration.zero);
    await OfflineCache.clear(prefs);
    expect(OfflineCache.savedAt(prefs), isNull);
    await expectLater(cache.rows('meters.u', () async => throw const SocketException('down')), throwsA(isA<SocketException>()));
  });
}
