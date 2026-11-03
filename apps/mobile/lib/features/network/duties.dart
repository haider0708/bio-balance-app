import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import 'network_models.dart';

/// What a team member does in a para.
enum Duty {
  seller(sells: true, buys: false),
  buyer(sells: false, buys: true),
  both(sells: true, buys: true);

  const Duty({required this.sells, required this.buys});

  final bool sells;
  final bool buys;

  static Duty of(Person person) =>
      person.sells ? (person.buys ? both : seller) : buyer;

  String label(AppLocalizations t) => switch (this) {
    seller => t.dutySeller,
    buyer => t.dutyBuyer,
    both => t.dutyBoth,
  };

  String hint(AppLocalizations t) => switch (this) {
    seller => t.dutySellerHint,
    buyer => t.dutyBuyerHint,
    both => t.dutyBothHint,
  };

  IconData get icon => switch (this) {
    seller => LucideIcons.receipt,
    buyer => LucideIcons.truck,
    both => LucideIcons.layers,
  };
}

/// Three cards: seller, buyer, or both, each with what it means.
class DutyPicker extends StatelessWidget {
  const DutyPicker({required this.value, required this.onChanged, super.key});

  final Duty value;
  final ValueChanged<Duty> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      spacing: 8,
      children: [
        for (final d in Duty.values)
          AppCard(
            onTap: () => onChanged(d),
            child: Row(
              spacing: 12,
              children: [
                IconBadge(
                  d.icon,
                  tone: d == value ? Tone.success : Tone.neutral,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.label(t), style: context.text.titleSmall),
                      Text(
                        d.hint(t),
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  d == value ? LucideIcons.circleCheck : LucideIcons.circle,
                  color: d == value
                      ? context.colors.primary
                      : context.status.muted,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The role of a person as managers read it: a team member says what they do.
String personRoleLabel(AppLocalizations t, Person person) =>
    switch (person.role) {
      Role.vendeur || Role.acheteur => Duty.of(person).label(t),
      _ => switch (person.role) {
        Role.admin => t.roleAdmin,
        Role.responsable => t.roleResponsable,
        Role.orders => t.roleOrders,
        _ => t.roleVendeur,
      },
    };
