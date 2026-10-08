import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/ui.dart';

final _invitesProvider = FutureProvider.family<List<Invite>, String>(
  (ref, id) => ref.watch(repositoryProvider).invites(id),
);

/// Invite family members by e-mail. They see live values and history once
/// they sign up or sign in with that address.
class SharingScreen extends ConsumerStatefulWidget {
  const SharingScreen({super.key});
  @override
  ConsumerState<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends ConsumerState<SharingScreen> {
  final email = TextEditingController();
  bool busy = false;

  Future<void> _invite(String meterId) async {
    final e = email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid e-mail address.')));
      return;
    }
    setState(() => busy = true);
    try {
      await ref.read(repositoryProvider).invite(meterId, e);
      email.clear();
      ref.invalidate(_invitesProvider(meterId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send. Already invited?')));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meter = ref.watch(currentMeterProvider).value;
    if (meter == null) return const Scaffold(body: SizedBox());
    final invites = ref.watch(_invitesProvider(meter.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Share with family')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.page, S.sm, S.page, S.xxl),
        children: [
          Text(
            'People you invite can see live usage, history and the bill. Only you can change settings.',
            style: t.bodyMedium?.copyWith(color: C.text2),
          ),
          const SizedBox(height: S.lg),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Their e-mail address', prefixIcon: Icon(Icons.mail_outline_rounded)),
            onSubmitted: (_) => _invite(meter.id),
          ),
          const SizedBox(height: S.md),
          FilledButton(onPressed: busy ? null : () => _invite(meter.id), child: const Text('Send invite')),
          const SectionHeader('Invited'),
          invites.when(
            loading: () => const LoadingPanel(),
            error: (e, _) => const ErrorPanel(message: 'Could not load invites.'),
            data: (list) => list.isEmpty
                ? Text('Nobody yet.', style: t.bodyMedium?.copyWith(color: C.text3))
                : Panel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(indent: 56),
                        ListTile(
                          leading: const Icon(Icons.person_outline_rounded),
                          title: Text(list[i].email),
                          subtitle: Text(list[i].acceptedAt != null
                              ? 'Joined ${fmtAgo(list[i].acceptedAt!)}'
                              : 'Waiting · invited ${fmtAgo(list[i].createdAt)}'),
                          trailing: IconButton(
                            tooltip: 'Cancel invite',
                            icon: const Icon(Icons.close_rounded, color: C.text3),
                            onPressed: () async {
                              await ref.read(repositoryProvider).cancelInvite(list[i].id);
                              ref.invalidate(_invitesProvider(meter.id));
                            },
                          ),
                        ),
                      ],
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}
