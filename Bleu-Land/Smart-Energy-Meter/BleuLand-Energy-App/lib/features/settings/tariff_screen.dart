import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/tariff.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// Edit the electricity price: blocks (tiers), billing period, currency.
class TariffScreen extends ConsumerStatefulWidget {
  const TariffScreen({super.key});
  @override
  ConsumerState<TariffScreen> createState() => _TariffScreenState();
}

class _Tier {
  _Tier(String upto, String price)
      : upto = TextEditingController(text: upto),
        price = TextEditingController(text: price);
  final TextEditingController upto;
  final TextEditingController price;
}

class _TariffScreenState extends ConsumerState<TariffScreen> {
  Meter? meter;
  late List<_Tier> tiers;
  late int periodMonths;
  late int billingDay;
  late TextEditingController currency;
  bool saving = false;

  void _load(Meter m) {
    meter = m;
    tiers = [
      for (final t in m.tariff.tiers) _Tier(t.uptoKwh == null ? '' : _n(t.uptoKwh!), _n(t.price)),
    ];
    if (tiers.isEmpty) tiers = [_Tier('', '')];
    periodMonths = m.tariff.periodMonths;
    billingDay = m.billingDay;
    currency = TextEditingController(text: m.currency);
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _resetSyria() => setState(() {
        tiers = [
          for (final t in Tariff.syriaHousehold.tiers) _Tier(t.uptoKwh == null ? '' : _n(t.uptoKwh!), _n(t.price)),
        ];
        periodMonths = Tariff.syriaHousehold.periodMonths;
        currency.text = 'SYP';
      });

  Tariff? _build() {
    final out = <TariffTier>[];
    double last = 0;
    for (var i = 0; i < tiers.length; i++) {
      final price = double.tryParse(tiers[i].price.text.replaceAll(',', '.'));
      if (price == null || price < 0) return null;
      final isLast = i == tiers.length - 1;
      final upto = isLast ? null : double.tryParse(tiers[i].upto.text.replaceAll(',', '.'));
      if (!isLast && (upto == null || upto <= last)) return null;
      out.add(TariffTier(uptoKwh: upto, price: price));
      if (upto != null) last = upto;
    }
    return Tariff(tiers: out, periodMonths: periodMonths);
  }

  Future<void> _save() async {
    final tariff = _build();
    final cur = currency.text.trim().toUpperCase();
    if (tariff == null || cur.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Check the prices: each block needs a price, and limits must go up.'),
      ));
      return;
    }
    setState(() => saving = true);
    try {
      await ref.read(repositoryProvider).updateMeter(meter!.copyWith(tariff: tariff, currency: cur, billingDay: billingDay));
      ref.invalidate(metersProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Check your connection.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = ref.watch(currentMeterProvider).value;
    if (m == null) return const Scaffold(body: SizedBox());
    if (meter?.id != m.id) _load(m);
    final preview = _build();
    final cur = currency.text.trim().toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Electricity price'),
        actions: [TextButton(onPressed: _resetSyria, child: const Text('Syria default'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
        children: [
          Text(
            'Enter the prices from your electricity bill. Most homes in Syria pay a cheaper price for the first block of each bill.',
            style: t.bodyMedium?.copyWith(color: C.text2),
          ),
          const SectionHeader('Price blocks'),
          for (var i = 0; i < tiers.length; i++) _tierRow(i, cur),
          TextButton.icon(
            onPressed: () => setState(() => tiers.insert(tiers.length - 1, _Tier('', ''))),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a block'),
          ),
          const SectionHeader('Billing'),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('A bill covers', style: t.labelMedium?.copyWith(color: C.text2)),
              const SizedBox(height: S.sm),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1 month')),
                  ButtonSegment(value: 2, label: Text('2 months')),
                ],
                selected: {periodMonths},
                onSelectionChanged: (s) => setState(() => periodMonths = s.first),
              ),
              const SizedBox(height: S.lg),
              Row(children: [
                Expanded(child: Text('Starts on day', style: t.bodyMedium)),
                IconButton(
                  onPressed: billingDay > 1 ? () => setState(() => billingDay--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(width: 28, child: Text('$billingDay', textAlign: TextAlign.center, style: t.titleMedium)),
                IconButton(
                  onPressed: billingDay < 28 ? () => setState(() => billingDay++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
              const SizedBox(height: S.sm),
              TextField(
                controller: currency,
                maxLength: 3,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z]'))],
                decoration: const InputDecoration(labelText: 'Currency code', counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
            ]),
          ),
          if (preview != null) ...[
            const SectionHeader('Example'),
            Panel(
              child: Column(children: [
                for (final kwh in [100.0, 300.0, 500.0])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Text(fmtKwh(kwh), style: t.bodyMedium?.copyWith(color: C.text2)),
                      const Spacer(),
                      Text(fmtMoney(preview.costFor(kwh), cur), style: t.titleSmall),
                    ]),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: S.xl),
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _tierRow(int i, String cur) {
    final t = Theme.of(context).textTheme;
    final isLast = i == tiers.length - 1;
    final from = i == 0 ? '0' : (tiers[i - 1].upto.text.isEmpty ? '…' : tiers[i - 1].upto.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              isLast ? 'Above $from kWh' : 'Block ${i + 1}: from $from kWh',
              style: t.titleSmall,
            ),
            const Spacer(),
            if (tiers.length > 1 && !isLast)
              IconButton(
                tooltip: 'Remove block',
                onPressed: () => setState(() => tiers.removeAt(i)),
                icon: const Icon(Icons.delete_outline_rounded, color: C.text3),
              ),
          ]),
          const SizedBox(height: S.sm),
          Row(children: [
            if (!isLast) ...[
              Expanded(
                child: TextField(
                  controller: tiers[i].upto,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Up to', suffixText: 'kWh'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: S.md),
            ],
            Expanded(
              child: TextField(
                controller: tiers[i].price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Price', suffixText: '$cur/kWh'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
