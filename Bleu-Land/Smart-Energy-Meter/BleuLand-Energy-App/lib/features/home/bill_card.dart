import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// "This bill": energy used and cost so far side by side, and the cheap-block meter.
class BillCard extends StatelessWidget {
  const BillCard({super.key, required this.meter, required this.cycle, this.onEditTariff});
  final Meter meter;
  final CycleSummary cycle;
  final VoidCallback? onEditTariff;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cur = meter.currency;
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
      padding: const EdgeInsets.all(S.xl),
      onTap: onEditTariff,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('This bill', style: t.titleSmall?.copyWith(color: C.text2)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(99)),
            child: Text(left == 1 ? '1 day left' : '$left days left', style: t.labelSmall?.copyWith(color: C.text2)),
          ),
        ]),
        const SizedBox(height: S.lg),
        // energy and cost side by side, equal weight
        IntrinsicHeight(
          child: Row(children: [
            stat('Used', fmtKwh(cycle.kwh, unit: false), 'kWh'),
            Container(width: 1, color: C.outline, margin: const EdgeInsets.symmetric(horizontal: S.lg)),
            stat('Cost', fmtMoney(cycle.cost, '').trim(), cur),
          ]),
        ),
        if (firstLimit != null) ...[
          const SizedBox(height: S.lg),
          TierMeter(used: cycle.kwh, limit: firstLimit),
          const SizedBox(height: S.sm),
          _TierLegend(cycle: cycle, meter: meter, limit: firstLimit),
        ],
      ]),
    );
  }
}

class _TierLegend extends StatelessWidget {
  const _TierLegend({required this.cycle, required this.meter, required this.limit});
  final CycleSummary cycle;
  final Meter meter;
  final double limit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.labelSmall;
    final tiers = meter.tariff.tiers;
    final cheap = tiers.first.price;
    final next = tiers.length > 1 ? tiers[1].price : null;
    final inCheap = cycle.kwh <= limit;
    final left = (limit - cycle.kwh).clamp(0, limit);
    return Row(children: [
      Icon(inCheap ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          size: 14, color: inCheap ? C.series : C.warning),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          inCheap
              ? '${fmtKwh(left.toDouble())} left at ${_p(cheap)} ${meter.currency}/kWh'
              : 'Above ${fmtKwh(limit)}: now ${_p(next ?? cheap)} ${meter.currency}/kWh',
          style: t?.copyWith(color: C.text2),
        ),
      ),
      if (next != null && inCheap) Text('then ${_p(next)}', style: t?.copyWith(color: C.text3)),
    ]);
  }

  static String _p(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
