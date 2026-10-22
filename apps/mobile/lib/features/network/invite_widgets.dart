import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/phone.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';

/// The WhatsApp number of a new account (required: the code is sent there as well as by email). It reads
/// "21 345 678", "+216 21 345 678", "00216 21345678"; the form keeps the canonical "+21621345678".
class PhoneField extends StatelessWidget {
  const PhoneField({
    required this.controller,
    this.textInputAction = TextInputAction.next,
    super.key,
  });

  final TextEditingController controller;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: t.phoneWhatsapp,
        hintText: '21 345 678',
        helperText: t.phoneHint,
        prefixIcon: const Icon(LucideIcons.messageCircle),
      ),
      validator: (v) => (v == null || v.trim().isEmpty)
          ? t.phoneRequired
          : normalizeTunisianPhone(v) == null
          ? t.phoneInvalid
          : null,
    );
  }
}

/// "Check before sending": the person's name, email and number, and where the code will go. Returns
/// whether to go on; a typo in an email or a number is found here, not after the invitation is lost.
Future<bool> confirmInvite(
  BuildContext context, {
  required String name,
  required String email,
  required String phone,
  required String place,
  required bool afterApproval,
}) async {
  final t = AppLocalizations.of(context);
  final yes = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.confirmInviteTitle, style: context.text.titleMedium),
            const Gap(12),
            _Line(LucideIcons.userRound, name),
            _Line(LucideIcons.mail, email),
            _Line(LucideIcons.messageCircle, formatPhone(phone)),
            if (place.isNotEmpty) _Line(LucideIcons.store, place),
            const Gap(8),
            Text(
              afterApproval
                  ? t.confirmInviteNoteApproval
                  : t.confirmInviteNoteNow,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
            const Gap(16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.confirmSend),
            ),
            const Gap(8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.confirmEdit),
            ),
          ],
        ),
      ),
    ),
  );
  return yes ?? false;
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.status.muted),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: context.text.bodyLarge)),
      ],
    ),
  );
}
