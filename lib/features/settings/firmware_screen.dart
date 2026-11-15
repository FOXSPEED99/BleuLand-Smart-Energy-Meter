import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

/// Meter firmware: current version, what's new, and updating over WiFi.
class FirmwareScreen extends ConsumerStatefulWidget {
  const FirmwareScreen({super.key});
  @override
  ConsumerState<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends ConsumerState<FirmwareScreen> {
  Timer? _poll;
  bool _busy = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// While an update runs, refresh every 3 s.
  void _follow(String meterId, FirmwareStatus? s) {
    final want = s?.updating ?? false;
    if (want && _poll == null) {
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => ref.invalidate(firmwareProvider(meterId)),
      );
    } else if (!want && _poll != null) {
      _poll!.cancel();
      _poll = null;
      if (s?.stage == UpdateStage.done) {
        ref.invalidate(metersProvider); // new version number
      }
    }
  }

  Future<void> _update(Meter m, FirmwareRelease r) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => _ConfirmSheet(release: r),
    );
    if (go != true) return;
    setState(() => _busy = true);
    final res = await ref.read(repositoryProvider).requestUpdate(m.id);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(firmwareProvider(m.id));
    final msg = switch (res) {
      UpdateRequest.ok => null,
      UpdateRequest.upToDate => 'Already up to date.',
      UpdateRequest.busy => 'An update is already running.',
      UpdateRequest.notOwner => 'Only the owner can update the meter.',
      UpdateRequest.failed =>
        'Could not start the update. Check your internet and try again.',
    };
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meter = ref.watch(currentMeterProvider).value;
    if (meter == null) return const Scaffold(body: SizedBox());
    final fw = ref.watch(firmwareProvider(meter.id));
    final live = ref.watch(liveProvider(meter.id)).value;
    final online =
        live != null &&
        DateTime.now().difference(live.ts) < AppConfig.offlineAfter;
    final s = fw.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow(meter.id, s);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Meter firmware')),
      body: fw.when(
        skipLoadingOnRefresh: true,
        loading: () => const Padding(
          padding: EdgeInsets.all(S.page),
          child: LoadingPanel(),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(S.page),
          child: ErrorPanel(
            message: 'Could not check for updates.',
            onRetry: () => ref.invalidate(firmwareProvider(meter.id)),
          ),
        ),
        data: (s) {
          final justUpdated =
              s.stage == UpdateStage.done &&
              s.target == s.current &&
              s.stageAt != null &&
              DateTime.now().difference(s.stageAt!) < const Duration(hours: 24);
          return ListView(
            padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
            children: [
              Panel(
                child: Row(
                  children: [
                    const Icon(Icons.memory_rounded, color: C.text2, size: 28),
                    const SizedBox(width: S.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Version ${s.current ?? '–'}',
                            style: t.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.latest == null && !s.updating
                                ? 'Up to date'
                                : 'Installed now',
                            style: t.bodySmall?.copyWith(color: C.text2),
                          ),
                        ],
                      ),
                    ),
                    if (s.beta)
                      const StatusPill(
                        kind: PillKind.info,
                        label: 'Test builds',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: S.md),
              if (s.updating)
                _Progress(
                  status: s,
                  online: online,
                  onCancel: meter.isOwner && s.stage == UpdateStage.requested
                      ? () async {
                          await ref
                              .read(repositoryProvider)
                              .cancelUpdate(meter.id);
                          ref.invalidate(firmwareProvider(meter.id));
                        }
                      : null,
                )
              else ...[
                if (justUpdated)
                  _Result(
                    ok: true,
                    title: 'Updated to ${s.current}',
                    body: 'The meter restarted and is running the new version.',
                  ),
                if (s.stage == UpdateStage.failed)
                  _Result(
                    ok: false,
                    title:
                        'The update to ${s.target ?? 'the new version'} didn\'t finish',
                    body:
                        '${s.error ?? 'Unknown problem.'} The meter is still working on version ${s.current}. You can try again.',
                  ),
                if (s.latest != null)
                  _Available(
                    release: s.latest!,
                    isOwner: meter.isOwner,
                    online: online,
                    busy: _busy,
                    onUpdate: () => _update(meter, s.latest!),
                  )
                else if (!justUpdated)
                  Panel(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: C.goodText,
                        ),
                        const SizedBox(width: S.md),
                        Expanded(
                          child: Text(
                            'Your meter has the latest firmware.',
                            style: t.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: S.lg),
              Text(
                'Updates install over WiFi. The meter keeps measuring while it downloads, then restarts in a few '
                'seconds. If a new version doesn\'t work, the meter goes back to the old one by itself.',
                style: t.bodySmall?.copyWith(color: C.text3),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Available extends StatelessWidget {
  const _Available({
    required this.release,
    required this.isOwner,
    required this.online,
    required this.busy,
    required this.onUpdate,
  });
  final FirmwareRelease release;
  final bool isOwner, online, busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_rounded, color: C.brand),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(
                  'Version ${release.version} is available',
                  style: t.titleSmall,
                ),
              ),
              if (release.beta)
                const StatusPill(kind: PillKind.info, label: 'Test'),
            ],
          ),
          if (release.notes != null && release.notes!.isNotEmpty) ...[
            const SizedBox(height: S.sm),
            Text(release.notes!, style: t.bodyMedium?.copyWith(color: C.text2)),
          ],
          const SizedBox(height: S.sm),
          Text(
            [
              if (release.size != null)
                '${(release.size! / 1048576).toStringAsFixed(1)} MB',
              if (release.createdAt != null)
                DateFormat('d MMM yyyy').format(release.createdAt!),
            ].join(' · '),
            style: t.labelSmall?.copyWith(color: C.text3),
          ),
          const SizedBox(height: S.lg),
          if (isOwner)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onUpdate,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: const Text('Update now'),
              ),
            )
          else
            Text(
              'Only the meter\'s owner can install updates.',
              style: t.bodySmall?.copyWith(color: C.text2),
            ),
          if (isOwner && !online) ...[
            const SizedBox(height: S.sm),
            Text(
              'The meter is offline right now. It will update as soon as it\'s back online.',
              style: t.bodySmall?.copyWith(color: C.warning),
            ),
          ],
        ],
      ),
    );
  }
}

/// requested -> downloading -> installing, as three steps.
class _Progress extends StatelessWidget {
  const _Progress({required this.status, required this.online, this.onCancel});
  final FirmwareStatus status;
  final bool online;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final at = switch (status.stage) {
      UpdateStage.requested => 0,
      UpdateStage.downloading => 1,
      _ => 2,
    };
    const steps = [
      (
        'Sent to the meter',
        'Waiting for the meter to pick it up (up to 10 s).',
      ),
      ('Downloading', 'About a minute. The meter keeps measuring.'),
      ('Installing and restarting', 'A few seconds. Values pause briefly.'),
    ];
    final waitingLong =
        status.stage == UpdateStage.requested &&
        status.stageAt != null &&
        DateTime.now().difference(status.stageAt!) > const Duration(minutes: 1);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Updating to ${status.target ?? ''}', style: t.titleSmall),
          const SizedBox(height: S.lg),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: i < at
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: C.goodText,
                            size: 22,
                          )
                        : i == at
                        ? const Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: C.brand,
                            ),
                          )
                        : const Icon(
                            Icons.radio_button_unchecked_rounded,
                            color: C.text3,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].$1,
                          style: t.bodyLarge?.copyWith(
                            color: i <= at ? C.text : C.text3,
                          ),
                        ),
                        if (i == at)
                          Text(
                            steps[i].$2,
                            style: t.bodySmall?.copyWith(color: C.text2),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Keep the meter plugged in. You can leave this screen.',
            style: t.bodySmall?.copyWith(color: C.text2),
          ),
          if (waitingLong && !online) ...[
            const SizedBox(height: S.sm),
            Text(
              'The meter is offline. It will update when it\'s back online.',
              style: t.bodySmall?.copyWith(color: C.warning),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: S.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.ok, required this.title, required this.body});
  final bool ok;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = ok ? C.goodText : C.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Container(
        padding: const EdgeInsets.all(S.lg),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(R.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: c,
            ),
            const SizedBox(width: S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: t.bodySmall?.copyWith(color: C.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.release});
  final FirmwareRelease release;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update to ${release.version}?', style: t.titleLarge),
            const SizedBox(height: S.md),
            for (final line in const [
              (Icons.timer_outlined, 'Takes about a minute.'),
              (
                Icons.bolt_rounded,
                'The meter keeps measuring; live values pause for a few seconds while it restarts.',
              ),
              (
                Icons.shield_outlined,
                'If something goes wrong, it goes back to the current version by itself.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(line.$1, size: 18, color: C.text2),
                    const SizedBox(width: S.md),
                    Expanded(
                      child: Text(
                        line.$2,
                        style: t.bodyMedium?.copyWith(color: C.text2),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: S.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Update'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
