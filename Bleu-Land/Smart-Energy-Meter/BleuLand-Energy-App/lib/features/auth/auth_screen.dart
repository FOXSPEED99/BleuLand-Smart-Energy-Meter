import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/providers.dart';
import '../../theme/tokens.dart';

/// Sign in or create an account with e-mail + password.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.signUp});
  final bool signUp;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  late bool signUp = widget.signUp;
  bool busy = false;
  bool hide = true;
  String? error;
  String? info;

  SupabaseClient get _db => Supabase.instance.client;

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      if (signUp) {
        final res = await _db.auth.signUp(email: email.text.trim(), password: password.text);
        if (res.session == null) {
          setState(() => info = 'Check your e-mail and tap the link to confirm your account, then sign in.');
          setState(() => signUp = false);
          return;
        }
      } else {
        await _db.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
      ref.read(demoModeProvider.notifier).set(false);
      // meters shared with this e-mail address become visible now
      try {
        await _db.rpc('accept_invites');
      } catch (_) {}
      ref.invalidate(metersProvider);
      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      setState(() => error = _friendly(e.message));
    } catch (_) {
      setState(() => error = 'No connection to the server. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _forgot() async {
    final e = email.text.trim();
    if (!e.contains('@')) {
      setState(() => error = 'Type your e-mail address first.');
      return;
    }
    try {
      await _db.auth.resetPasswordForEmail(e);
      setState(() => info = 'We sent a password reset link to $e.');
    } catch (_) {
      setState(() => error = 'Could not send the reset e-mail. Try again later.');
    }
  }

  static String _friendly(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return 'Wrong e-mail or password.';
    if (s.contains('already registered')) return 'This e-mail already has an account. Sign in instead.';
    if (s.contains('email not confirmed')) return 'Please confirm your e-mail first (check your inbox).';
    if (s.contains('rate limit')) return 'Too many attempts. Wait a minute and try again.';
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(S.xl, S.sm, S.xl, S.xl),
            children: [
              Text(signUp ? 'Create your account' : 'Welcome back', style: t.headlineSmall),
              const SizedBox(height: S.sm),
              Text(
                signUp ? 'One account for all your meters and your family.' : 'Sign in to see your home.',
                style: t.bodyMedium?.copyWith(color: C.text2),
              ),
              const SizedBox(height: S.xl),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline_rounded)),
                validator: (v) => v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
                    ? null
                    : 'Enter a valid e-mail address',
              ),
              const SizedBox(height: S.md),
              TextFormField(
                controller: password,
                obscureText: hide,
                autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: hide ? 'Show password' : 'Hide password',
                    icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => hide = !hide),
                  ),
                ),
                validator: (v) => v != null && v.length >= 8 ? null : 'At least 8 characters',
              ),
              if (!signUp)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
                ),
              if (error != null) _Note(text: error!, error: true),
              if (info != null) _Note(text: info!, error: false),
              const SizedBox(height: S.lg),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(signUp ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: S.md),
              TextButton(
                onPressed: () => setState(() {
                  signUp = !signUp;
                  error = null;
                }),
                child: Text(signUp ? 'I already have an account' : 'Create a new account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.error});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: S.md),
        padding: const EdgeInsets.all(S.md),
        decoration: BoxDecoration(
          color: (error ? C.critical : C.brand).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(children: [
          Icon(error ? Icons.error_outline_rounded : Icons.mark_email_read_outlined,
              color: error ? C.criticalText : C.brand, size: 20),
          const SizedBox(width: S.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}
