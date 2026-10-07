import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import '../settings/settings_screen.dart';
import '../shared/status_chips.dart';
import 'network_models.dart';
import 'network_repository.dart';

/// Ask for one short piece of text.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
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
          Text(title, style: context.text.titleLarge),
          const Gap(16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (v) =>
                v.trim().length >= 2 ? Navigator.pop(context, v.trim()) : null,
          ),
          const Gap(16),
          FilledButton(
            onPressed: () => controller.text.trim().length >= 2
                ? Navigator.pop(context, controller.text.trim())
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}

/// People of the network: the admin sees every role (filterable), a responsable their team.
class PeopleList extends ConsumerStatefulWidget {
  const PeopleList({this.regionId, this.pdvId, super.key});

  final String? regionId;
  final String? pdvId;

  @override
  ConsumerState<PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends ConsumerState<PeopleList> {
  String? _role;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final query = (
      role: me.role == Role.admin ? _role : 'VENDEUR',
      pdvId: widget.pdvId,
      regionId: widget.regionId,
      status: null,
    );
    final people = ref.watch(peopleProvider(query));
    return Column(
      children: [
        if (me.role == Role.admin)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                for (final (value, label) in [
                  (null, t.all),
                  ('RESPONSABLE', t.roleResponsable),
                  ('GROSSISTE', t.roleGrossiste),
                  ('VENDEUR', t.roleVendeur),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _role == value,
                      onSelected: (_) => setState(() => _role = value),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(peopleProvider(query));
              await ref.read(peopleProvider(query).future);
            },
            child: AsyncBody(
              value: people,
              onRetry: () => ref.invalidate(peopleProvider(query)),
              isEmpty: (l) => l.isEmpty,
              empty: ListView(
                children: [
                  EmptyState(icon: LucideIcons.users, title: t.noPeople),
                ],
              ),
              builder: (list) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (context, i) => PersonTile(
                  person: list[i],
                  onChanged: () => ref.invalidate(peopleProvider),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PersonTile extends ConsumerWidget {
  const PersonTile({required this.person, required this.onChanged, super.key});

  final Person person;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: () => showPersonSheet(context, ref, person, onChanged),
      child: Row(
        children: [
          Avatar(
            person.initials,
            tone: switch (person.status) {
              ItemStatus.active => Tone.neutral,
              ItemStatus.pending => Tone.warning,
              _ => Tone.muted,
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name, style: context.text.titleSmall),
                Text(
                  roleLabel(t, person.role),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          if (person.status == ItemStatus.active && !person.activated) ...[
            StatusChip(t.invitationSent, tone: Tone.info),
            const SizedBox(width: 6),
          ],
          ItemStatusChip(person.status),
        ],
      ),
    );
  }
}

/// A person's details with the actions allowed to the viewer.
Future<void> showPersonSheet(
  BuildContext context,
  WidgetRef ref,
  Person person,
  VoidCallback onChanged,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: PersonPanel(
          person: person,
          onChanged: onChanged,
          onDone: () => Navigator.pop(sheet),
        ),
      ),
    ),
  );
}

/// The same details as a full page (opened from the approvals inbox).
class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({required this.person, super.key});

  final Person person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(person.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PersonPanel(
            person: person,
            onChanged: () => ref.invalidate(peopleProvider),
            onDone: () => context.pop(),
          ),
        ],
      ),
    );
  }
}

class PersonPanel extends ConsumerWidget {
  const PersonPanel({
    required this.person,
    required this.onChanged,
    required this.onDone,
    super.key,
  });

  final Person person;
  final VoidCallback onChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.read(meProvider);
    final repo = ref.read(networkRepositoryProvider);
    Future<void> act(Future<void> Function() action, String done) async {
      if (await perform(context, action, success: done)) {
        ref.invalidate(approvalsProvider);
        onChanged();
        onDone();
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Avatar(person.initials, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: context.text.titleLarge),
                  Text(
                    roleLabel(t, person.role),
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ],
              ),
            ),
            ItemStatusChip(person.status),
          ],
        ),
        const Gap(12),
        InfoRow(t.email, person.email),
        if (person.phone != null) InfoRow(t.phone, person.phone!),
        if (me.role == Role.admin && person.role != Role.admin)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                final changed = await _editPerson(context, person);
                if (changed == null || !context.mounted) return;
                await act(() => repo.updatePerson(person.id, changed), t.saved);
              },
              icon: const Icon(LucideIcons.pencil, size: 16),
              label: Text(t.edit),
            ),
          ),
        if (person.decisionNote != null)
          InfoRow(t.decision, person.decisionNote!),
        const Gap(12),
        if (me.role == Role.admin && person.status == ItemStatus.pending) ...[
          AsyncButton(
            label: t.approveAndInvite,
            icon: LucideIcons.check,
            onPressed: () =>
                act(() => repo.decidePerson(person.id, 'approve'), t.approved),
          ),
          const Gap(8),
          AsyncButton(
            label: t.reject,
            style: AsyncButtonStyle.text,
            onPressed: () async {
              final note = await askNote(
                context,
                title: t.rejectReasonTitle,
                confirmLabel: t.reject,
                hint: t.rejectReasonHint,
              );
              if (note != null && context.mounted)
                await act(
                  () => repo.decidePerson(person.id, 'reject', note: note),
                  t.rejected,
                );
            },
          ),
        ],
        if (person.status == ItemStatus.active &&
            !person.activated &&
            person.role != Role.admin)
          AsyncButton(
            label: t.resendInvitation,
            icon: LucideIcons.mail,
            style: AsyncButtonStyle.outlined,
            onPressed: () =>
                act(() => repo.resendInvite(person.id), t.invitationResent),
          ),
        if (person.status == ItemStatus.active &&
            !person.activated &&
            person.role != Role.admin)
          AsyncButton(
            label: t.cancelInvitation,
            icon: LucideIcons.mailX,
            style: AsyncButtonStyle.text,
            onPressed: () async {
              if (await confirm(
                    context,
                    title: t.cancelInvitationTitle(person.name),
                    message: t.cancelInvitationBody,
                    confirmLabel: t.cancelInvitation,
                    destructive: true,
                  ) &&
                  context.mounted) {
                await act(
                  () => repo.cancelInvite(person.id),
                  t.invitationCancelled,
                );
              }
            },
          ),
        // Once the account exists it is deactivated; before that the invitation is cancelled.
        if (person.status == ItemStatus.active &&
            person.id != me.id &&
            person.activated)
          AsyncButton(
            label: t.deactivate,
            icon: LucideIcons.userX,
            style: AsyncButtonStyle.text,
            onPressed: () async {
              if (await confirm(
                    context,
                    title: t.deactivateTitle(person.name),
                    message: t.deactivateBody,
                    confirmLabel: t.deactivate,
                    destructive: true,
                  ) &&
                  context.mounted) {
                await act(
                  () => repo.decidePerson(person.id, 'suspend'),
                  t.deactivated,
                );
              }
            },
          ),
        if (me.role == Role.admin && person.status == ItemStatus.suspended)
          AsyncButton(
            label: t.reactivate,
            icon: LucideIcons.userCheck,
            onPressed: () => act(
              () => repo.decidePerson(person.id, 'reactivate'),
              t.reactivated,
            ),
          ),
      ],
    );
  }
}

/// Name and phone of a person, as the admin corrects them.
Future<Map<String, Object?>?> _editPerson(BuildContext context, Person person) {
  final t = AppLocalizations.of(context);
  final name = TextEditingController(text: person.name);
  final phone = TextEditingController(text: person.phone ?? '');
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.editPerson),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t.fullName),
          ),
          const Gap(10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: t.phone),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            if (name.text.trim().length >= 2) 'name': name.text.trim(),
            'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
          }),
          child: Text(t.save),
        ),
      ],
    ),
  );
}
