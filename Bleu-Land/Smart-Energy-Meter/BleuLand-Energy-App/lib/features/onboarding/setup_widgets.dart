// Pieces shared by "Add a meter" and "Change WiFi".
import 'package:esp_provisioning_ble/esp_provisioning_ble.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// A centred step: big icon (or spinner), title, text, then actions.
class SetupPage extends StatelessWidget {
  const SetupPage({
    super.key,
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

IconData wifiIcon(int rssi) => rssi > -60
    ? Icons.wifi_rounded
    : rssi > -72
        ? Icons.wifi_2_bar_rounded
        : Icons.wifi_1_bar_rounded;

/// The networks the meter can see; tap one to type its password.
class WifiNetworkList extends StatelessWidget {
  const WifiNetworkList({super.key, required this.networks, required this.onPick, this.current});
  final List<WifiAP> networks;
  final void Function(String ssid, bool secured) onPick;
  final String? current; // the network it's on now, marked

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < networks.length; i++) ...[
              if (i > 0) const Divider(indent: 56),
              ListTile(
                leading: Icon(wifiIcon(networks[i].rssi), color: C.text2),
                title: Text(networks[i].ssid),
                subtitle: networks[i].ssid == current ? const Text('Current network') : null,
                trailing: networks[i].private ? const Icon(Icons.lock_outline_rounded, size: 18, color: C.text3) : null,
                onTap: () => onPick(networks[i].ssid, networks[i].private),
              ),
            ],
            if (networks.isEmpty)
              const ListTile(title: Text('No networks found'), subtitle: Text('Move the meter closer to the router.')),
          ]),
        ),
        TextButton(
          onPressed: () async {
            final ssid = await askHiddenSsid(context);
            if (ssid != null) onPick(ssid, true);
          },
          child: const Text('My network isn\'t listed'),
        ),
      ]);
}

Future<String?> askWifiPassword(BuildContext context, String ssid) {
  final ctrl = TextEditingController();
  var hide = true;
  return showModalBottomSheet<String>(
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
}

Future<String?> askHiddenSsid(BuildContext context) async {
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
  return ssid == null || ssid.isEmpty ? null : ssid;
}

/// Plain-words result of sending WiFi details to the meter.
(String, String) joinFailureText(String ssid, bool wrongPassword) => wrongPassword
    ? ('Wrong WiFi password', 'The meter could not join "$ssid" with that password. Check it and try again.')
    : (
        'Network not found',
        'The meter can\'t see "$ssid". It only works with 2.4 GHz WiFi. Move the router closer or pick another network.'
      );
