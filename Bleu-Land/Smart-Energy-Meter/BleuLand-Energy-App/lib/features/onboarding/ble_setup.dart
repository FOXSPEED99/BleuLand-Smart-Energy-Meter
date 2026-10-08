// Talking to an SEM-1 in setup mode over Bluetooth LE.
//
// The meter runs Espressif's standard WiFi provisioning service. Each of its
// "endpoints" (session, scan, config ...) is a GATT characteristic whose
// name is stored in a User Description descriptor (0x2901). We look them up
// by name, so firmware that adds or reorders endpoints keeps working.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../core/config.dart';

const provService = '021a9004-0382-4aea-bff4-6b3f1c5adfb4';
const _userDescription = '00002901-0000-1000-8000-00805f9b34fb';

/// Data from the QR code on the front label:
/// {"ver":"v1","name":"SEM1_8B6204","pop":"e528hunu","transport":"ble"}
class MeterCode {
  const MeterCode({required this.bleName, required this.pop});
  final String bleName; // SEM1_8B6204
  final String pop; // 8-character setup code

  String get meterId => bleName.replaceFirst('_', '-'); // SEM1-8B6204

  static MeterCode? parse(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final name = j['name'] as String?;
      final pop = j['pop'] as String?;
      if (name == null || pop == null || !name.startsWith(AppConfig.blePrefix) || pop.length != 8) return null;
      return MeterCode(bleName: name, pop: pop);
    } catch (_) {
      return null;
    }
  }

  /// Typed by hand: "SEM1-8B6204" (or "8B6204") + the code.
  static MeterCode? manual(String id, String pop) {
    final m = RegExp(r'^(?:SEM1[-_])?([0-9A-Fa-f]{6})$').firstMatch(id.trim());
    final p = pop.trim().toLowerCase();
    if (m == null || p.length != 8) return null;
    return MeterCode(bleName: '${AppConfig.blePrefix}${m.group(1)!.toUpperCase()}', pop: p);
  }
}

class UniversalBleTransport implements ProvTransport {
  UniversalBleTransport(this.deviceId);
  final String deviceId;
  final Map<String, String> _chars = {}; // endpoint name -> characteristic uuid

  // Espressif's default numbering, used only if descriptors can't be read.
  static const _fallback = {
    'prov-scan': 'ff50',
    'prov-session': 'ff51',
    'prov-config': 'ff52',
    'proto-ver': 'ff53',
  };

  @override
  Future<bool> connect() async {
    try {
      await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
    } catch (_) {
      return false;
    }
    try {
      await UniversalBle.requestMtu(deviceId, 256);
    } catch (_) {/* not supported everywhere; the default works too */}

    final services = await UniversalBle.discoverServices(deviceId, withDescriptors: true);
    final svc = services.where((s) => s.uuid.toLowerCase() == provService).firstOrNull;
    if (svc == null) return false;
    for (final c in svc.characteristics) {
      final hasDesc = c.descriptors.any((d) => d.uuid.toLowerCase() == _userDescription);
      if (!hasDesc) continue;
      try {
        final raw = await UniversalBle.readDescriptor(deviceId, provService, c.uuid, _userDescription);
        final name = utf8.decode(raw, allowMalformed: true).replaceAll('\u0000', '').trim();
        if (name.isNotEmpty) _chars[name] = c.uuid;
      } catch (_) {}
    }
    if (!_chars.containsKey('prov-session')) {
      for (final e in _fallback.entries) {
        _chars[e.key] = '${provService.substring(0, 4)}${e.value}${provService.substring(8)}';
      }
    }
    return true;
  }

  @override
  Future<bool> checkConnect() async =>
      await UniversalBle.getConnectionState(deviceId) == BleConnectionState.connected;

  @override
  Future<bool> disconnect() async {
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {}
    return true;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    final c = _chars[epName];
    if (c == null) throw StateError('The meter has no "$epName" endpoint');
    if (data.isNotEmpty) await UniversalBle.write(deviceId, provService, c, data);
    return UniversalBle.read(deviceId, provService, c);
  }
}

/// Finds the meter advertising [bleName]. Returns its BLE device id, or null
/// after [timeout] (meter not in setup mode, too far away, Bluetooth off).
Future<String?> findMeter(String bleName, {Duration timeout = const Duration(seconds: 15)}) async {
  final done = Completer<String?>();
  UniversalBle.onScanResult = (d) {
    if ((d.name ?? '') == bleName && !done.isCompleted) done.complete(d.deviceId);
  };
  await UniversalBle.startScan(
    scanFilter: ScanFilter(withNamePrefix: [AppConfig.blePrefix]),
    platformConfig: PlatformConfig(web: WebOptions(optionalServices: [provService])),
  );
  final id = await done.future.timeout(timeout, onTimeout: () => null);
  UniversalBle.onScanResult = null;
  try {
    await UniversalBle.stopScan();
  } catch (_) {}
  return id;
}
