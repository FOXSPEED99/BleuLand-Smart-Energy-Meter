import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/flag.dart';
import '../../widgets/ui.dart';

/// "Current bill": energy used and cost so far side by side, the cheap-block
/// meter, and one line about the price, with the country's flag.
class BillCard extends ConsumerWidget {
  const BillCard({super.key, required this.meter, required this.cycle, this.onEditTariff});
  final Meter meter;
  final CycleSummary cycle;
  final VoidCallback? onEditTariff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cur = meter.currency;
    final region = ref.watch(regionProvider);
    final tiers = meter.tariff.tiers;
    final firstLimit = tiers.isNotEmpty ? tiers.first.uptoKwh : null;
    final daysLeft = cycle.period.end.difference(DateTime.now()).inDays;

    if (!meter.tariff.isSet) {
      return Panel(
        onTap: onEditTariff,
        child: Row(children: [
          const Icon(Icons.receipt_long_rounded, color: C.brand),
          const SizedBox(width: S.md),
          Expanded(child: Text('Add your electricity price to see your bill in $cur.', style: t.bodyMedium)),
          const Icon(Icons.chevron_right_rounded, color: C.text3),
        ]),
      );
    }

    final left = daysLeft < 0 ? 0 : daysLeft;
    // one stat: small label, big number, unit; shrinks rather than wraps
    Widget stat(String label, String value, String unit) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.labelMedium?.copyWith(color: C.text3)),
            const SizedBox(height: S.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: value, style: t.displaySmall),
                TextSpan(text: ' $unit', style: t.titleMedium?.copyWith(color: C.text2)),
              ])),
            ),
          ]),
        );

    return Panel(
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xl),
      onTap: onEditTariff,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Current bill', style: t.titleSmall?.copyWith(color: C.text2)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(99)),
            child: Text(left == 1 ? '1 day left' : '$left days left', style: t.labelSmall?.copyWith(color: C.text2)),
          ),
        ]),
        const SizedBox(height: S.lg),
        // energy and cost side by side, equal weight; "≈" while "Match your
        // bill" estimates the days before the meter
        IntrinsicHeight(
          child: Row(children: [
            stat('Used', '${cycle.beforeEstimated ? '≈' : ''}${fmtKwh(cycle.kwh, unit: false)}', 'kWh'),
            Container(width: 1, color: C.outline, margin: const EdgeInsets.symmetric(horizontal: S.lg)),
            stat('Cost', '${cycle.beforeEstimated ? '≈' : ''}${fmtMoney(cycle.cost, '').trim()}', cur),
          ]),
        ),
        if (firstLimit != null) ...[
          const SizedBox(height: S.lg),
          TierMeter(used: cycle.kwh, limit: firstLimit),
          const SizedBox(height: S.sm),
          _PriceLine(cycle: cycle, meter: meter, limit: firstLimit, region: region),
        ],
      ]),
    );
  }
}

/// One line about the price, in plain words ("6 SYP per kWh for the first
/// 300 kWh"), and the country's flag waving on the right.
class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.cycle, required this.meter, required this.limit, required this.region});
  final CycleSummary cycle;
  final Meter meter;
  final double limit;
  final String? region;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.labelSmall;
    final tiers = meter.tariff.tiers;
    final cur = meter.currency;
    final cheap = tiers.first.price;
    final next = tiers.length > 1 ? tiers[1].price : null;
    final inCheap = cycle.kwh <= limit;
    final text = next == null
        ? '${_p(cheap)} $cur per kWh'
        : inCheap
            ? '${_p(cheap)} $cur per kWh for the first ${fmtKwh(limit)}'
            : 'Over ${fmtKwh(limit)}: now ${_p(next)} $cur per kWh';
    return Row(children: [
      Icon(inCheap ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          size: 14, color: inCheap ? C.series : C.warning),
      const SizedBox(width: 6),
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text, maxLines: 1, style: t?.copyWith(color: C.text2)),
        ),
      ),
      if (region != null) ...[
        const SizedBox(width: S.sm),
        WavingFlag(regionId: region!, width: 28, height: 20),
      ],
    ]);
  }

  static String _p(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
