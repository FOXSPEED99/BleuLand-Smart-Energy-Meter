import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts.dart';
import '../../widgets/ui.dart';
import 'bill_card.dart';
import 'live_card.dart';
import 'voltage_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meterAsync = ref.watch(currentMeterProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: meterAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(S.page),
            child: ErrorPanel(
              message:
                  'Could not load your meters. Check your internet connection.',
              onRetry: () => ref.invalidate(metersProvider),
            ),
          ),
          data: (meter) =>
              meter == null ? const _NoMeter() : _Dashboard(meter: meter),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerStatefulWidget {
  const _Dashboard({required this.meter});
  final Meter meter;

  @override
  ConsumerState<_Dashboard> createState() => _DashboardState();
}

/// While Home is on screen and the app is in the foreground, tell the cloud
/// every 25 s that someone is watching: the meter then reports every 2 s.
class _DashboardState extends ConsumerState<_Dashboard>
    with WidgetsBindingObserver {
  Timer? _beat;
  bool _foreground = true;
  bool _visible = true;

  Meter get meter => widget.meter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // other bottom tabs keep Home alive but switch its tickers off
    _visible = TickerMode.valuesOf(context).enabled;
    _updateBeat();
  }

  @override
  void didUpdateWidget(_Dashboard old) {
    super.didUpdateWidget(old);
    if (old.meter.id != meter.id) {
      _beat?.cancel();
      _beat = null;
      _updateBeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _foreground = s == AppLifecycleState.resumed;
    _updateBeat();
  }

  void _updateBeat() {
    final want = _visible && _foreground;
    if (want && _beat == null) {
      _ping();
      _beat = Timer.periodic(const Duration(seconds: 25), (_) => _ping());
    } else if (!want && _beat != null) {
      _beat!.cancel();
      _beat = null;
    }
  }

  void _ping() => ref.read(repositoryProvider).watch(meter.id);

  @override
  void dispose() {
    _beat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final live = ref.watch(liveProvider(meter.id));
    final cycle = ref.watch(cycleProvider(meter.id));
    final power = ref.watch(power24hProvider(meter.id));
    final demo = ref.watch(demoModeProvider);

    return RefreshIndicator(
      color: C.brand,
      backgroundColor: C.surface2,
      onRefresh: () async {
        ref.invalidate(cycleProvider(meter.id));
        ref.invalidate(power24hProvider(meter.id));
        await ref.read(cycleProvider(meter.id).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.md, S.page, S.xxl),
        children: [
          _Header(meter: meter, demo: demo),
          const SizedBox(height: S.lg),
          LiveCard(
            reading: live.value,
            meter: meter,
            loading: live.isLoading && !live.hasValue,
          ),
          const SizedBox(height: S.md),
          // hides itself while the meter is offline (and adds its own spacing)
          VoltageCard(reading: live.value, meter: meter),
          cycle.when(
            loading: () => const LoadingPanel(height: 220),
            error: (e, _) => ErrorPanel(
              message: 'Could not load this bill.',
              onRetry: () => ref.invalidate(cycleProvider(meter.id)),
            ),
            data: (c) => Column(
              children: [
                BillCard(
                  meter: meter,
                  cycle: c,
                  onEditTariff: meter.isOwner
                      ? () => context.push('/settings/tariff')
                      : null,
                ),
                const SizedBox(height: S.md),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.today_rounded,
                        label: 'Today',
                        value: fmtKwh(c.todayKwh, unit: false),
                        unit: 'kWh',
                        sub: c.yesterdayKwh > 0.05
                            ? DeltaText(
                                fraction: _sameTimeDelta(c),
                                versus: 'yesterday',
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: S.md),
                    Expanded(
                      child: StatTile(
                        icon: Icons.payments_outlined,
                        label: 'Today costs',
                        value: fmtMoney(c.todayCost, '').trim(),
                        unit: meter.currency,
                        sub: Text(
                          'at ${_price(c.tier.price)} ${meter.currency}/kWh',
                          style: t.labelSmall?.copyWith(color: C.text2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SectionHeader(
            'Last 24 hours',
            trailing: TextButton(
              onPressed: () => context.go('/history'),
              child: const Text('History'),
            ),
          ),
          Panel(
            padding: const EdgeInsets.fromLTRB(S.sm, S.lg, S.lg, S.sm),
            child: power.when(
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => const SizedBox(
                height: 180,
                child: Center(child: Text('Could not load the chart')),
              ),
              data: (pts) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: S.sm, bottom: S.md),
                    child: Text(
                      'Power, kW',
                      style: t.labelMedium?.copyWith(color: C.text2),
                    ),
                  ),
                  PowerAreaChart(points: pts),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Today so far vs the same share of yesterday (fair comparison mid-day).
  static double _sameTimeDelta(CycleSummary c) {
    final now = DateTime.now();
    final share = (now.hour * 60 + now.minute) / (24 * 60);
    final y = c.yesterdayKwh * share;
    return y <= 0 ? 0 : (c.todayKwh - y) / y;
  }

  static String _price(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _Header extends ConsumerWidget {
  const _Header({required this.meter, required this.demo});
  final Meter meter;
  final bool demo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final meters = ref.watch(metersProvider).value ?? const [];
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: meters.length > 1
                ? () => _pickMeter(context, ref, meters)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(),
                    style: t.bodySmall?.copyWith(color: C.text2),
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          meter.name,
                          style: t.headlineSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (meters.length > 1)
                        const Icon(Icons.expand_more_rounded, color: C.text2),
                      if (demo) ...[
                        const SizedBox(width: S.sm),
                        const StatusPill(kind: PillKind.info, label: 'Demo'),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Add a meter',
          style: IconButton.styleFrom(
            backgroundColor: C.surface,
            foregroundColor: C.text,
          ),
          onPressed: () => context.push('/add-meter'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _pickMeter(BuildContext context, WidgetRef ref, List<Meter> meters) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in meters)
              ListTile(
                leading: const Icon(Icons.home_rounded),
                title: Text(m.name),
                subtitle: Text(m.isOwner ? m.id : '${m.id} · shared with you'),
                trailing: m.id == meter.id
                    ? const Icon(Icons.check_rounded, color: C.brand)
                    : null,
                onTap: () {
                  ref.read(selectedMeterIdProvider.notifier).select(m.id);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: S.md),
          ],
        ),
      ),
    );
  }
}

class _NoMeter extends StatelessWidget {
  const _NoMeter();

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(
      icon: Icons.electric_meter_rounded,
      title: 'Add your SEM-1',
      body: 'Scan the QR code on the front of your meter. Setup takes about two minutes.',
      action: FilledButton.icon(
        onPressed: () => context.push('/add-meter'),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Add meter'),
      ),
    ),
  );
}
