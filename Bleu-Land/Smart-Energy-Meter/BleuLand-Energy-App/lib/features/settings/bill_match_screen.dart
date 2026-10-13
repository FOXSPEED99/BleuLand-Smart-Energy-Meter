import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/tariff.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/number_input.dart';
import '../../widgets/ui.dart';

/// "Match your bill" (Syria): two numbers from the electricity company's
/// meter, so the bill in the app counts the whole cycle, also the days before
/// the BleuLand meter was installed. Optional: everything works without it.
class BillMatchScreen extends ConsumerStatefulWidget {
  const BillMatchScreen({super.key});
  @override
  ConsumerState<BillMatchScreen> createState() => _BillMatchScreenState();
}

class _BillMatchScreenState extends ConsumerState<BillMatchScreen> {
  final _house = TextEditingController();
  final _lastBill = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  static final _n = NumberFormat('#,##0');
  static double? _parse(String s) => double.tryParse(s.replaceAll(RegExp(r'[,\s]'), ''));

  @override
  void dispose() {
    _house.dispose();
    _lastBill.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save(Meter m) async {
    final house = _parse(_house.text);
    final last = _parse(_lastBill.text);
    if (house == null || house <= 0) return _toast('Enter the number on your house meter.');
    if (last == null || last <= 0) return _toast('Enter the current reading from your last bill.');
    if (last > house) return _toast('The last bill\'s reading can\'t be higher than the meter shows now.');
    if (house - last > 20000) return _toast('That\'s more than 20,000 kWh apart: check both numbers.');
    // the BleuLand meter's own counter right now, to follow the house meter from here
    final live = ref.read(liveProvider(m.id)).value;
    if (live == null || DateTime.now().difference(live.ts) > const Duration(minutes: 10)) {
      return _toast('Your BleuLand meter needs to be online to match the bill.');
    }
    setState(() => _saving = true);
    final match = BillMatch(
      at: DateTime.now(),
      houseKwh: house,
      cycleStartKwh: last,
      meterKwh: live.kwhTotal,
    );
    try {
      // Syrian bills: 2-month cycles starting on the 1st of odd months
      await ref.read(repositoryProvider).updateMeter(
            m.copyWith(tariff: m.tariff.copyWith(match: match, periodMonths: 2), billingDay: 1),
          );
      ref.invalidate(metersProvider);
      ref.invalidate(cycleProvider);
      if (mounted) setState(() => _editing = false);
    } catch (_) {
      _toast('Couldn\'t save. Check your internet connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(Meter m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Stop matching your bill?'),
        content: const Text('The bill will count only what your BleuLand meter measured.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Stop')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).updateMeter(m.copyWith(tariff: m.tariff.copyWith(clearMatch: true)));
      ref.invalidate(metersProvider);
      ref.invalidate(cycleProvider);
    } catch (_) {
      _toast('Couldn\'t save. Check your internet connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(currentMeterProvider).value;
    if (m == null) return const Scaffold(body: SizedBox());
    final match = m.tariff.match;
    return Scaffold(
      appBar: AppBar(title: const Text('Match your bill')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
        children: match == null || _editing ? _form(m, match) : _summary(m, match),
      ),
    );
  }

  // ------------------------------------------------------------ the form

  List<Widget> _form(Meter m, BillMatch? match) {
    final t = Theme.of(context).textTheme;
    if (_house.text.isEmpty && match != null) {
      // editing: start from the house meter as it should read now
      final live = ref.read(liveProvider(m.id)).value;
      _house.text = _n.format(live == null ? match.houseKwh : match.houseNow(live.kwhTotal));
    }
    return [
      Text(
        'Make the bill here match your paper bill. Your BleuLand meter started in the middle of a cycle, so '
        'it didn\'t see the days before. Your house meter (the electricity company\'s) did: two numbers from '
        'it make the bill exact.',
        style: t.bodyMedium?.copyWith(color: C.text2),
      ),
      const SizedBox(height: S.xl),
      _field(
        controller: _house,
        label: 'House meter now',
        help: 'The number on the electricity company\'s meter today (the screen marked 1.8.0).',
        icon: Icons.speed_rounded,
      ),
      const SizedBox(height: S.lg),
      _field(
        controller: _lastBill,
        label: 'Last bill: current reading',
        help: 'The "current reading" printed on your last paper bill: where this cycle started.',
        icon: Icons.receipt_long_rounded,
      ),
      const SizedBox(height: S.xl),
      FilledButton(
        onPressed: _saving ? null : () => _save(m),
        child: _saving
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Match my bill'),
      ),
      if (match != null) ...[
        const SizedBox(height: S.sm),
        TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Cancel')),
      ],
      const SizedBox(height: S.lg),
      Text(
        'Optional. Your meter and the app work the same without it. Your Home screen doesn\'t change: the bill on '
        'it simply includes these numbers.',
        style: t.bodySmall?.copyWith(color: C.text3),
      ),
    ];
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String help,
    required IconData icon,
    String suffix = 'kWh',
    int decimals = 0,
  }) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
        // "106,469" while typing, not "106469"
        inputFormatters: [GroupedNumberFormatter(decimals: decimals)],
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 3,
          prefixIcon: Icon(icon),
          suffixText: suffix,
        ),
      );

  // ------------------------------------------------------------ after matching

  List<Widget> _summary(Meter m, BillMatch match) {
    final t = Theme.of(context).textTheme;
    final cycle = ref.watch(cycleProvider(m.id)).value;
    final live = ref.watch(liveProvider(m.id)).value;
    final day = DateFormat('d MMM');
    final inThisCycle = cycle != null && cycle.beforeKwh != null;
    final complete = match.cycleStartKwh != null; // matched before the reading was required
    Widget row(String label, String value, {bool strong = false, String? note}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: S.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: (strong ? t.titleSmall : t.bodyMedium)?.copyWith(color: strong ? C.text : C.text2)),
                if (note != null) Text(note, style: t.labelSmall?.copyWith(color: C.text3)),
              ]),
            ),
            Text(value, style: (strong ? t.titleMedium : t.bodyLarge)?.copyWith(color: C.text)),
          ]),
        );
    return [
      Panel(
        padding: const EdgeInsets.all(S.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              complete ? Icons.check_circle_rounded : Icons.info_rounded,
              color: complete ? C.goodText : C.warning,
              size: 20,
            ),
            const SizedBox(width: S.sm),
            Text(complete ? 'Bill matched' : 'One number missing', style: t.titleMedium),
          ]),
          const SizedBox(height: S.xs),
          Text('Numbers from ${day.format(match.at)}', style: t.bodySmall?.copyWith(color: C.text3)),
          const SizedBox(height: S.lg),
          if (!complete)
            Text(
              'Add the current reading from your last bill. Until then the bill counts only what your BleuLand '
              'meter measured.',
              style: t.bodyMedium?.copyWith(color: C.text2),
            )
          else if (cycle == null)
            const Padding(padding: EdgeInsets.all(S.md), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (inThisCycle) ...[
            Text(
              'This cycle: ${day.format(cycle.period.start)} – ${day.format(cycle.period.end.subtract(const Duration(days: 1)))}',
              style: t.labelMedium?.copyWith(color: C.text2),
            ),
            const SizedBox(height: S.xs),
            row(
              'Before your BleuLand meter',
              fmtKwh(cycle.beforeKwh!),
              note: '${_n.format(match.houseKwh)} − ${_n.format(match.cycleStartKwh)} on your house meter',
            ),
            row('Measured since ${day.format(match.at)}', fmtKwh(cycle.measuredKwh ?? 0)),
            const Divider(),
            row('This cycle so far', fmtKwh(cycle.kwh), strong: true),
          ] else
            Text(
              'Your BleuLand meter has measured this whole cycle, so the bill needs no extra numbers.',
              style: t.bodyMedium?.copyWith(color: C.text2),
            ),
        ]),
      ),
      const SizedBox(height: S.md),
      Panel(
        padding: const EdgeInsets.all(S.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your house meter should read', style: t.labelMedium?.copyWith(color: C.text2)),
          const SizedBox(height: S.xs),
          Text(
            live == null ? '—' : '${_n.format(match.houseNow(live.kwhTotal))} kWh',
            style: t.headlineSmall,
          ),
          const SizedBox(height: S.sm),
          Text(
            'Compare it with the number the meter reader writes on your bill. A big difference can mean an '
            'estimated or wrong reading.',
            style: t.bodySmall?.copyWith(color: C.text3),
          ),
          if (live != null && DateTime.now().difference(live.ts) > AppConfig.offlineAfter)
            Padding(
              padding: const EdgeInsets.only(top: S.sm),
              child: Text('Meter offline: this may be behind.', style: t.labelSmall?.copyWith(color: C.warning)),
            ),
        ]),
      ),
      const SizedBox(height: S.xl),
      OutlinedButton(
        onPressed: () => setState(() {
          _editing = true;
          _house.clear(); // refilled with what it should read now
          _lastBill.text = match.cycleStartKwh == null ? '' : _n.format(match.cycleStartKwh);
        }),
        child: Text(complete ? 'Update the numbers' : 'Add the reading'),
      ),
      const SizedBox(height: S.sm),
      TextButton(
        onPressed: () => _remove(m),
        style: TextButton.styleFrom(foregroundColor: C.criticalText),
        child: const Text('Stop matching'),
      ),
    ];
  }
}
