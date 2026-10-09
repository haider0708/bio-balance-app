import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/app_localizations.dart';

/// Width under which the admin shell uses a drawer instead of a persistent sidebar.
const adminWideBreakpoint = 900.0;

const adminSidebarExpandedWidth = 248.0;
const adminSidebarCollapsedWidth = 72.0;

/// One row in the admin sidebar (or a section title above a group).
class AdminNavEntry {
  const AdminNavEntry.item({
    required this.icon,
    required this.label,
    required this.path,
    this.matchPrefixes = const [],
  }) : isSection = false;

  const AdminNavEntry.section(this.label)
    : icon = null,
      path = null,
      matchPrefixes = const [],
      isSection = true;

  final bool isSection;
  final IconData? icon;
  final String label;
  final String? path;

  /// Extra path prefixes that keep this item selected (e.g. `/pdvs` under Network).
  final List<String> matchPrefixes;

  bool matches(String location) {
    if (path == null) return false;
    if (location == path || location.startsWith('$path/')) return true;
    for (final p in matchPrefixes) {
      if (location == p || location.startsWith('$p/')) return true;
    }
    return false;
  }
}

/// Ordered sidebar contents for the admin console.
List<AdminNavEntry> adminNavEntries(AppLocalizations t) => [
  AdminNavEntry.section(t.navSectionOverview),
  AdminNavEntry.item(icon: LucideIcons.house, label: t.tabHome, path: '/home'),
  AdminNavEntry.section(t.navSectionOperations),
  AdminNavEntry.item(
    icon: LucideIcons.inbox,
    label: t.tabApprovals,
    path: '/approvals',
  ),
  AdminNavEntry.item(
    icon: LucideIcons.network,
    label: t.tabNetwork,
    path: '/network',
    matchPrefixes: ['/pdvs', '/groups', '/people', '/regions'],
  ),
  AdminNavEntry.item(
    icon: LucideIcons.truck,
    label: t.tabRestocks,
    path: '/restocks',
  ),
  AdminNavEntry.item(
    icon: LucideIcons.wallet,
    label: t.payoutsTitle,
    path: '/payouts',
  ),
  AdminNavEntry.section(t.navSectionInsights),
  AdminNavEntry.item(
    icon: LucideIcons.chartNoAxesColumn,
    label: t.tabReports,
    path: '/reports',
    matchPrefixes: ['/stock-attention'],
  ),
  AdminNavEntry.section(t.navSectionCommerce),
  AdminNavEntry.item(
    icon: LucideIcons.package,
    label: t.catalogTitle,
    path: '/catalog',
  ),
  AdminNavEntry.item(
    icon: LucideIcons.banknote,
    label: t.rewardsTitle,
    path: '/rewards',
  ),
  AdminNavEntry.section(t.navSectionContent),
  AdminNavEntry.item(
    icon: LucideIcons.megaphone,
    label: t.announcementsTitle,
    path: '/messages',
  ),
  AdminNavEntry.item(
    icon: LucideIcons.graduationCap,
    label: t.trainingTitle,
    path: '/training/manage',
    matchPrefixes: ['/training'],
  ),
  AdminNavEntry.section(t.navSectionPlaces),
  AdminNavEntry.item(
    icon: LucideIcons.warehouse,
    label: t.grossistesTitle,
    path: '/depots',
  ),
  AdminNavEntry.section(t.navSectionAccount),
  AdminNavEntry.item(
    icon: LucideIcons.bell,
    label: t.notificationsTitle,
    path: '/notifications',
  ),
  AdminNavEntry.item(
    icon: LucideIcons.settings,
    label: t.settingsTitle,
    path: '/settings',
  ),
];

/// Which sidebar destination is active for [location] (path only, no query).
AdminNavEntry? selectedAdminNav(List<AdminNavEntry> entries, String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  AdminNavEntry? best;
  var bestLen = -1;
  for (final e in entries) {
    if (e.isSection || e.path == null) continue;
    if (!e.matches(path)) continue;
    final score = e.path!.length;
    if (score > bestLen) {
      best = e;
      bestLen = score;
    }
  }
  return best;
}
