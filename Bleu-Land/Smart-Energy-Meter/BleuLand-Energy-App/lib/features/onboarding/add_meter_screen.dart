import 'dart:async';

import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';
import 'ble_setup.dart';

enum _Step { intro, scan, manual, connecting, wifi, joining, linking, name, error }

/// Add a meter: scan its QR code → send the home WiFi over Bluetooth →
/// link it to this account → give it a name.
class AddMeterScreen extends ConsumerStatefulWidget {
  const AddMeterScreen({super.key});
  @override
  ConsumerState<AddMeterScreen> createState() => _AddMeterScreenState();
}

class _AddMeterScreenState extends ConsumerState<AddMeterScreen> {
  _Step step = _Step.intro;
  MeterCode? code;
  EspProv? prov;
  UniversalBleTransport? transport;
  List<WifiAP> networks = [];
  String status = '';
  String? errorTitle, errorBody;
  _Step retryStep = _Step.intro;
  final nameCtrl = TextEditingController(text: 'My home');
  final idCtrl = TextEditingController();
  final popCtrl = TextEditingController();

  @override
  void dispose() {
    transport?.disconnect();
    super.dispose();
  }

  void _fail(String title, String body, {_Step retry = _Step.intro}) {
    transport?.disconnect();
    if (!mounted) return;
    setState(() {
      errorTitle = title;
      errorBody = body;
      retryStep = retry;
      step = _Step.error;
    });
  }

  // ---------------------------------------------------------------- flow

  Future<void> _gotCode(MeterCode c) async {
    setState(() {
      code = c;
      step = _Step.connecting;
      status = 'Looking for ${c.bleName}…';
    });
    try {
      if (!kIsWeb) await UniversalBle.requestPermissions(withAndroidFineLocation: true);
      final id = await findMeter(c.bleName);
      if (id == null) {
        _fail(
          'Meter not found',
          'Make sure the meter is powered and its blue light blinks slowly (setup mode), and stand within a few metres. '
              'If the light is steady, it is already online: use "It\'s already connected" below.',
          retry: _Step.intro,
        );
        return;
      }
      setState(() => status = 'Connecting securely…');
      transport = UniversalBleTransport(id);
      if (!await transport!.connect()) {
        _fail('Could not connect', 'Bluetooth connection failed. Move closer to the meter and try again.');
        return;
      }
      prov = EspProv(transport: transport!, security: Security1(pop: c.pop));
      final s = await prov!.establishSession();
      if (s == EstablishSessionStatus.keymismatch) {
        _fail('Wrong setup code', 'The code doesn\'t match this meter. Scan the QR code on its label again.');
        return;
      }
      if (s != EstablishSessionStatus.connected) {
        _fail('Connection lost', 'The meter disconnected. Try again.');
        return;
      }
      setState(() => status = 'Looking for WiFi networks near the meter…');
      final list = await prov!.startScanWiFi();
      list.sort((a, b) => b.rssi.compareTo(a.rssi));
      final seen = <String>{};
      setState(() {
        networks = [for (final n in list) if (n.ssid.isNotEmpty && seen.add(n.ssid)) n];
        step = _Step.wifi;
      });
    } catch (e) {
      _fail('Bluetooth problem', 'Turn Bluetooth on, allow the permissions, and try again.\n\n($e)');
    }
  }

  Future<void> _join(String ssid, String password) async {
    setState(() {
      step = _Step.joining;
      status = 'The meter is joining "$ssid"…';
    });
    try {
      await prov!.sendWifiConfig(ssid: ssid, password: password);
      await prov!.applyWifiConfig();
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final st = await prov!.getStatus();
        if (st.state == WifiConnectionState.Connected) {
          await transport?.disconnect();
          await _link();
          return;
        }
        if (st.state == WifiConnectionState.ConnectionFailed) {
          final wrongPw = st.failedReason == WifiConnectFailedReason.AuthError;
          _fail(
            wrongPw ? 'Wrong WiFi password' : 'Network not found',
            wrongPw
                ? 'The meter could not join "$ssid" with that password. Check it and try again.'
                : 'The meter can\'t see "$ssid". It only works with 2.4 GHz WiFi. Move the router closer or pick another network.',
            retry: _Step.intro,
          );
          return;
        }
      }
      _fail('Taking too long', 'The meter didn\'t confirm the connection. Check the router and try again.');
    } catch (e) {
      _fail('Connection lost', 'Bluetooth dropped while sending the WiFi details. Try again.');
    }
  }

  /// Link the meter to this account. Right after joining WiFi the meter
  /// still needs a few seconds to reach the cloud, so we retry for a while.
  Future<void> _link() async {
    final c = code!;
    setState(() {
      step = _Step.linking;
      status = 'Linking the meter to your account…';
    });
    final repo = ref.read(repositoryProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (true) {
      final r = await repo.claim(c.meterId, c.pop, nameCtrl.text.trim());
      switch (r) {
        case ClaimResult.ok:
          if (mounted) setState(() => step = _Step.name);
          return;
        case ClaimResult.wrongCode:
          _fail('Wrong setup code', 'The code doesn\'t match this meter.');
          return;
        case ClaimResult.alreadyClaimed:
          _fail(
            'Already in another account',
            'This meter belongs to someone else. Ask them to remove it, or hold the meter\'s button for 15 seconds to reset it.',
          );
          return;
        case ClaimResult.notOnlineYet:
        case ClaimResult.failed:
          if (DateTime.now().isAfter(deadline)) {
            _fail(
              'The meter isn\'t online yet',
              'It joined your WiFi but hasn\'t reached the internet. Check that the router has internet, then try "It\'s already connected".',
              retry: _Step.manual,
            );
            return;
          }
          await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> _finish() async {
    final c = code!;
    final name = nameCtrl.text.trim();
    final meters = await ref.read(repositoryProvider).meters();
    final m = meters.where((x) => x.id == c.meterId).firstOrNull;
    if (m != null && name.isNotEmpty && name != m.name) {
      await ref.read(repositoryProvider).updateMeter(m.copyWith(name: name));
    }
    ref.read(selectedMeterIdProvider.notifier).select(c.meterId);
    ref.invalidate(metersProvider);
    if (mounted) context.go('/home');
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(demoModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add a meter')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(step), child: demo ? _demoNote() : _body()),
        ),
      ),
    );
  }

  Widget _demoNote() => Center(
        child: EmptyState(
          icon: Icons.science_outlined,
          title: 'You\'re in the demo',
          body: 'Create an account to add your own SEM-1. Your meter\'s data stays private to you and the people you invite.',
          action: FilledButton(
            onPressed: () {
              ref.read(demoModeProvider.notifier).set(false);
              context.go('/auth?mode=signup');
            },
            child: const Text('Create account'),
          ),
        ),
      );

  Widget _body() {
    final t = Theme.of(context).textTheme;
    switch (step) {
      case _Step.intro:
        return _Page(
          icon: Icons.electric_meter_rounded,
          title: 'Let\'s connect your SEM-1',
          body: 'Power the meter on. When its blue WiFi light blinks slowly, it\'s ready. '
              'Keep your phone close to it, with Bluetooth on.',
          children: [
            FilledButton.icon(
              onPressed: () => setState(() => step = _Step.scan),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan the QR code'),
            ),
            const SizedBox(height: S.md),
            OutlinedButton(
              onPressed: () => setState(() => step = _Step.manual),
              child: const Text('Type the code instead'),
            ),
          ],
        );

      case _Step.scan:
        return Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(S.page),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(R.xl),
                child: Stack(fit: StackFit.expand, children: [
                  MobileScanner(
                    onDetect: (cap) {
                      if (step != _Step.scan) return;
                      for (final b in cap.barcodes) {
                        final c = MeterCode.parse(b.rawValue ?? '');
                        if (c != null) {
                          _gotCode(c);
                          return;
                        }
                      }
                    },
                  ),
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(color: C.brand, width: 3),
                        borderRadius: BorderRadius.circular(R.lg),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.page, 0, S.page, S.lg),
            child: Column(children: [
              Text('Point the camera at the "SCAN TO PAIR" code on the front of the meter.',
                  style: t.bodyMedium?.copyWith(color: C.text2), textAlign: TextAlign.center),
              TextButton(onPressed: () => setState(() => step = _Step.manual), child: const Text('Type the code instead')),
            ]),
          ),
        ]);

      case _Step.manual:
        return _Page(
          icon: Icons.keyboard_rounded,
          title: 'Meter ID and setup code',
          body: 'Both are printed under the QR code on the meter\'s label.',
          children: [
            TextField(
              controller: idCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Meter ID', hintText: 'SEM1-8B6204'),
            ),
            const SizedBox(height: S.md),
            TextField(
              controller: popCtrl,
              decoration: const InputDecoration(labelText: 'Setup code', hintText: '8 letters and numbers'),
            ),
            const SizedBox(height: S.xl),
            FilledButton(
              onPressed: () {
                final c = MeterCode.manual(idCtrl.text, popCtrl.text);
                if (c == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the ID and the 8-character code.')));
                  return;
                }
                _gotCode(c);
              },
              child: const Text('Set up WiFi'),
            ),
            const SizedBox(height: S.md),
            OutlinedButton(
              onPressed: () {
                final c = MeterCode.manual(idCtrl.text, popCtrl.text);
                if (c == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the ID and the 8-character code.')));
                  return;
                }
                code = c;
                _link();
              },
              child: const Text('It\'s already connected to WiFi'),
            ),
          ],
        );

      case _Step.connecting:
      case _Step.joining:
      case _Step.linking:
        final n = step == _Step.connecting ? 1 : step == _Step.joining ? 2 : 3;
        return _Page(
          icon: step == _Step.linking ? Icons.cloud_sync_rounded : Icons.bluetooth_searching_rounded,
          title: 'Step $n of 3',
          body: status,
          busy: true,
          children: [_Steps(current: n)],
        );

      case _Step.wifi:
        return ListView(
          padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xl),
          children: [
            _Steps(current: 2),
            const SizedBox(height: S.lg),
            Text('Choose your home WiFi', style: t.headlineSmall),
            const SizedBox(height: S.xs),
            Text('Networks the meter can see. It needs 2.4 GHz WiFi.', style: t.bodyMedium?.copyWith(color: C.text2)),
            const SizedBox(height: S.lg),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < networks.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  ListTile(
                    leading: Icon(_wifiIcon(networks[i].rssi), color: C.text2),
                    title: Text(networks[i].ssid),
                    trailing: networks[i].private ? const Icon(Icons.lock_outline_rounded, size: 18, color: C.text3) : null,
                    onTap: () => _askPassword(networks[i].ssid, networks[i].private),
                  ),
                ],
                if (networks.isEmpty)
                  const ListTile(title: Text('No networks found'), subtitle: Text('Move the meter closer to the router.')),
              ]),
            ),
            TextButton(onPressed: () => _askSsid(), child: const Text('My network isn\'t listed')),
          ],
        );

      case _Step.name:
        return _Page(
          icon: Icons.check_circle_rounded,
          title: 'Your meter is online',
          body: 'Give it a name you\'ll recognise. You can change it later.',
          children: [
            TextField(controller: nameCtrl, maxLength: 40, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: S.lg),
            FilledButton(onPressed: _finish, child: const Text('Done')),
          ],
        );

      case _Step.error:
        return _Page(
          icon: Icons.error_outline_rounded,
          iconColor: C.criticalText,
          title: errorTitle ?? 'Something went wrong',
          body: errorBody ?? '',
          children: [
            FilledButton(onPressed: () => setState(() => step = retryStep), child: const Text('Try again')),
            const SizedBox(height: S.md),
            OutlinedButton(onPressed: () => context.pop(), child: const Text('Cancel')),
          ],
        );
    }
  }

  static IconData _wifiIcon(int rssi) => rssi > -60
      ? Icons.wifi_rounded
      : rssi > -72
          ? Icons.wifi_2_bar_rounded
          : Icons.wifi_1_bar_rounded;

  Future<void> _askPassword(String ssid, bool secured) async {
    if (!secured) return _join(ssid, '');
    final ctrl = TextEditingController();
    var hide = true;
    final pw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(S.xl, 0, S.xl, MediaQuery.of(c).viewInsets.bottom + S.xl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Password for "$ssid"', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: S.lg),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: hide,
              decoration: InputDecoration(
                labelText: 'WiFi password',
                suffixIcon: IconButton(
                  icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => set(() => hide = !hide),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(c, v),
            ),
            const SizedBox(height: S.lg),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Connect')),
          ]),
        ),
      ),
    );
    if (pw != null) await _join(ssid, pw);
  }

  Future<void> _askSsid() async {
    final ctrl = TextEditingController();
    final ssid = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Network name'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'WiFi name (SSID)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Next')),
        ],
      ),
    );
    if (ssid != null && ssid.isNotEmpty) await _askPassword(ssid, true);
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.children = const [],
    this.busy = false,
    this.iconColor = C.brand,
  });
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;
  final bool busy;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.xl),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(S.xl),
                    child: CircularProgressIndicator(strokeWidth: 3, color: iconColor),
                  )
                : Icon(icon, size: 44, color: iconColor),
          ),
        ),
        const SizedBox(height: S.xl),
        Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: S.sm),
        Text(body, style: t.bodyMedium?.copyWith(color: C.text2), textAlign: TextAlign.center),
        const SizedBox(height: S.xxl),
        ...children,
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    const labels = ['Bluetooth', 'WiFi', 'Account'];
    final t = Theme.of(context).textTheme;
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: S.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < current ? C.brand : C.surface2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: S.xs),
            Text(labels[i], style: t.labelSmall?.copyWith(color: i < current ? C.text : C.text3)),
          ]),
        ),
      ],
    ]);
  }
}
