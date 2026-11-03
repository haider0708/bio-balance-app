import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/session.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'auth_repository.dart';
import 'auth_widgets.dart';

/// First sign-in with the password that was sent: the person chooses their own before anything else.
/// The server refuses every other request until they have, so this cannot be skipped.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () =>
          ref.read(authRepositoryProvider).changePassword(next: _password.text),
      success: t.passwordSet,
    );
    // The server now knows them as themselves: asking who they are again opens the app.
    if (ok) await ref.read(sessionProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name = ref.watch(meProvider).name.split(' ').first;
    return AuthScaffold(
      title: t.setPasswordTitle(name),
      subtitle: t.setPasswordHint,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                controller: _password,
                label: t.newPassword,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) =>
                    (v == null || v.length < 8) ? t.passwordTooShort : null,
              ),
              const Gap(14),
              PasswordField(
                controller: _confirm,
                label: t.confirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                validator: (v) =>
                    v != _password.text ? t.passwordsDiffer : null,
              ),
              const Gap(8),
              Text(
                t.passwordRule,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Gap(20),
              AsyncButton(
                label: t.setPasswordSave,
                icon: LucideIcons.check,
                onPressed: _save,
              ),
              const Gap(8),
              AsyncButton(
                label: t.signOut,
                style: AsyncButtonStyle.text,
                onPressed: () => ref.read(sessionProvider.notifier).logout(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
