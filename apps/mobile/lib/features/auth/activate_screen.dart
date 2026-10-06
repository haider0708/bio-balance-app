import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';

/// First sign-in: the email and the code that arrived after the admin approved the account.
class ActivateScreen extends ConsumerStatefulWidget {
  const ActivateScreen({super.key});

  @override
  ConsumerState<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends ConsumerState<ActivateScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_email, _code, _name, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final email = _email.text.trim();
    final ok = await perform(
      context,
      () => ref
          .read(authRepositoryProvider)
          .activate(
            email: email,
            code: _code.text,
            password: _password.text,
            name: _name.text,
          ),
      success: t.accountActivated,
    );
    if (ok && mounted)
      context.go('/login?email=${Uri.encodeQueryComponent(email)}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AuthScaffold(
      showBack: true,
      title: t.activateTitle,
      subtitle: t.activateSubtitle,
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
              const Gap(14),
              CodeField(
                controller: _code,
                label: t.activationCode,
                invalidMessage: t.codeInvalid,
              ),
              const Gap(14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.fullNameOptional),
              ),
              const Gap(14),
              PasswordField(
                controller: _password,
                label: t.newPassword,
                validator: (v) =>
                    (v == null || v.length < 8) ? t.passwordTooShort : null,
              ),
              const Gap(14),
              PasswordField(
                controller: _confirm,
                label: t.confirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _password.text ? t.passwordsDiffer : null,
              ),
              const Gap(24),
              AsyncButton(label: t.activateAccount, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}
