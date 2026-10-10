import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/auth/session.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/components.dart';
import '../features/notifications/notifications_repository.dart';
import '../features/settings/settings_screen.dart' show roleLabel;
import '../l10n/app_localizations.dart';
import 'console_nav.dart';

const _collapsedKey = 'admin.sidebar.collapsed';

/// Whether the wide sidebar shows icons only.
class ConsoleSidebarCollapsed extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(preferencesProvider, (_, next) {
      final stored = next.value?.getBool(_collapsedKey);
      if (stored != null && stored != state) state = stored;
    }, fireImmediately: true);
    return false;
  }

  Future<void> toggle() async {
    state = !state;
    await (await ref.read(preferencesProvider.future))
        .setBool(_collapsedKey, state);
  }

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    await (await ref.read(preferencesProvider.future))
        .setBool(_collapsedKey, value);
  }
}

final consoleSidebarCollapsedProvider =
    NotifierProvider<ConsoleSidebarCollapsed, bool>(
      ConsoleSidebarCollapsed.new,
    );

/// The web console: persistent collapsible sidebar on wide screens,
/// drawer + top chrome on phone.
class ConsoleShell extends ConsumerStatefulWidget {
  const ConsoleShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends ConsumerState<ConsoleShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= consoleWideBreakpoint;
    final collapsed = ref.watch(consoleSidebarCollapsedProvider);
    final location = GoRouterState.of(context).uri.toString();
    final t = AppLocalizations.of(context);
    final entries = consoleNavEntries(t, ref.watch(meProvider).role);
    final selected = selectedConsoleNav(entries, location);

    void go(String path) {
      if (GoRouterState.of(context).uri.path != path) context.go(path);
      if (!wide) _scaffoldKey.currentState?.closeDrawer();
    }

    final panel = _SidebarPanel(
      entries: entries,
      selected: selected,
      collapsed: wide && collapsed,
      onNavigate: go,
      onToggleCollapse: wide
          ? () => ref.read(consoleSidebarCollapsedProvider.notifier).toggle()
          : null,
      showCollapseControl: wide,
    );

    // The browser tab names the section: "Network · BioBalance".
    final title = selected == null
        ? t.appName
        : '${selected.label} · ${t.appName}';
    return Title(
      title: title,
      color: context.colors.primary,
      child: _layout(context, wide, panel, t),
    );
  }

  Widget _layout(
    BuildContext context,
    bool wide,
    Widget panel,
    AppLocalizations t,
  ) {
    final location = GoRouterState.of(context).uri.toString();
    void go(String path) {
      if (GoRouterState.of(context).uri.path != path) context.go(path);
      if (!wide) _scaffoldKey.currentState?.closeDrawer();
    }

    if (wide) {
      return Material(
        color: context.theme.scaffoldBackgroundColor,
        child: Row(
          children: [
            panel,
            // Phone-sized screens read badly stretched over a big monitor: keep them to a comfortable width.
            // The page is its own accessibility region: a route inside it would otherwise hide the sidebar from screen readers.
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isFormPath(Uri.parse(location).path)
                          ? consoleFormMaxWidth
                          : consoleContentMaxWidth,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: consoleSidebarExpandedWidth + 8,
        backgroundColor: context.status.card,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(child: panel),
      ),
      body: Column(
        children: [
          _TopBar(
            title: t.appName,
            onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            onNotifications: () => go('/notifications'),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.title,
    required this.onMenu,
    required this.onNotifications,
  });

  final String title;
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.status;
    final unread = ref.watch(unreadCountProvider);
    return Material(
      color: s.card,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: s.hairline)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                onPressed: onMenu,
                icon: const Icon(LucideIcons.menu, size: 22),
              ),
              Expanded(
                child: Text(
                  title,
                  style: context.text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).notificationsTitle,
                onPressed: onNotifications,
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(LucideIcons.bell, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarPanel extends ConsumerWidget {
  const _SidebarPanel({
    required this.entries,
    required this.selected,
    required this.collapsed,
    required this.onNavigate,
    required this.showCollapseControl,
    this.onToggleCollapse,
  });

  final List<ConsoleNavEntry> entries;
  final ConsoleNavEntry? selected;
  final bool collapsed;
  final ValueChanged<String> onNavigate;
  final bool showCollapseControl;
  final VoidCallback? onToggleCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.status;
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final width = collapsed
        ? consoleSidebarCollapsedWidth
        : consoleSidebarExpandedWidth;
    final unread = ref.watch(unreadCountProvider);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: s.card,
        border: Border(right: BorderSide(color: s.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 12 : 16,
              16,
              collapsed ? 12 : 8,
              12,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'B',
                    style: TextStyle(
                      color: context.colors.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.appName,
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          roleLabel(t, me.role),
                          style: context.text.labelSmall?.copyWith(
                            color: s.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (showCollapseControl && onToggleCollapse != null)
                  IconButton(
                    tooltip: collapsed
                        ? t.navExpandSidebar
                        : t.navCollapseSidebar,
                    onPressed: onToggleCollapse,
                    icon: Icon(
                      collapsed
                          ? LucideIcons.panelLeftOpen
                          : LucideIcons.panelLeftClose,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: s.hairline),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                for (final entry in entries)
                  if (entry.isSection)
                    if (!collapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                        child: Text(
                          entry.label.toUpperCase(),
                          style: context.text.labelSmall?.copyWith(
                            color: s.muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontSize: 10.5,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 8)
                  else
                    _NavTile(
                      entry: entry,
                      selected: entry.path == selected?.path,
                      collapsed: collapsed,
                      badge: entry.path == '/notifications' ? unread : 0,
                      onTap: () => onNavigate(entry.path!),
                    ),
              ],
            ),
          ),
          Divider(height: 1, color: s.hairline),
          Padding(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 10 : 12,
              10,
              collapsed ? 10 : 12,
              12,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onNavigate('/settings'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Avatar(me.initials, size: collapsed ? 36 : 40),
                    if (!collapsed) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              me.name,
                              style: context.text.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              me.email,
                              style: context.text.bodySmall?.copyWith(
                                color: s.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.entry,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge = 0,
  });

  final ConsoleNavEntry entry;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final primary = context.colors.primary;
    final fg = selected ? primary : s.muted;
    final bg = selected ? context.colors.primaryContainer : Colors.transparent;

    final icon = Badge(
      isLabelVisible: badge > 0 && collapsed,
      label: Text('$badge'),
      child: Icon(entry.icon, size: 20, color: fg),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Tooltip(
          message: collapsed ? entry.label : '',
          waitDuration: const Duration(milliseconds: 400),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 40,
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
                alignment: collapsed ? Alignment.center : Alignment.centerLeft,
                child: collapsed
                    ? icon
                    : Row(
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.label,
                              style: context.text.labelLarge?.copyWith(
                                color: selected
                                    ? primary
                                    : context.colors.onSurface,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontSize: 13.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badge > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge > 99 ? '99+' : '$badge',
                                style: TextStyle(
                                  color: context.colors.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
