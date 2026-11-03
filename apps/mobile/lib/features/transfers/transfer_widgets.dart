import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import 'transfer_models.dart';

extension TransferStatusText on TransferStatus {
  String label(AppLocalizations t) => switch (this) {
    TransferStatus.pending => t.transferStatusPending,
    TransferStatus.approved => t.transferStatusApproved,
    TransferStatus.rejected => t.transferStatusRejected,
    TransferStatus.cancelled => t.transferStatusCancelled,
    TransferStatus.expired => t.transferStatusExpired,
  };

  Tone get tone => switch (this) {
    TransferStatus.pending => Tone.info,
    TransferStatus.approved => Tone.success,
    TransferStatus.rejected => Tone.danger,
    TransferStatus.cancelled || TransferStatus.expired => Tone.muted,
  };
}

/// One transfer in a list: who gives to whom, how many units, where it stands.
class TransferCard extends StatelessWidget {
  const TransferCard({required this.transfer, required this.onTap, super.key});

  final Transfer transfer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          const IconBadge(LucideIcons.arrowLeftRight, size: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  '${transfer.from.name} → ${transfer.to.name}',
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${transfer.number} · ${t.units(transfer.units)} · ${t.byName(transfer.createdBy)}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                Text(
                  Dates.dateTime(transfer.createdAt, t.localeName),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                const SizedBox(height: 2),
                StatusChip(
                  transfer.status.label(t),
                  tone: transfer.status.tone,
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: context.status.muted),
        ],
      ),
    );
  }
}
