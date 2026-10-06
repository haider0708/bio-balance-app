import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';

/// The BioBalance logo above a screen title: shared by every signed-out screen.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.title, required this.children, this.subtitle, this.showBack = false, super.key});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: showBack ? const BackButton() : null,
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset('assets/brand/biobalance-logo.jpg', height: 76, fit: BoxFit.contain),
                    ),
                  ),
                  const Gap(28),
                  Text(title, style: context.text.headlineMedium),
                  if (subtitle != null) ...[
                    const Gap(8),
                    Text(subtitle!, style: context.text.bodyLarge?.copyWith(color: context.status.muted)),
                  ],
                  const Gap(28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// FR | EN, saved on the phone.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Localizations.localeOf(context).languageCode;
    Widget option(String code, String label) {
      final on = current == code;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => ref.read(localeProvider.notifier).choose(code),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: on ? context.colors.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              code.toUpperCase(),
              style: context.text.labelLarge?.copyWith(color: on ? context.colors.primary : context.status.muted),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.languages, size: 18, color: context.status.muted),
        const SizedBox(width: 6),
        option('fr', 'Français'),
        option('en', 'English'),
      ],
    );
  }
}

/// A password field with a show/hide button.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
    this.validator,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          icon: Icon(_hidden ? LucideIcons.eye : LucideIcons.eyeOff, size: 20),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}
