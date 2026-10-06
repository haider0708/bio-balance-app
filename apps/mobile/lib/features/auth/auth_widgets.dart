import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/session.dart';
import '../../l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';

/// The BioBalance logo above a screen title: shared by every signed-out screen.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.showBack = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: showBack ? const BackButton() : null,
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle()),
        ],
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
                      child: Image.asset(
                        'assets/brand/biobalance-logo.jpg',
                        height: 76,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const Gap(28),
                  Text(title, style: context.text.headlineMedium),
                  if (subtitle != null) ...[
                    const Gap(8),
                    Text(
                      subtitle!,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
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
              style: context.text.labelLarge?.copyWith(
                color: on ? context.colors.primary : context.status.muted,
              ),
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

/// An 8-character code (activation or recovery) with a Paste button: copy it from the email, paste it here.
class CodeField extends StatelessWidget {
  const CodeField({
    required this.controller,
    required this.label,
    required this.invalidMessage,
    this.textInputAction = TextInputAction.next,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String invalidMessage;
  final TextInputAction textInputAction;

  /// `abcd2345` becomes `ABCD-2345`; anything incomplete stays as typed so far.
  static String pretty(String? raw) {
    final clean = (raw ?? '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final capped = clean.length > 8 ? clean.substring(0, 8) : clean;
    return capped.length > 4
        ? '${capped.substring(0, 4)}-${capped.substring(4)}'
        : capped;
  }

  /// The code inside whatever was copied (it may include spaces, a dash or the sentence around it).
  static String? extract(String? copied) {
    final match = RegExp(r'\b([A-Za-z0-9]{4})[-\s]?([A-Za-z0-9]{4})\b')
        .firstMatch(copied ?? '');
    return match == null
        ? null
        : '${match.group(1)}-${match.group(2)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [_CodeFormatter()],
      textInputAction: textInputAction,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'ABCD-2345',
        suffixIcon: TextButton.icon(
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final code = extract(data?.text);
            if (code != null) controller.text = code;
          },
          icon: const Icon(LucideIcons.clipboardPaste, size: 18),
          label: Text(t.paste),
        ),
      ),
      validator: (v) =>
          (v == null || v.replaceAll(RegExp(r'[\s-]'), '').length != 8)
          ? invalidMessage
          : null,
    );
  }
}

/// Puts the dash in by itself: typing ABCD2345 shows ABCD-2345.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = CodeField.pretty(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
