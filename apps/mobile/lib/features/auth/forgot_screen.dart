import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';

/// Ask for a code by email, then choose a new password with it.
class ForgotScreen extends ConsumerStatefulWidget {
  const ForgotScreen({super.key});

  @override
  ConsumerState<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends ConsumerState<ForgotScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _haveCode = false;

  @override
  void dispose() {
    for (final c in [_email, _code, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _request() async {
    if (!_email.text.contains('@')) return;
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref.read(authRepositoryProvider).forgot(_email.text),
      success: t.resetCodeSent,
    );
    if (ok && mounted) setState(() => _haveCode = true);
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final email = _email.text.trim();
    final ok = await perform(
      context,
      () => ref
          .read(authRepositoryProvider)
          .reset(email: email, code: _code.text, password: _password.text),
      success: t.passwordChanged,
    );
    if (ok && mounted)
      context.go('/login?email=${Uri.encodeQueryComponent(email)}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AuthScaffold(
      showBack: true,
      title: t.forgotTitle,
      subtitle: _haveCode ? t.forgotCodeSubtitle : t.forgotSubtitle,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.email),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? t.emailInvalid : null,
              ),
              if (_haveCode) ...[
                const Gap(14),
                CodeField(
                  controller: _code,
                  label: t.recoveryCode,
                  invalidMessage: t.codeInvalid,
                ),
                const Gap(14),
                PasswordField(
                  controller: _password,
                  label: t.newPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _reset(),
                  validator: (v) =>
                      (v == null || v.length < 8) ? t.passwordTooShort : null,
                ),
              ],
              const Gap(24),
              AsyncButton(
                label: _haveCode ? t.changePassword : t.sendCode,
                onPressed: _haveCode ? _reset : _request,
              ),
              if (!_haveCode) ...[
                const Gap(8),
                TextButton(
                  onPressed: () => setState(() => _haveCode = true),
                  child: Text(t.haveCode),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
