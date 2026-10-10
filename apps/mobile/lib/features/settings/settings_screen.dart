import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/app_version.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/money.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_widgets.dart';
import '../sales/sales_outbox.dart';
import '../wallet/wallet_repository.dart';
import 'legal.dart';

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
                          if (where != null) StatusChip(where),
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
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _ProfileSheet(me: me),
            ),
          ),
          _Item(
            icon: LucideIcons.keyRound,
            label: t.changePassword,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _PasswordSheet(),
            ),
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
                const LanguageToggle(icon: false),
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
          _Item(
            icon: LucideIcons.shieldCheck,
            label: t.privacyPolicy,
            onTap: () => openLegal(context, LegalPage.privacy),
          ),
          _Item(
            icon: LucideIcons.fileText,
            label: t.termsOfUse,
            onTap: () => openLegal(context, LegalPage.terms),
          ),
          AppCard(
            child: InfoRow(
              t.appVersion,
              ref.watch(appVersionProvider).value ?? '…',
            ),
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
          const Gap(8),
          TextButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _DeleteAccountSheet(),
            ),
            style: TextButton.styleFrom(foregroundColor: context.status.danger),
            icon: const Icon(LucideIcons.userX),
            label: Text(t.deleteAccount),
          ),
        ],
      ),
    );
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

/// Name and phone, edited in a sheet that owns its fields.
class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({required this.me});

  final Me me;

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late final _name = TextEditingController(text: widget.me.name);
  late final _phone = TextEditingController(text: widget.me.phone ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SheetBody(
      title: t.editProfile,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: InputDecoration(labelText: t.fullName),
        ),
        const Gap(12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
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
                    name: _name.text.trim(),
                    phone: _phone.text.trim(),
                  );
              await ref.read(sessionProvider.notifier).refresh();
            }, success: t.saved);
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SheetBody(
      title: t.changePassword,
      children: [
        PasswordField(
          controller: _current,
          label: t.currentPassword,
          autofillHints: const [AutofillHints.password],
        ),
        const Gap(12),
        PasswordField(
          controller: _next,
          label: t.newPassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const Gap(6),
        Text(
          t.passwordRule,
          style: context.text.bodySmall?.copyWith(color: context.status.muted),
        ),
        const Gap(16),
        AsyncButton(
          label: t.changePassword,
          onPressed: () async {
            if (_next.text.length < 8) {
              showMessage(context, t.passwordTooShort, error: true);
              return;
            }
            final ok = await perform(
              context,
              () => ref
                  .read(authRepositoryProvider)
                  .changePassword(current: _current.text, next: _next.text),
              success: t.passwordChangedShort,
            );
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

/// Deleting one's own account: what goes, what stays, the money still to be paid, and the
/// password to confirm. Sales still waiting on the phone must be sent first.
class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final vendeur = me.role == Role.vendeur;
    final waiting = vendeur ? ref.watch(salesOutboxProvider).length : 0;
    final balance = vendeur
        ? ref.watch(walletSummaryProvider).value?.availableMillimes ?? 0
        : 0;
    return _SheetBody(
      title: t.deleteAccountTitle,
      children: [
        Text(t.deleteAccountBody, style: context.text.bodyMedium),
        const Gap(8),
        Text(
          t.deleteAccountKept,
          style: context.text.bodySmall?.copyWith(color: context.status.muted),
        ),
        if (balance > 0) ...[
          const Gap(12),
          _Warning(t.deleteAccountBalance(Money.format(balance, t.localeName))),
        ],
        if (waiting > 0) ...[
          const Gap(12),
          _Warning(t.deleteAccountWaitingSales(waiting)),
        ],
        const Gap(16),
        PasswordField(
          controller: _password,
          label: t.password,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
        ),
        const Gap(16),
        AsyncButton(
          label: t.deleteAccountConfirm,
          style: AsyncButtonStyle.danger,
          onPressed: waiting > 0
              ? null
              : () async {
                  if (_password.text.isEmpty) {
                    showMessage(context, t.passwordRequired, error: true);
                    return;
                  }
                  final ok = await perform(
                    context,
                    () => ref
                        .read(authRepositoryProvider)
                        .deleteAccount(_password.text),
                  );
                  if (!ok || !context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  ref.read(sessionProvider.notifier).expire();
                  messenger.showSnackBar(
                    SnackBar(content: Text(t.deleteAccountDone)),
                  );
                },
        ),
        const Gap(8),
        TextButton(
          onPressed: () => openLegal(context, LegalPage.deletion),
          child: Text(t.deleteAccountLearnMore),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.status.warningSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 18,
            color: context.status.warning,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ],
      ),
    ),
  );
}

/// The frame of a settings sheet: title, fields, room for the keyboard.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
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
          Text(title, style: context.text.titleLarge),
          const Gap(16),
          ...children,
        ],
      ),
    ),
  );
}
