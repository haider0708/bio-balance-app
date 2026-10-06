import 'package:flutter/material.dart';

import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_models.dart';
import '../restock/restock_models.dart';
import '../stock/stock_models.dart';

/// Account / group / point-of-sale status.
class ItemStatusChip extends StatelessWidget {
  const ItemStatusChip(this.status, {super.key});

  final ItemStatus status;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (label, tone) = switch (status) {
      ItemStatus.pending => (t.statusWaitingApproval, Tone.warning),
      ItemStatus.active => (t.statusActive, Tone.success),
      ItemStatus.rejected => (t.statusRejected, Tone.danger),
      ItemStatus.suspended => (t.statusSuspended, Tone.muted),
    };
    return StatusChip(label, tone: tone);
  }
}

class DeclarationStatusChip extends StatelessWidget {
  const DeclarationStatusChip(this.status, {super.key});

  final DeclarationStatus status;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (label, tone) = switch (status) {
      DeclarationStatus.pending => (t.statusWaitingApproval, Tone.warning),
      DeclarationStatus.approved => (t.statusApproved, Tone.success),
      DeclarationStatus.rejected => (t.statusRejected, Tone.danger),
    };
    return StatusChip(label, tone: tone);
  }
}

String restockStatusLabel(AppLocalizations t, RestockStatus s) => switch (s) {
  RestockStatus.requested => t.restockRequested,
  RestockStatus.assigned => t.restockAssigned,
  RestockStatus.shipped => t.restockShipped,
  RestockStatus.received => t.restockReceived,
  RestockStatus.completed => t.restockCompleted,
  RestockStatus.cancelled => t.statusCancelled,
};

Tone restockTone(RestockStatus s) => switch (s) {
  RestockStatus.requested => Tone.warning,
  RestockStatus.assigned => Tone.info,
  RestockStatus.shipped => Tone.info,
  RestockStatus.received => Tone.warning,
  RestockStatus.completed => Tone.success,
  RestockStatus.cancelled => Tone.muted,
};

class RestockStatusChip extends StatelessWidget {
  const RestockStatusChip(this.status, {super.key});

  final RestockStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(
    restockStatusLabel(AppLocalizations.of(context), status),
    tone: restockTone(status),
  );
}
