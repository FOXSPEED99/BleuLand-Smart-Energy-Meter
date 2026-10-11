import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Bucket;

/// Keeps the last answer of each cloud query on the phone, so the app still
/// opens and shows the bill, history and alerts without internet.
///
/// [rows] runs a query; when it works the raw rows are saved, when the
/// network fails the saved rows come back instead (the same parsing then
/// runs on them). A server error (the cloud answered "no") is not a network
/// problem, so it's passed on as before.
class OfflineCache {
  OfflineCache(this._prefs, {required this.onReached, required this.onUnreachable});

  final SharedPreferences _prefs;
  final void Function() onReached; // a request got through
  final void Function() onUnreachable; // a request failed for lack of network

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
    try {
      final v = await query().timeout(const Duration(seconds: 20));
      onReached();
      unawaited(_save(key, v));
      return v;
    } on PostgrestException {
      onReached(); // the cloud answered; it's not the network
      rethrow;
    } catch (_) {
      onUnreachable();
      final saved = _prefs.getString('$_prefix$key');
      if (saved == null) rethrow;
      return jsonDecode(saved);
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
