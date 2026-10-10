import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_widgets.dart';

String roleLabel(AppLocalizations t, Role role) => switch (role) {
  Role.admin => t.roleAdmin,
  Role.responsable => t.roleResponsable,
  Role.vendeur => t.roleVendeur,
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final where = me.pdv?.name ?? me.region?.name;
    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Row(
              children: [
                Avatar(me.initials, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.name, style: context.text.titleMedium),
                      Text(
                        me.email,
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                      const Gap(6),
                      Wrap(
                        spacing: 6,
                        children: [
                          StatusChip(roleLabel(t, me.role), tone: Tone.success),
                          if (where != null)
                            StatusChip(where, tone: Tone.muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SectionHeader(t.account),
          _Item(
            icon: LucideIcons.userPen,
            label: t.editProfile,
            onTap: () => _editProfile(context, ref, me),
          ),
          _Item(
            icon: LucideIcons.keyRound,
            label: t.changePassword,
            onTap: () => _changePassword(context, ref),
          ),
          SectionHeader(t.language),
          AppCard(
            child: Row(
              children: [
                const Icon(LucideIcons.languages),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.language, style: context.text.titleSmall),
                ),
                const LanguageToggle(),
              ],
            ),
          ),
          SectionHeader(t.appearance),
          AppCard(
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(t.themeAuto),
                  icon: const Icon(LucideIcons.smartphone),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(t.themeLight),
                  icon: const Icon(LucideIcons.sun),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(t.themeDark),
                  icon: const Icon(LucideIcons.moon),
                ),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).choose(s.first),
            ),
          ),
          SectionHeader(t.about),
          AppCard(
            child: Column(children: [InfoRow(t.appVersion, AppConfig.version)]),
          ),
          const Gap(24),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirm(
                context,
                title: t.signOutTitle,
                confirmLabel: t.signOut,
              )) {
                await ref.read(sessionProvider.notifier).logout();
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: context.status.danger,
            ),
            icon: const Icon(LucideIcons.logOut),
            label: Text(t.signOut),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, Me me) async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: me.name);
    final phone = TextEditingController(text: me.phone ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.editProfile, style: context.text.titleLarge),
            const Gap(16),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.fullName),
            ),
            const Gap(12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: t.phone),
            ),
            const Gap(16),
            AsyncButton(
              label: t.save,
              onPressed: () async {
                final ok = await perform(context, () async {
                  await ref
                      .read(authRepositoryProvider)
                      .updateProfile(
                        name: name.text.trim(),
                        phone: phone.text.trim(),
                      );
                  await ref.read(sessionProvider.notifier).refresh();
                }, success: t.saved);
                if (ok && context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    if (saved == true) ref.invalidate(sessionProvider);
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final current = TextEditingController();
    final next = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.changePassword, style: context.text.titleLarge),
            const Gap(16),
            PasswordField(controller: current, label: t.currentPassword),
            const Gap(12),
            PasswordField(
              controller: next,
              label: t.newPassword,
              textInputAction: TextInputAction.done,
            ),
            const Gap(6),
            Text(
              t.passwordRule,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
            const Gap(16),
            AsyncButton(
              label: t.changePassword,
              onPressed: () async {
                if (next.text.length < 8) {
                  showMessage(context, t.passwordTooShort, error: true);
                  return;
                }
                final ok = await perform(
                  context,
                  () => ref
                      .read(authRepositoryProvider)
                      .changePassword(current: current.text, next: next.text),
                  success: t.passwordChangedShort,
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: context.text.titleSmall)),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.status.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// The "More" tab and everything every role shares, as a list of destinations.
class MoreEntry {
  const MoreEntry(
    this.icon,
    this.label,
    this.route, {
    this.tone = Tone.neutral,
  });

  final IconData icon;
  final String label;
  final String route;
  final Tone tone;
}

/// Everything that is not a main tab: who you are on top, then a grid of tiles.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({required this.entries, super.key});

  final List<MoreEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final initials = me.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Scaffold(
      appBar: AppBar(title: Text(t.moreTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          AppCard(
            onTap: () => context.push('/settings'),
            child: Row(
              children: [
                Avatar(initials.isEmpty ? '?' : initials, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me.name, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        [
                          roleLabel(t, me.role),
                          ?me.region?.name,
                          ?me.pdv?.name,
                        ].join(' · '),
                        style: context.text.bodySmall?.copyWith(
                          color: context.status.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: context.status.muted,
                ),
              ],
            ),
          ),
          const Gap(16),
          GridView.extent(
            // Two columns on a phone, three or four in a wide browser window.
            maxCrossAxisExtent: 230,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: [
              for (final e in entries)
                AppCard(
                  onTap: () => context.push(e.route),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconBadge(e.icon, tone: e.tone, size: 42),
                      Text(
                        e.label,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
