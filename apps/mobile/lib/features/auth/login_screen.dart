import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import '../settings/legal.dart';
import 'auth_widgets.dart';

/// Sign-in on the phone. The web console wraps the same [SignInForm] in its own layout.
class LoginScreen extends StatelessWidget {
  const LoginScreen({this.email, super.key});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AuthScaffold(
      title: t.signInTitle,
      subtitle: t.signInSubtitle,
      children: [
        SignInForm(email: email),
        const Divider(height: 40),
        Text(
          t.invitedHint,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium,
        ),
        const Gap(8),
        OutlinedButton(
          onPressed: () => context.push('/activate'),
          child: Text(t.activateAccount),
        ),
        const Gap(16),
        const LegalLinks(),
      ],
    );
  }
}

/// Email and password, then the authenticator code when the account asks for one.
/// The router moves on by itself once the session exists.
class SignInForm extends ConsumerStatefulWidget {
  const SignInForm({this.email, this.icons = false, super.key});

  final String? email;

  /// Small icons in front of each field (the web console's look).
  final bool icons;

  @override
  ConsumerState<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<SignInForm> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _needsCode = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(email: _email.text, password: _password.text, otp: _otp.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'MFA_REQUIRED') {
        setState(() => _needsCode = true);
        if (_otp.text.isNotEmpty) {
          showMessage(context, t.codeInvalid, error: true);
        }
        return;
      }
      showError(context, error);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Widget? _icon(IconData icon) =>
      widget.icons ? Icon(icon, size: 18, color: context.status.muted) : null;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              decoration: InputDecoration(
                labelText: t.email,
                prefixIcon: _icon(LucideIcons.mail),
              ),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? t.emailInvalid : null,
            ),
            const Gap(14),
            PasswordField(
              controller: _password,
              label: t.password,
              autofillHints: const [AutofillHints.password],
              textInputAction: _needsCode
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: (_) => _needsCode ? null : _submit(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? t.passwordRequired : null,
            ),
            if (_needsCode) ...[
              const Gap(14),
              TextFormField(
                controller: _otp,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(
                  labelText: t.authenticatorCode,
                  helperText: t.authenticatorCodeHelp,
                  prefixIcon: _icon(LucideIcons.shieldCheck),
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.length != 6) ? t.codeInvalid : null,
              ),
            ],
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.push('/forgot'),
                child: Text(t.forgotPassword),
              ),
            ),
            const Gap(8),
            AsyncButton(label: t.signIn, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
