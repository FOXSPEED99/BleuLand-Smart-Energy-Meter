import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final meter = ref.watch(currentMeterProvider).value;
    if (meter == null) return const Scaffold(body: Center(child: Text('Add a meter to get alerts.')));
    final alerts = ref.watch(alertsProvider(meter.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: RefreshIndicator(
        color: C.brand,
        onRefresh: () async => ref.invalidate(alertsProvider(meter.id)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
          children: [
            _AlertSettings(meter: meter),
            const SectionHeader('Recent'),
            alerts.when(
              loading: () => const LoadingPanel(),
              error: (e, _) => ErrorPanel(message: 'Could not load alerts.', onRetry: () => ref.invalidate(alertsProvider(meter.id))),
              data: (list) => list.isEmpty
                  ? Panel(
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded, color: C.series),
                        const SizedBox(width: S.md),
                        Expanded(child: Text('All quiet. Nothing unusual so far.', style: t.bodyMedium)),
                      ]),
                    )
                  : Panel(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(indent: 64),
                          _AlertTile(a: list[i]),
                        ],
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.a});
  final AlertItem a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (icon, color, title) = switch (a.kind) {
      AlertKind.highPower => (Icons.bolt_rounded, C.warning, 'High usage · ${fmtPowerText(a.value ?? 0)}'),
      AlertKind.offline => (Icons.power_off_rounded, C.criticalText, 'Meter offline'),
    };
    final when = DateFormat('EEE d MMM, HH:mm').format(a.createdAt);
    final dur = a.resolvedAt?.difference(a.createdAt);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xs),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: t.titleSmall),
      subtitle: Text(
        a.active ? '$when · still going' : '$when · lasted ${_dur(dur!)}',
        style: t.bodySmall?.copyWith(color: C.text2),
      ),
      trailing: a.active ? const StatusPill(kind: PillKind.stale, label: 'Active') : null,
    );
  }

  static String _dur(Duration d) {
    if (d.inMinutes < 1) return 'under a minute';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
}

class _AlertSettings extends ConsumerWidget {
  const _AlertSettings({required this.meter});
  final Meter meter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final on = meter.alertPowerW != null;
    final threshold = (meter.alertPowerW ?? 3000).toDouble();

    Future<void> save(Meter m) async {
      await ref.read(repositoryProvider).updateMeter(m);
      ref.invalidate(metersProvider);
    }

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt_rounded, color: C.warning, size: 20),
          const SizedBox(width: S.sm),
          Expanded(child: Text('High usage alert', style: t.titleSmall)),
          Switch(
            value: on,
            onChanged: meter.isOwner
                ? (v) => save(v ? meter.copyWith(alertPowerW: threshold.round()) : meter.copyWith(clearAlertPower: true))
                : null,
          ),
        ]),
        Text(
          on
              ? 'Alert when the house uses more than ${fmtPowerText(threshold)}.'
              : 'Get warned when usage goes above a limit you choose.',
          style: t.bodySmall?.copyWith(color: C.text2),
        ),
        if (on && meter.isOwner)
          _ThresholdSlider(
            initial: threshold,
            onDone: (v) => save(meter.copyWith(alertPowerW: v.round())),
          ),
        const SizedBox(height: S.md),
        const Divider(),
        const SizedBox(height: S.md),
        Row(children: [
          const Icon(Icons.power_off_rounded, color: C.criticalText, size: 20),
          const SizedBox(width: S.sm),
          Expanded(child: Text('Offline alert', style: t.titleSmall)),
          Text('after ${meter.alertOfflineMin} min', style: t.labelMedium?.copyWith(color: C.text2)),
        ]),
        const SizedBox(height: S.xs),
        Text(
          'Shows when the meter stops reporting: usually a power cut, or the home internet is down.',
          style: t.bodySmall?.copyWith(color: C.text2),
        ),
      ]),
    );
  }
}

class _ThresholdSlider extends StatefulWidget {
  const _ThresholdSlider({required this.initial, required this.onDone});
  final double initial;
  final ValueChanged<double> onDone;
  @override
  State<_ThresholdSlider> createState() => _ThresholdSliderState();
}

class _ThresholdSliderState extends State<_ThresholdSlider> {
  late double v = widget.initial.clamp(500, 10000);

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Slider(
            value: v,
            min: 500,
            max: 10000,
            divisions: 38,
            label: fmtPowerText(v),
            activeColor: C.brand,
            inactiveColor: C.surface2,
            onChanged: (x) => setState(() => v = x),
            onChangeEnd: widget.onDone,
          ),
        ),
        SizedBox(width: 72, child: Text(fmtPowerText(v), textAlign: TextAlign.right)),
      ]);
}
