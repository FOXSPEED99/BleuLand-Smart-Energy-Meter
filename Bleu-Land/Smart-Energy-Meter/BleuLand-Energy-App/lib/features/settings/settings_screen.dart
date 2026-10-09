import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final meter = ref.watch(currentMeterProvider).value;
    final demo = ref.watch(demoModeProvider);
    final email = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
        children: [
          if (meter != null) ...[
            _MeterHeader(meter: meter),
            const SectionHeader('Meter'),
            _Group(children: [
              _Row(
                icon: Icons.edit_rounded,
                title: 'Name',
                value: meter.name,
                onTap: meter.isOwner ? () => _rename(context, ref, meter) : null,
              ),
              _Row(
                icon: Icons.receipt_long_rounded,
                title: 'Electricity price',
                value: meter.tariff.isSet ? _tariffSummary(meter) : 'Not set',
                onTap: meter.isOwner ? () => context.push('/settings/tariff') : null,
              ),
              _Row(
                icon: Icons.group_rounded,
                title: 'Share with family',
                value: meter.isOwner ? 'Invite by e-mail' : 'Shared with you',
                onTap: meter.isOwner ? () => context.push('/settings/sharing') : null,
              ),
              _FirmwareRow(meter: meter),
            ]),
          ],
          const SectionHeader('Meters'),
          _Group(children: [
            _Row(icon: Icons.add_circle_outline_rounded, title: 'Add a meter', onTap: () => context.push('/add-meter')),
          ]),
          const SectionHeader('Account'),
          _Group(children: [
            if (demo)
              _Row(
                icon: Icons.science_outlined,
                title: 'Demo mode',
                value: 'Simulated home',
                onTap: null,
              )
            else
              _Row(icon: Icons.person_rounded, title: 'Signed in', value: email ?? ''),
            _Row(
              icon: Icons.logout_rounded,
              title: demo ? 'Leave the demo' : 'Sign out',
              danger: true,
              onTap: () async {
                if (demo) {
                  ref.read(demoModeProvider.notifier).set(false);
                } else {
                  await Supabase.instance.client.auth.signOut();
                }
                if (context.mounted) context.go('/welcome');
              },
            ),
          ]),
          const SizedBox(height: S.xl),
          Center(
            child: Text('${AppConfig.appName} · version 1.0.0', style: t.labelSmall?.copyWith(color: C.text3)),
          ),
        ],
      ),
    );
  }

  static String _tariffSummary(Meter m) {
    final tiers = m.tariff.tiers;
    final p = tiers.map((x) => _n(x.price)).join(' → ');
    final per = m.tariff.periodMonths == 1 ? 'monthly' : 'every ${m.tariff.periodMonths} months';
    return '$p ${m.currency}/kWh, $per';
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _rename(BuildContext context, WidgetRef ref, Meter meter) async {
    final ctrl = TextEditingController(text: meter.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Meter name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'e.g. Home, Shop, Parents'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == meter.name) return;
    await ref.read(repositoryProvider).updateMeter(meter.copyWith(name: name));
    ref.invalidate(metersProvider);
  }
}

class _MeterHeader extends ConsumerWidget {
  const _MeterHeader({required this.meter});
  final Meter meter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final live = ref.watch(liveProvider(meter.id)).value;
    final online = live != null && DateTime.now().difference(live.ts) < AppConfig.offlineAfter;
    return Panel(
      child: Row(children: [
        const BrandMark(size: 52),
        const SizedBox(width: S.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SEM-1 · ${meter.id}', style: t.titleSmall),
            const SizedBox(height: 2),
            Text(
              [
                if (meter.fw != null) 'Firmware ${meter.fw}',
                if (live?.rssi != null) 'WiFi ${_signal(live!.rssi!)}',
              ].join(' · '),
              style: t.bodySmall?.copyWith(color: C.text2),
            ),
            const SizedBox(height: S.sm),
            online
                ? const StatusPill(kind: PillKind.live, label: 'Online')
                : StatusPill(kind: PillKind.offline, label: live == null ? 'Not reporting yet' : 'Offline · ${fmtAgo(live.ts)}'),
          ]),
        ),
      ]),
    );
  }

  static String _signal(int rssi) => rssi > -60 ? 'excellent' : rssi > -70 ? 'good' : rssi > -80 ? 'fair' : 'weak';
}

/// "Firmware 0.3.0 · up to date", or a highlighted "update available".
class _FirmwareRow extends ConsumerWidget {
  const _FirmwareRow({required this.meter});
  final Meter meter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final s = ref.watch(firmwareProvider(meter.id)).value;
    final current = s?.current ?? meter.fw ?? '–';
    final (String value, bool attention) = s == null
        ? (current, false)
        : s.updating
            ? ('Updating to ${s.target}…', true)
            : s.latest != null
                ? ('$current · version ${s.latest!.version} available', true)
                : ('$current · up to date', false);
    return ListTile(
      onTap: () => context.push('/settings/firmware'),
      leading: Badge(
        isLabelVisible: attention,
        backgroundColor: C.brand,
        smallSize: 8,
        child: const Icon(Icons.memory_rounded, color: C.text2),
      ),
      title: Text('Firmware', style: t.bodyLarge),
      subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: attention ? TextStyle(color: C.brand) : null),
      trailing: const Icon(Icons.chevron_right_rounded, color: C.text3),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            children[i],
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.value, this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: danger ? C.criticalText : C.text2),
      title: Text(title, style: t.bodyLarge?.copyWith(color: danger ? C.criticalText : C.text)),
      subtitle: value == null || value!.isEmpty ? null : Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: onTap != null && !danger ? const Icon(Icons.chevron_right_rounded, color: C.text3) : null,
    );
  }
}
