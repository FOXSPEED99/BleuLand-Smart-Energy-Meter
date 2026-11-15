import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/region.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/flag.dart';
import '../../widgets/ui.dart';

/// "Where are your homes?": picked once after signing up or in (changeable
/// in Settings). Today only Syria; more countries are added in region.dart.
class RegionScreen extends ConsumerStatefulWidget {
  const RegionScreen({super.key});
  @override
  ConsumerState<RegionScreen> createState() => _RegionScreenState();
}

class _RegionScreenState extends ConsumerState<RegionScreen> {
  String _id = regions.first.id;
  bool _saving = false;

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await saveRegion(_id); // the router moves on to Home once it's saved
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t save. Check your internet connection and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.page, S.xl, S.page, S.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: WavingFlag(regionId: 'sy', width: 72, height: 50)),
            const SizedBox(height: S.xl),
            Text('Where are your homes?', style: t.headlineSmall),
            const SizedBox(height: S.sm),
            Text(
              'Your bill uses it for the currency and local prices. You can change it later in Settings.',
              style: t.bodyMedium?.copyWith(color: C.text2),
            ),
            const SizedBox(height: S.xl),
            RegionList(selected: _id, onPick: (id) => setState(() => _id = id)),
            const SizedBox(height: S.md),
            Text('More countries are coming.', style: t.bodySmall?.copyWith(color: C.text3)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _continue,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The countries to pick from, the chosen one ticked.
class RegionList extends StatelessWidget {
  const RegionList({super.key, required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final r in regions)
          ListTile(
            onTap: () => onPick(r.id),
            leading: WavingFlag(regionId: r.id, width: 30, height: 21, wave: false),
            title: Text(r.name, style: t.bodyLarge),
            subtitle: Text('Prices in ${r.currency}'),
            trailing: r.id == selected
                ? const Icon(Icons.check_circle_rounded, color: C.brand)
                : const Icon(Icons.circle_outlined, color: C.text3),
          ),
      ]),
    );
  }
}
