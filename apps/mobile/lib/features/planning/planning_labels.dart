import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import 'planning_models.dart';

extension VisitKindText on VisitKind {
  String label(AppLocalizations t) => switch (this) {
    VisitKind.count => t.visitKindCount,
    VisitKind.delivery => t.visitKindDelivery,
    VisitKind.training => t.visitKindTraining,
    VisitKind.followUp => t.visitKindFollowUp,
    VisitKind.other => t.visitKindOther,
  };

  IconData get icon => switch (this) {
    VisitKind.count => LucideIcons.clipboardList,
    VisitKind.delivery => LucideIcons.truck,
    VisitKind.training => LucideIcons.graduationCap,
    VisitKind.followUp => LucideIcons.messageSquare,
    VisitKind.other => LucideIcons.mapPin,
  };
}

extension VisitStatusText on VisitStatus {
  String label(AppLocalizations t) => switch (this) {
    VisitStatus.planned => t.visitStatusPlanned,
    VisitStatus.onSite => t.visitStatusOnSite,
    VisitStatus.done => t.visitStatusDone,
    VisitStatus.missed => t.visitStatusMissed,
    VisitStatus.cancelled => t.visitStatusCancelled,
  };

  Tone get tone => switch (this) {
    VisitStatus.planned => Tone.info,
    VisitStatus.onSite => Tone.warning,
    VisitStatus.done => Tone.success,
    VisitStatus.missed => Tone.danger,
    VisitStatus.cancelled => Tone.muted,
  };
}

/// "120 m" or "1.4 km".
String distanceText(int meters) =>
    meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1)} km';

extension VisitEventText on VisitEvent {
  String label(AppLocalizations t) => switch (presence) {
    Presence.verified => t.presenceVerified,
    Presence.outOfRange => t.presenceOutOfRange(
      distanceMeters == null ? '?' : distanceText(distanceMeters!),
    ),
    Presence.noFix => t.presenceNoFix,
    Presence.noPosition => t.presenceNoPosition,
  };

  Tone get tone => switch (presence) {
    Presence.verified => Tone.success,
    Presence.outOfRange => Tone.warning,
    Presence.noFix || Presence.noPosition => Tone.muted,
  };

  IconData get icon => switch (presence) {
    Presence.verified => LucideIcons.mapPinCheck,
    Presence.outOfRange => LucideIcons.mapPinOff,
    Presence.noFix || Presence.noPosition => LucideIcons.mapPin,
  };
}
