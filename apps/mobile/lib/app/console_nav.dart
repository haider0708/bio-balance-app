import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/auth/me.dart';
import '../l10n/app_localizations.dart';

export '../core/layout/layout.dart'
    show contentMaxWidth, formMaxWidth, isFormPath;

/// Width under which the console uses a drawer instead of a persistent sidebar.
const consoleWideBreakpoint = 900.0;

const consoleSidebarExpandedWidth = 248.0;
const consoleSidebarCollapsedWidth = 72.0;

/// One row in the admin sidebar (or a section title above a group).
class ConsoleNavEntry {
  const ConsoleNavEntry.item({
    required this.icon,
    required this.label,
    required this.path,
    this.matchPrefixes = const [],
  }) : isSection = false;

  const ConsoleNavEntry.section(this.label)
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

/// Ordered sidebar contents of the web console, for the signed-in role: the admin sees the whole
/// network, a responsable their own region.
List<ConsoleNavEntry> consoleNavEntries(AppLocalizations t, Role role) =>
    role == Role.admin ? _adminEntries(t) : _responsableEntries(t);

List<ConsoleNavEntry> _responsableEntries(AppLocalizations t) => [
  ConsoleNavEntry.section(t.navSectionOverview),
  ConsoleNavEntry.item(
    icon: LucideIcons.house,
    label: t.tabHome,
    path: '/home',
  ),
  ConsoleNavEntry.section(t.navSectionOperations),
  ConsoleNavEntry.item(
    icon: LucideIcons.store,
    label: t.tabPdvs,
    path: '/pdvs',
    matchPrefixes: ['/groups', '/people'],
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.truck,
    label: t.tabRestocks,
    path: '/restocks',
  ),
  ConsoleNavEntry.section(t.navSectionInsights),
  ConsoleNavEntry.item(
    icon: LucideIcons.chartNoAxesColumn,
    label: t.tabReports,
    path: '/reports',
    matchPrefixes: ['/stock-attention', '/explore'],
  ),
  ConsoleNavEntry.section(t.navSectionCommerce),
  ConsoleNavEntry.item(
    icon: LucideIcons.package,
    label: t.catalogTitle,
    path: '/catalog',
  ),
  ConsoleNavEntry.section(t.navSectionContent),
  ConsoleNavEntry.item(
    icon: LucideIcons.graduationCap,
    label: t.trainingTitle,
    path: '/training',
  ),
  ConsoleNavEntry.section(t.navSectionPlaces),
  ConsoleNavEntry.item(
    icon: LucideIcons.warehouse,
    label: t.grossistesTitle,
    path: '/depots',
  ),
  ConsoleNavEntry.section(t.navSectionAccount),
  ConsoleNavEntry.item(
    icon: LucideIcons.bell,
    label: t.notificationsTitle,
    path: '/notifications',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.settings,
    label: t.settingsTitle,
    path: '/settings',
  ),
];

List<ConsoleNavEntry> _adminEntries(AppLocalizations t) => [
  ConsoleNavEntry.section(t.navSectionOverview),
  ConsoleNavEntry.item(
    icon: LucideIcons.house,
    label: t.tabHome,
    path: '/home',
  ),
  ConsoleNavEntry.section(t.navSectionOperations),
  ConsoleNavEntry.item(
    icon: LucideIcons.inbox,
    label: t.tabApprovals,
    path: '/approvals',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.network,
    label: t.tabNetwork,
    path: '/network',
    matchPrefixes: ['/pdvs', '/groups', '/people'],
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.truck,
    label: t.tabRestocks,
    path: '/restocks',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.wallet,
    label: t.payoutsTitle,
    path: '/payouts',
  ),
  ConsoleNavEntry.section(t.navSectionInsights),
  ConsoleNavEntry.item(
    icon: LucideIcons.chartNoAxesColumn,
    label: t.tabReports,
    path: '/reports',
    matchPrefixes: ['/stock-attention', '/explore'],
  ),
  ConsoleNavEntry.section(t.navSectionCommerce),
  ConsoleNavEntry.item(
    icon: LucideIcons.package,
    label: t.catalogTitle,
    path: '/catalog',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.banknote,
    label: t.rewardsTitle,
    path: '/rewards',
  ),
  ConsoleNavEntry.section(t.navSectionContent),
  ConsoleNavEntry.item(
    icon: LucideIcons.megaphone,
    label: t.announcementsTitle,
    path: '/messages',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.graduationCap,
    label: t.trainingTitle,
    path: '/training/manage',
    matchPrefixes: ['/training'],
  ),
  ConsoleNavEntry.section(t.navSectionPlaces),
  ConsoleNavEntry.item(
    icon: LucideIcons.map,
    label: t.regions,
    path: '/regions',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.warehouse,
    label: t.grossistesTitle,
    path: '/depots',
  ),
  ConsoleNavEntry.section(t.navSectionAccount),
  ConsoleNavEntry.item(
    icon: LucideIcons.bell,
    label: t.notificationsTitle,
    path: '/notifications',
  ),
  ConsoleNavEntry.item(
    icon: LucideIcons.settings,
    label: t.settingsTitle,
    path: '/settings',
  ),
];

/// Which sidebar destination is active for [location] (path only, no query).
ConsoleNavEntry? selectedConsoleNav(
  List<ConsoleNavEntry> entries,
  String location,
) {
  final path = Uri.tryParse(location)?.path ?? location;
  ConsoleNavEntry? best;
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
