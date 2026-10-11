import 'dart:io';

import 'package:bleuland_energy/data/offline_cache.dart';
import 'package:bleuland_energy/data/providers.dart' show hasNetwork;
import 'package:connectivity_plus/connectivity_plus.dart';
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
    await expectLater(
      cache.rows('alerts.X', () async => throw const SocketException('down')),
      throwsA(isA<SocketException>()),
    );
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
    await expectLater(
      cache.rows('meters.u', () async => throw const SocketException('down')),
      throwsA(isA<SocketException>()),
    );
  });

  group('known to be offline', () {
    var offline = false;
    var network = true;
    var asked = 0;
    late OfflineCache fast;

    setUp(() {
      offline = false;
      network = true;
      asked = 0;
      fast = OfflineCache(
        prefs,
        onReached: () => events.add('ok'),
        onUnreachable: () => events.add('offline'),
        isOffline: () => offline,
        hasNetwork: () async => network,
      );
    });

    Future<dynamic> query() async {
      asked++;
      return [42];
    }

    test('saved rows come back at once, without asking the cloud', () async {
      await fast.rows('alerts.X', query);
      await Future<void>.delayed(Duration.zero);
      offline = true;
      expect(await fast.rows('alerts.X', query), [42]);
      expect(asked, 1);
    });

    test('Wi-Fi and data off: saved rows at once, and the app is told', () async {
      await fast.rows('alerts.X', query);
      await Future<void>.delayed(Duration.zero);
      network = false;
      expect(await fast.rows('alerts.X', query), [42]);
      expect(asked, 1);
      expect(events, ['ok', 'offline']);
    });

    test('Wi-Fi and data off with nothing saved fails at once', () async {
      network = false;
      await expectLater(fast.rows('alerts.X', query), throwsA(isA<SocketException>()));
      expect(asked, 0);
    });

    test('offline but nothing saved yet: still tries the cloud', () async {
      offline = true;
      expect(await fast.rows('alerts.X', query), [42]);
      expect(asked, 1);
    });
  });

  test('probe reports whether the cloud answered', () async {
    await cache.probe(() async => []);
    await cache.probe(() async => throw const SocketException('down'));
    await cache.probe(() async => throw const PostgrestException(message: 'denied'));
    expect(events, ['ok', 'offline', 'ok']);
  });

  test('a VPN alone is not a network', () {
    expect(hasNetwork([ConnectivityResult.wifi]), isTrue);
    expect(hasNetwork([ConnectivityResult.mobile, ConnectivityResult.vpn]), isTrue);
    expect(hasNetwork([ConnectivityResult.vpn]), isFalse);
    expect(hasNetwork([ConnectivityResult.none]), isFalse);
  });
}
