import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

/// One native editable field supports paste, autofill and screen readers;
/// the eight cells are only its visual presentation, not eight focus targets.
class RecoveryCodeField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  const RecoveryCodeField({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  @override
  State<RecoveryCodeField> createState() => _RecoveryCodeFieldState();
}

class _RecoveryCodeFieldState extends State<RecoveryCodeField> {
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    focus.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: widget.controller,
    builder: (context, value, _) {
      if (value.text.length > 9) {
        return TextField(
          key: const ValueKey('auth.token'),
          controller: widget.controller,
          enabled: widget.enabled,
          decoration: const InputDecoration(labelText: 'Code reçu par email'),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Code de récupération',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Stack(
            children: [
              ExcludeSemantics(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final split =
                        constraints.maxWidth <
                        MediaQuery.textScalerOf(context).scale(24) * 8 + 36;
                    Widget cells(int start, int end) => Row(
                      children: [
                        for (var i = start; i < end; i++) ...[
                          if (i > start) SizedBox(width: i == 4 ? 12 : 4),
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 52),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F8F4),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      focus.hasFocus &&
                                          i == value.text.length.clamp(0, 7)
                                      ? darkGreen
                                      : const Color(0xFFDCE8DF),
                                ),
                              ),
                              child: Text(
                                i < value.text.length ? value.text[i] : '–',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                    return split
                        ? Column(
                            children: [
                              cells(0, 4),
                              const SizedBox(height: 8),
                              cells(4, 8),
                            ],
                          )
                        : cells(0, 8);
                  },
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: TextField(
                    key: const ValueKey('auth.token'),
                    controller: widget.controller,
                    focusNode: focus,
                    enabled: widget.enabled,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Code reçu par email, 8 lettres et chiffres',
                    ),
                    inputFormatters: [
                      TextInputFormatter.withFunction((old, next) {
                        // Accept still-valid legacy links pasted during the update.
                        if (RegExp(r'^[A-Za-z0-9_-]{32,256}$')
                            .hasMatch(next.text.trim())) {
                          return next;
                        }
                        final text = next.text.toUpperCase().replaceAll(
                          RegExp('[^A-Z0-9]'),
                          '',
                        );
                        final clipped = text.length > 8
                            ? text.substring(0, 8)
                            : text;
                        return TextEditingValue(
                          text: clipped,
                          selection: TextSelection.collapsed(
                            offset: clipped.length,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '8 lettres et chiffres · vous pouvez coller le code entier.',
            style: TextStyle(fontSize: 14, color: muted),
          ),
        ],
      );
    },
  );
}
