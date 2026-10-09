import 'dart:async';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';
import '../onboarding/ble_setup.dart';
import '../onboarding/setup_widgets.dart';

enum _Step { overview, searching, notFound, needCode, connecting, pick, joining, waiting, done, error }

/// The meter's WiFi: which network it's on, and changing it over Bluetooth.
///
/// Online meter: the cloud tells it to open Bluetooth setup (it restarts,
/// ~20 s). Offline meter (password changed, new router): it opens Bluetooth
/// setup by itself after 2 minutes without WiFi, or when its button is held
/// for 5 s. Either way the old WiFi is kept until a new one works.
class WifiScreen extends ConsumerStatefulWidget {
  const WifiScreen({super.key});
  @override
  ConsumerState<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends ConsumerState<WifiScreen> {
  _Step step = _Step.overview;
  String status = '';
  String? errorTitle, errorBody;
  MeterLink? link;
  MeterCode? code;
  List<WifiAP> networks = [];
  String? newSsid;
  bool wasOnline = false;
  final codeCtrl = TextEditingController();

  @override
  void dispose() {
    link?.close();
    super.dispose();
  }

  void _fail(String title, String body) {
    link?.close();
    link = null;
    if (!mounted) return;
    setState(() {
      errorTitle = title;
      errorBody = body;
      step = _Step.error;
    });
  }

  String _bleName(Meter m) => '${AppConfig.blePrefix}${m.id.substring(5)}';

  // ------------------------------------------------------------ flow

  Future<void> _start(Meter m, {required bool online}) async {
    if (ref.read(demoModeProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not available in the demo.')));
      return;
    }
    wasOnline = online;
    setState(() {
      step = _Step.searching;
      status = online ? 'Asking the meter to open Bluetooth setup…' : 'Looking for the meter nearby…';
    });
    try {
      if (!kIsWeb) await UniversalBle.requestPermissions();
    } catch (e) {
      _fail('Bluetooth problem', 'Turn Bluetooth on, allow the permissions, and try again.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    if (online) {
      try {
        await repo.requestWifiSetup(m.id);
      } catch (_) {
        _fail('Couldn\'t reach the meter', 'Check your internet connection and try again.');
        return;
      }
    }
    final pop = code?.pop ?? await repo.setupCode(m.id);
    if (pop == null) {
      if (mounted) setState(() => step = _Step.needCode);
      return;
    }
    code = MeterCode(bleName: _bleName(m), pop: pop);
    await _connect(findFor: Duration(seconds: online ? 75 : 20));
  }

  Future<void> _connect({Duration findFor = const Duration(seconds: 20)}) async {
    setState(() {
      step = _Step.searching;
      status = wasOnline
          ? 'The meter is restarting into Bluetooth setup. This takes about 20 seconds…'
          : 'Looking for the meter nearby…';
    });
    try {
      final (l, err) = await MeterLink.open(code!, findFor: findFor);
      switch (err) {
        case LinkError.notFound:
          if (mounted) setState(() => step = _Step.notFound);
          return;
        case LinkError.connectFailed:
          _fail('Could not connect', 'Bluetooth connection failed. Move closer to the meter and try again.');
          return;
        case LinkError.wrongCode:
          code = null;
          _fail('Wrong setup code', 'The code doesn\'t match this meter. Check the label and try again.');
          return;
        case LinkError.lost:
          _fail('Connection lost', 'The meter disconnected. Try again.');
          return;
        case null:
      }
      link = l;
      setState(() {
        step = _Step.connecting;
        status = 'Looking for WiFi networks near the meter…';
      });
      final list = await link!.networks();
      if (!mounted) return;
      setState(() {
        networks = list;
        step = _Step.pick;
      });
    } catch (e) {
      _fail('Bluetooth problem', 'Turn Bluetooth on, allow the permissions, and try again.');
    }
  }

  Future<void> _pick(Meter m, String ssid, bool secured) async {
    var pw = '';
    if (secured) {
      final p = await askWifiPassword(context, ssid);
      if (p == null) return;
      pw = p;
    }
    setState(() {
      step = _Step.joining;
      status = 'The meter is joining "$ssid"…';
      newSsid = ssid;
    });
    final r = await link!.join(ssid, pw);
    switch (r) {
      case JoinResult.connected:
        await link?.close();
        link = null;
        await _waitOnline(m, ssid);
      case JoinResult.wrongPassword:
      case JoinResult.notFound:
        // The meter stays in setup mode: pick again without reconnecting.
        final (title, body) = joinFailureText(ssid, r == JoinResult.wrongPassword);
        if (!mounted) return;
        setState(() => step = _Step.pick);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title. $body')));
      case JoinResult.timeout:
        _fail('Taking too long', 'The meter didn\'t confirm the connection. Check the router and try again.');
      case JoinResult.lost:
        _fail('Connection lost', 'Bluetooth dropped while sending the WiFi details. Try again.');
    }
  }

  /// Joined over Bluetooth; now wait until it reports through the cloud.
  Future<void> _waitOnline(Meter m, String ssid) async {
    setState(() {
      step = _Step.waiting;
      status = 'Connected to "$ssid". Waiting for the meter to come back online…';
    });
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final live = ref.read(liveProvider(m.id)).value;
      if (live != null && live.ssid == ssid && DateTime.now().difference(live.ts) < const Duration(seconds: 20)) {
        setState(() => step = _Step.done);
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!mounted) return;
    _fail(
      'Joined "$ssid", but no internet yet',
      'The meter is on the new WiFi but hasn\'t reached the cloud. If the router has internet, it will show up '
          'within a minute or two. If the router has no internet, the meter keeps measuring and uploads later.',
    );
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final meter = ref.watch(currentMeterProvider).value;
    if (meter == null) return const Scaffold(body: SizedBox());
    final live = ref.watch(liveProvider(meter.id)).value;
    final online = live != null && DateTime.now().difference(live.ts) < AppConfig.offlineAfter;
    return Scaffold(
      appBar: AppBar(title: const Text('Meter WiFi')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(step), child: _body(meter, live, online)),
        ),
      ),
    );
  }

  Widget _body(Meter m, LiveReading? live, bool online) {
    final t = Theme.of(context).textTheme;
    switch (step) {
      case _Step.overview:
        return _Overview(
          meter: m,
          live: live,
          online: online,
          onChange: () => _start(m, online: online),
        );

      case _Step.searching:
      case _Step.connecting:
      case _Step.joining:
      case _Step.waiting:
        return SetupPage(
          icon: Icons.bluetooth_searching_rounded,
          title: switch (step) {
            _Step.searching => 'Finding the meter',
            _Step.connecting => 'Connected',
            _Step.joining => 'Joining the new WiFi',
            _ => 'Almost done',
          },
          body: status,
          busy: true,
          children: [
            Text('Keep your phone near the meter with Bluetooth on.',
                style: t.bodySmall?.copyWith(color: C.text3), textAlign: TextAlign.center),
          ],
        );

      case _Step.notFound:
        return SetupPage(
          icon: Icons.bluetooth_disabled_rounded,
          iconColor: C.warning,
          title: 'The meter isn\'t in setup mode yet',
          body: 'When it can\'t reach its WiFi for 2 minutes, the meter opens Bluetooth setup by itself and its blue '
              'light blinks slowly. To open it now, hold the meter\'s button for 5 seconds.\n\n'
              'Its current WiFi is kept until a new one works, so nothing is lost.',
          children: [
            FilledButton.icon(
              onPressed: () => _connect(findFor: const Duration(seconds: 60)),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search again'),
            ),
            const SizedBox(height: S.md),
            OutlinedButton(onPressed: () => setState(() => step = _Step.overview), child: const Text('Back')),
          ],
        );

      case _Step.needCode:
        return SetupPage(
          icon: Icons.keyboard_rounded,
          title: 'Setup code',
          body: 'Type the 8-character code printed under the QR code on the meter\'s label. You only need it once.',
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Setup code', hintText: '8 letters and numbers'),
            ),
            const SizedBox(height: S.xl),
            FilledButton(
              onPressed: () {
                final c = MeterCode.manual(m.id, codeCtrl.text);
                if (c == null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('The code has 8 letters and numbers.')));
                  return;
                }
                code = c;
                _connect(findFor: Duration(seconds: wasOnline ? 75 : 20));
              },
              child: const Text('Continue'),
            ),
          ],
        );

      case _Step.pick:
        return ListView(
          padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xl),
          children: [
            Text('Choose the WiFi', style: t.headlineSmall),
            const SizedBox(height: S.xs),
            Text('Networks the meter can see. It needs 2.4 GHz WiFi.', style: t.bodyMedium?.copyWith(color: C.text2)),
            const SizedBox(height: S.lg),
            WifiNetworkList(networks: networks, current: live?.ssid, onPick: (s, secured) => _pick(m, s, secured)),
          ],
        );

      case _Step.done:
        return SetupPage(
          icon: Icons.check_circle_rounded,
          iconColor: C.goodText,
          title: 'Back online',
          body: 'The meter is now on "${newSsid ?? ''}" and reporting again.',
          children: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
        );

      case _Step.error:
        return SetupPage(
          icon: Icons.error_outline_rounded,
          iconColor: C.criticalText,
          title: errorTitle ?? 'Something went wrong',
          body: '${errorBody ?? ''}\n\nIf nothing changes, the meter goes back to its previous WiFi by itself.',
          children: [
            FilledButton(onPressed: () => setState(() => step = _Step.overview), child: const Text('Try again')),
          ],
        );
    }
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.meter, required this.live, required this.online, required this.onChange});
  final Meter meter;
  final LiveReading? live;
  final bool online;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = live;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
      children: [
        Panel(
          child: Row(children: [
            Icon(online ? wifiIcon(l?.rssi ?? -50) : Icons.wifi_off_rounded, color: online ? C.brand : C.criticalText, size: 28),
            const SizedBox(width: S.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  online ? (l?.ssid ?? 'Connected') : 'Not connected',
                  style: t.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  online
                      ? 'Signal ${_signal(l?.rssi)}'
                      : l == null
                          ? 'The meter hasn\'t reported yet'
                          : 'Last seen ${fmtAgo(l.ts)}${l.ssid != null ? ' on "${l.ssid}"' : ''}',
                  style: t.bodySmall?.copyWith(color: C.text2),
                ),
              ]),
            ),
            online
                ? const StatusPill(kind: PillKind.live, label: 'Online')
                : const StatusPill(kind: PillKind.offline, label: 'Offline'),
          ]),
        ),
        const SizedBox(height: S.md),
        if (!online)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Why is it offline?', style: t.titleSmall),
              const SizedBox(height: S.md),
              const _Reason(
                icon: Icons.router_outlined,
                title: 'Router off, or no internet',
                body: 'Nothing to do. The meter keeps measuring, reconnects by itself, and uploads what it recorded.',
              ),
              const _Reason(
                icon: Icons.password_rounded,
                title: 'WiFi password or router changed',
                body: 'Fix it below. After 2 minutes without WiFi the meter opens Bluetooth setup by itself.',
              ),
              const _Reason(
                icon: Icons.power_off_rounded,
                title: 'Power cut',
                body: 'It comes back by itself when the electricity does.',
              ),
            ]),
          ),
        if (!online) const SizedBox(height: S.md),
        if (meter.isOwner) ...[
          FilledButton.icon(
            onPressed: onChange,
            icon: const Icon(Icons.bluetooth_rounded),
            label: Text(online ? 'Change WiFi network' : 'Fix the WiFi over Bluetooth'),
          ),
          const SizedBox(height: S.md),
          Text(
            'Stand near the meter with Bluetooth on. The meter keeps its current WiFi until the new one works.',
            style: t.bodySmall?.copyWith(color: C.text3),
            textAlign: TextAlign.center,
          ),
        ] else
          Text('Only the meter\'s owner can change its WiFi.', style: t.bodySmall?.copyWith(color: C.text2)),
      ],
    );
  }

  static String _signal(int? rssi) => rssi == null
      ? 'unknown'
      : rssi > -60
          ? 'excellent'
          : rssi > -70
              ? 'good'
              : rssi > -80
                  ? 'fair'
                  : 'weak';
}

class _Reason extends StatelessWidget {
  const _Reason({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: C.text2),
        const SizedBox(width: S.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.bodyMedium),
            Text(body, style: t.bodySmall?.copyWith(color: C.text2)),
          ]),
        ),
      ]),
    );
  }
}
