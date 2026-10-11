import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Bucket;

/// Keeps the last answer of each cloud query on the phone, so the app still
/// opens and shows the bill, history and alerts without internet.
///
/// [rows] runs a query; when it works the raw rows are saved, when the
/// network fails the saved rows come back instead (the same parsing then
/// runs on them). A server error (the cloud answered "no") is not a network
/// problem, so it's passed on as before.
///
/// When the phone is already known to be offline the saved rows come back
/// at once, without waiting for a request that can't get through.
class OfflineCache {
  OfflineCache(
    this._prefs, {
    required this.onReached,
    required this.onUnreachable,
    bool Function()? isOffline,
    Future<bool> Function()? hasNetwork,
  }) : isOffline = isOffline ?? (() => false),
       hasNetwork = hasNetwork ?? (() async => true);

  final SharedPreferences _prefs;
  final void Function() onReached; // a request got through
  final void Function() onUnreachable; // a request failed for lack of network
  final bool Function() isOffline; // already known: no internet right now
  final Future<bool> Function() hasNetwork; // Wi-Fi or mobile data switched on

  /// How long a request may take before the saved rows are shown instead.
  static const timeout = Duration(seconds: 8);

  static const _prefix = 'cache.';
  static const _savedAtKey = 'cache_saved_at';
  static const _energyIndexKey = 'cache_energy_keys';
  static const _maxEnergyEntries = 40; // history pages the user browsed

  /// When cloud data was last saved (shown as "saved at 14:32" offline).
  static DateTime? savedAt(SharedPreferences prefs) {
    final ms = prefs.getInt(_savedAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<dynamic> rows(String key, Future<dynamic> Function() query) async {
    final saved = _prefs.getString('$_prefix$key');
    if (isOffline() && saved != null) return jsonDecode(saved);
    if (!await hasNetwork()) {
      onUnreachable();
      if (saved != null) return jsonDecode(saved);
      throw const SocketException('No network');
    }
    try {
      final v = await query().timeout(timeout);
      onReached();
      unawaited(_save(key, v));
      return v;
    } on PostgrestException {
      onReached(); // the cloud answered; it's not the network
      rethrow;
    } catch (_) {
      onUnreachable();
      if (saved == null) rethrow;
      return jsonDecode(saved);
    }
  }

  /// A small request just to learn whether the cloud can be reached
  /// (network switched, or the periodic "still there?" check).
  Future<void> probe(Future<dynamic> Function() query) async {
    try {
      await query().timeout(timeout);
      onReached();
    } on PostgrestException {
      onReached();
    } catch (_) {
      onUnreachable();
    }
  }

  Future<void> _save(String key, dynamic v) async {
    await _prefs.setString('$_prefix$key', jsonEncode(v));
    await _prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
    if (!key.startsWith('energy.')) return;
    // keep the number of saved history pages bounded (oldest out first)
    final index = _prefs.getStringList(_energyIndexKey) ?? [];
    index
      ..remove(key)
      ..add(key);
    while (index.length > _maxEnergyEntries) {
      await _prefs.remove('$_prefix${index.removeAt(0)}');
    }
    await _prefs.setStringList(_energyIndexKey, index);
  }

  /// Forget everything (sign out): the next account must not see this one's data.
  static Future<void> clear(SharedPreferences prefs) async {
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(k);
    }
    await prefs.remove(_savedAtKey);
    await prefs.remove(_energyIndexKey);
  }
}
