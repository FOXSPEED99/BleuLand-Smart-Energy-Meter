import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide Bucket;

import '../core/tariff.dart';
import 'models.dart';
import 'repository.dart';

/// Real data from the BleuLand Energy cloud. Row-level security on the server
/// makes sure a user only ever receives meters they own or that were shared.
class SupabaseRepository implements EnergyRepository {
  SupabaseRepository(this._db);
  final SupabaseClient _db;

  @override
  bool get isDemo => false;

  String get _uid => _db.auth.currentUser!.id;

  @override
  Future<List<Meter>> meters() async {
    final rows = await _db
        .from('device_members')
        .select('role, devices(*)')
        .eq('user_id', _uid)
        .order('added_at');
    return [
      for (final r in rows)
        if (r['devices'] != null) _meterFrom(Map<String, dynamic>.from(r['devices'] as Map), r['role'] as String),
    ];
  }

  Meter _meterFrom(Map<String, dynamic> d, String role) => Meter(
        id: d['id'] as String,
        name: d['name'] as String,
        role: role,
        fw: d['fw'] as String?,
        lastSeen: _ts(d['last_seen']),
        timezone: d['timezone'] as String? ?? 'Asia/Damascus',
        currency: d['currency'] as String? ?? 'SYP',
        tariff: Tariff.fromJson(d['tariff'] == null ? null : Map<String, dynamic>.from(d['tariff'] as Map)),
        billingDay: (d['billing_day'] as num?)?.toInt() ?? 1,
        alertPowerW: (d['alert_power_w'] as num?)?.toInt(),
        alertOfflineMin: (d['alert_offline_min'] as num?)?.toInt() ?? 15,
      );

  static DateTime? _ts(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  LiveReading _liveFrom(Map<String, dynamic> r) => LiveReading(
        ts: _ts(r['ts'])!,
        watts: _d(r['p']),
        volts: _d(r['v']),
        amps: _d(r['i']),
        pf: _d(r['pf']),
        kwhTotal: _d(r['kwh']),
        rssi: (r['rssi'] as num?)?.toInt(),
      );

  /// Current row, then every change pushed by the cloud (about every 10 s).
  @override
  Stream<LiveReading?> live(String meterId) {
    late final StreamController<LiveReading?> ctrl;
    RealtimeChannel? channel;
    ctrl = StreamController<LiveReading?>(
      onListen: () async {
        try {
          final row = await _db.from('device_live').select().eq('device_id', meterId).maybeSingle();
          ctrl.add(row == null ? null : _liveFrom(row));
        } catch (e) {
          ctrl.addError(e);
        }
        channel = _db
            .channel('live-$meterId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'device_live',
              filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'device_id', value: meterId),
              callback: (p) {
                if (p.newRecord.isNotEmpty) ctrl.add(_liveFrom(p.newRecord));
              },
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) await _db.removeChannel(channel!);
      },
    );
    return ctrl.stream;
  }

  @override
  Future<List<EnergyPoint>> energy(String meterId, DateTime from, DateTime to, Bucket bucket) async {
    final rows = await _db.rpc('get_energy', params: {
      'p_id': meterId,
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
      'p_bucket': bucket.name,
    }) as List;
    return [for (final r in rows) EnergyPoint(_ts(r['bucket'])!, _d(r['kwh']))];
  }

  @override
  Future<List<PowerPoint>> power(String meterId, DateTime from) async {
    final rows = await _db
        .from('readings')
        .select('ts, p_avg, p_max')
        .eq('device_id', meterId)
        .gte('ts', from.toUtc().toIso8601String())
        .order('ts');
    return [for (final r in rows) PowerPoint(_ts(r['ts'])!, _d(r['p_avg']), _d(r['p_max']))];
  }

  @override
  Future<List<AlertItem>> alerts(String meterId) async {
    final rows = await _db
        .from('alerts')
        .select()
        .eq('device_id', meterId)
        .order('created_at', ascending: false)
        .limit(50);
    return [
      for (final r in rows)
        AlertItem(
          id: (r['id'] as num).toInt(),
          kind: r['kind'] == 'offline' ? AlertKind.offline : AlertKind.highPower,
          value: (r['value'] as num?)?.toDouble(),
          createdAt: _ts(r['created_at'])!,
          resolvedAt: _ts(r['resolved_at']),
        ),
    ];
  }

  @override
  Future<void> updateMeter(Meter m) async {
    await _db.from('devices').update({
      'name': m.name,
      'currency': m.currency,
      'tariff': m.tariff.toJson(),
      'billing_day': m.billingDay,
      'alert_power_w': m.alertPowerW,
      'alert_offline_min': m.alertOfflineMin,
    }).eq('id', m.id);
  }

  @override
  Future<ClaimResult> claim(String meterId, String pop, String name) async {
    try {
      final res = await _db.rpc('claim_device', params: {'p_id': meterId, 'p_pop': pop, 'p_name': name});
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] == true) return ClaimResult.ok;
      return switch (map['error']) {
        'wrong_code' => ClaimResult.wrongCode,
        'not_online_yet' => ClaimResult.notOnlineYet,
        'already_claimed' => ClaimResult.alreadyClaimed,
        _ => ClaimResult.failed,
      };
    } catch (_) {
      return ClaimResult.failed;
    }
  }

  @override
  Future<List<Invite>> invites(String meterId) async {
    final rows = await _db.from('invites').select().eq('device_id', meterId).order('created_at');
    return [
      for (final r in rows)
        Invite(
          id: r['id'] as String,
          email: r['email'] as String,
          createdAt: _ts(r['created_at'])!,
          acceptedAt: _ts(r['accepted_at']),
        ),
    ];
  }

  @override
  Future<int> memberCount(String meterId) async {
    final rows = await _db.from('device_members').select('user_id').eq('device_id', meterId);
    return rows.length;
  }

  @override
  Future<void> invite(String meterId, String email) async {
    await _db.from('invites').insert({'device_id': meterId, 'email': email.trim().toLowerCase(), 'invited_by': _uid});
  }

  @override
  Future<void> cancelInvite(String inviteId) async {
    await _db.from('invites').delete().eq('id', inviteId);
  }
}
