import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(children: [
        // soft brand glow
        Positioned(
          top: -160,
          right: -120,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [C.brand.withValues(alpha: 0.22), C.brand.withValues(alpha: 0)]),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const BrandMark(size: 44),
                const SizedBox(width: S.md),
                Text('BleuLand Energy', style: t.titleMedium),
              ]),
              const Spacer(),
              const _Preview(),
              const SizedBox(height: S.xxl),
              Text('See every watt\nyour home uses.', style: t.displaySmall?.copyWith(height: 1.15)),
              const SizedBox(height: S.md),
              Text(
                'Live usage, your bill before it arrives, and an alert when something is left on.',
                style: t.bodyLarge?.copyWith(color: C.text2),
              ),
              const SizedBox(height: S.xxl),
              FilledButton(onPressed: () => context.push('/auth?mode=signup'), child: const Text('Create account')),
              const SizedBox(height: S.md),
              OutlinedButton(onPressed: () => context.push('/auth?mode=signin'), child: const Text('Sign in')),
              const SizedBox(height: S.sm),
              Center(
                child: TextButton(
                  onPressed: () {
                    ref.read(demoModeProvider.notifier).set(true);
                    context.go('/home');
                  },
                  child: const Text('Try the demo first'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// A small static teaser of the dashboard.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(S.xl),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Using now', style: t.labelMedium?.copyWith(color: C.text2)),
            const SizedBox(height: S.xs),
            Text.rich(TextSpan(children: [
              TextSpan(text: '860', style: t.displaySmall),
              TextSpan(text: ' W', style: t.titleMedium?.copyWith(color: C.text2)),
            ])),
            const SizedBox(height: S.md),
            const TierMeter(used: 212, limit: 300),
            const SizedBox(height: S.sm),
            Text('88 kWh left at the cheap price', style: t.labelSmall?.copyWith(color: C.text2)),
          ]),
        ),
      ]),
    );
  }
}
