import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'session_view_model.dart';
import '../../core/design.dart';
import '../../core/recovery_code_field.dart';
import '../../core/installation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _otp = TextEditingController();
  bool _visible = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SessionViewModel>();
    return Scaffold(
      body: SafeArea(
        child: FormContent(
          maxWidth: 480,
          children: [
            const SizedBox(height: 24),
            Image.asset(
              'assets/brand/biobalance-logo.jpg',
              height: 72,
              semanticLabel: 'BioBalance, Back to nature',
            ),
            const SizedBox(height: 24),
            const SectionTitle(
              Installation.variant == '' ? 'Connexion' : Installation.label,
              subtitle: Installation.loginHint,
            ),
            if (vm.state.error != null) ...[
              Notice(vm.state.error!, error: true),
              const SizedBox(height: 16),
            ],
            AutofillGroup(
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('auth.email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Adresse email',
                      prefixIcon: Icon(AppIcons.mailOutline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('auth.password'),
                    controller: _password,
                    obscureText: !_visible,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _login(vm),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(AppIcons.lockOutline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _visible = !_visible),
                        icon: Icon(
                          _visible
                              ? AppIcons.visibilityOffOutlined
                              : AppIcons.visibilityOutlined,
                        ),
                        tooltip: _visible
                            ? 'Masquer le mot de passe'
                            : 'Afficher le mot de passe',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              trailing: const Icon(AppIcons.keyboardArrowDown),
              tilePadding: EdgeInsets.zero,
              title: const Text('Code administrateur (MFA)'),
              children: [
                TextField(
                  key: const ValueKey('auth.otp'),
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Code à six chiffres',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('auth.login'),
              onPressed: vm.state.busy ? null : () => _login(vm),
              child: vm.state.busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Se connecter'),
            ),
            TextButton(
              onPressed: () => _accountAction(context, 'forgot'),
              child: const Text('Mot de passe oublié ?'),
            ),
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _accountAction(context, 'activate'),
              icon: const Icon(AppIcons.markEmailReadOutlined),
              label: const Text('Activer mon invitation'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Un accès personnel pour chaque membre de votre équipe.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  void _login(SessionViewModel vm) {
    if (!vm.state.busy) vm.login(_email.text, _password.text, _otp.text);
  }

  Future<void> _accountAction(BuildContext context, String mode) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AccountActionScreen(mode: mode)));
  }
}

class AccountActionScreen extends StatefulWidget {
  final String mode;
  final String? initialToken;
  const AccountActionScreen({super.key, required this.mode, this.initialToken});
  @override
  State<AccountActionScreen> createState() => _AccountActionScreenState();
}

class _AccountActionScreenState extends State<AccountActionScreen> {
  final _email = TextEditingController(),
      _token = TextEditingController(),
      _name = TextEditingController(),
      _password = TextEditingController();
  bool busy = false, passwordVisible = false;
  String? error, success;
  late String mode = widget.mode;
  @override
  void initState() {
    super.initState();
    _token.text = widget.initialToken ?? '';
  }

  @override
  void dispose() {
    for (final c in [_email, _token, _name, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: mode == 'activate' ? 'Activer mon accès' : 'Récupérer mon compte',
    maxWidth: 480,
    action: FilledButton(
      onPressed: busy ? null : submit,
      child: Text(
        busy
            ? 'Veuillez patienter…'
            : mode == 'forgot'
            ? 'Recevoir un code'
            : 'Confirmer',
      ),
    ),
    children: [
      Text(
        mode == 'forgot'
            ? 'Recevez un code pour choisir un nouveau mot de passe.'
            : mode == 'reset'
            ? 'Saisissez le code reçu et choisissez votre nouveau mot de passe.'
            : 'Votre invitation vous donne accès à votre équipe.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 20),
      if (error != null) Notice(error!, error: true),
      if (success != null) Notice(success!),
      const SizedBox(height: 16),
      if (mode == 'forgot')
        TextField(
          key: const ValueKey('auth.email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Adresse email'),
        ),
      if (mode != 'forgot') ...[
        if (mode == 'reset')
          RecoveryCodeField(controller: _token, enabled: !busy)
        else
          TextField(
            key: const ValueKey('auth.token'),
            controller: _token,
            decoration: const InputDecoration(labelText: 'Code reçu par email'),
          ),
        const SizedBox(height: 16),
        if (mode == 'activate') ...[
          TextField(
            key: const ValueKey('auth.name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Votre nom'),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const ValueKey('auth.password'),
          controller: _password,
          obscureText: !passwordVisible,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            helperText: '12 caractères minimum',
            suffixIcon: IconButton(
              tooltip: passwordVisible
                  ? 'Masquer le mot de passe'
                  : 'Afficher le mot de passe',
              onPressed: () =>
                  setState(() => passwordVisible = !passwordVisible),
              icon: Icon(
                passwordVisible
                    ? AppIcons.visibilityOffOutlined
                    : AppIcons.visibilityOutlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (mode == 'activate')
          const Text(
            'Vous avez déjà un compte ? Utilisez son mot de passe actuel pour activer cet accès.',
            style: TextStyle(fontSize: 14),
          ),
      ],
      if (mode == 'forgot')
        TextButton(
          onPressed: () => setState(() => mode = 'reset'),
          child: const Text('J’ai déjà reçu un code'),
        ),
      if (mode == 'reset')
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  mode = 'forgot';
                  error = null;
                  success = null;
                }),
          child: const Text('Recevoir un nouveau code'),
        ),
    ],
  );
  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      if (mode != 'forgot' && _password.text.length < 12) {
        throw const FormatException(
          'Choisissez un mot de passe de 12 caractères minimum.',
        );
      }
      if (mode == 'reset' &&
          !RegExp(r'^(?:[A-Za-z0-9]{8}|[A-Za-z0-9_-]{32,256})$')
              .hasMatch(_token.text.trim())) {
        throw const FormatException('Saisissez les 8 caractères du code reçu.');
      }
      final identity = context.read<SessionViewModel>().identity;
      if (mode == 'activate') {
        await identity.activate(
          _token.text.trim(),
          _password.text,
          _name.text.trim(),
        );
      } else if (mode == 'forgot') {
        await identity.forgot(_email.text.trim());
      } else {
        await identity.reset(_token.text.trim(), _password.text);
      }
      if (mounted) {
        if (mode == 'forgot') {
          setState(() {
            mode = 'reset';
            success = 'Si un compte existe, son code a été envoyé. Saisissez-le ci-dessous avec votre nouveau mot de passe.';
          });
        } else {
          FocusScope.of(context).unfocus();
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).popUntil((route) => route.isFirst);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                mode == 'reset'
                    ? 'Mot de passe modifié. Connectez-vous avec votre nouveau mot de passe.'
                    : 'Votre accès est activé. Vous pouvez vous connecter.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
