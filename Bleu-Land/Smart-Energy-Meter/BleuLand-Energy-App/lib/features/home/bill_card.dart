import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// "This bill": cost so far, the cheap-block meter, and where the bill is heading.
class BillCard extends StatelessWidget {
  const BillCard({
    super.key,
    required this.meter,
    required this.cycle,
    this.onEditTariff,
  });
  final Meter meter;
  final CycleSummary cycle;
  final VoidCallback? onEditTariff;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cur = meter.currency;
    final df = DateFormat('d MMM');
    final tiers = meter.tariff.tiers;
    final firstLimit = tiers.isNotEmpty ? tiers.first.uptoKwh : null;
    final daysLeft = cycle.period.end.difference(DateTime.now()).inDays;

    if (!meter.tariff.isSet) {
      return Panel(
        onTap: onEditTariff,
        child: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: C.brand),
            const SizedBox(width: S.md),
            Expanded(
              child: Text(
                'Add your electricity price to see your bill in $cur.',
                style: t.bodyMedium,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.text3),
          ],
        ),
      );
    }

    return Panel(
      padding: const EdgeInsets.all(S.xl),
      onTap: onEditTariff,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('This bill', style: t.titleSmall?.copyWith(color: C.text2)),
              const Spacer(),
              Text(
                '${df.format(cycle.period.start)} – ${df.format(cycle.period.end.subtract(const Duration(days: 1)))}',
                style: t.labelMedium?.copyWith(color: C.text3),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: fmtMoney(cycle.cost, '').trim(),
                  style: t.displaySmall,
                ),
                TextSpan(
                  text: ' $cur',
                  style: t.titleMedium?.copyWith(color: C.text2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${fmtKwh(cycle.kwh)} so far · $daysLeft days left',
            style: t.bodySmall?.copyWith(color: C.text2),
          ),
          if (firstLimit != null) ...[
            const SizedBox(height: S.lg),
            TierMeter(
              used: cycle.kwh,
              limit: firstLimit,
              projected: cycle.projectedKwh,
            ),
            const SizedBox(height: S.sm),
            _TierLegend(cycle: cycle, meter: meter, limit: firstLimit),
          ],
          const SizedBox(height: S.lg),
          Container(
            padding: const EdgeInsets.all(S.md),
            decoration: BoxDecoration(
              color: C.surface2,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.trending_up_rounded, size: 20, color: C.text2),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: t.bodySmall?.copyWith(color: C.text2),
                      children: [
                        const TextSpan(text: 'At this pace: '),
                        TextSpan(
                          text:
                              '~${fmtKwh(cycle.projectedKwh)} · ${fmtMoney(cycle.projectedCost, cur)}',
                          style: const TextStyle(
                            color: C.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: ' by the end of this bill.'),
                        if (cycle.tierCrossDate != null &&
                            cycle.tierCrossDate!.isBefore(
                              cycle.period.end,
                            )) ...[
                          const TextSpan(
                            text: ' The cheap block runs out around ',
                          ),
                          TextSpan(
                            text: DateFormat('d MMM')
                                .format(cycle.tierCrossDate!),
                            style: const TextStyle(
                              color: C.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierLegend extends StatelessWidget {
  const _TierLegend({
    required this.cycle,
    required this.meter,
    required this.limit,
  });
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
    return Row(
      children: [
        Icon(
          inCheap ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          size: 14,
          color: inCheap ? C.series : C.warning,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            inCheap
                ? '${fmtKwh(left.toDouble())} left at ${_p(cheap)} ${meter.currency}/kWh'
                : 'Above ${fmtKwh(limit)}: now ${_p(next ?? cheap)} ${meter.currency}/kWh',
            style: t?.copyWith(color: C.text2),
          ),
        ),
        if (next != null && inCheap)
          Text('then ${_p(next)}', style: t?.copyWith(color: C.text3)),
      ],
    );
  }

  static String _p(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
