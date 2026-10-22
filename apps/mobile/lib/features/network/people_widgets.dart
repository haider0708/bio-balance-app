import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../analytics/analytics_widgets.dart' show AnalyticsButton;
import '../analytics/lens.dart' show Facet;
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import '../settings/settings_screen.dart';
import '../shared/status_chips.dart';
import 'network_models.dart';
import 'person_sales.dart';
import 'network_repository.dart';
import 'region_moves.dart';
import '../../core/layout/layout.dart';
import '../../core/util/phone.dart';
import 'invite_widgets.dart';

/// Ask for one short piece of text.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? initial,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _TextSheet(
    title: title,
    label: label,
    confirmLabel: confirmLabel,
    initial: initial,
  ),
);

/// The sheet owns its text field's controller, so it lives exactly as long as the sheet.
class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.initial,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? initial;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final text = _controller.text.trim();
    if (text.length >= 2) Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + sheetBottomInset(context)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: context.text.titleLarge),
        const Gap(16),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _done(),
        ),
        const Gap(16),
        FilledButton(onPressed: _done, child: Text(widget.confirmLabel)),
      ],
    ),
  );
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          if (person.role == Role.vendeur)
            AnalyticsButton(facet: Facet.seller, id: person.id),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PersonPanel(
            person: person,
            onChanged: () => ref.invalidate(peopleProvider),
            onDone: () => context.pop(),
          ),
          // What a team member sold, and the way to correct a sale (the admin and the responsable).
          if (person.role == Role.vendeur &&
              person.status == ItemStatus.active &&
              (ref.watch(meProvider).role == Role.admin ||
                  ref.watch(meProvider).role == Role.responsable)) ...[
            const Gap(20),
            PersonSales(person: person),
          ],
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
        if (person.phone != null) InfoRow(t.phone, formatPhone(person.phone!)),
        if (me.role == Role.admin && person.role != Role.admin)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                final changed = await _editPerson(context, person);
                if (changed == null || changed.isEmpty || !context.mounted) {
                  return;
                }
                await act(() => repo.updatePerson(person.id, changed), t.saved);
              },
              icon: const Icon(LucideIcons.pencil, size: 16),
              label: Text(t.edit),
            ),
          ),
        if (person.decisionNote != null)
          InfoRow(t.decision, person.decisionNote!),
        if (me.role == Role.admin && person.role == Role.responsable)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                if (await moveResponsableFlow(context, ref, person)) {
                  onChanged();
                  onDone();
                }
              },
              icon: const Icon(LucideIcons.moveRight, size: 16),
              label: Text(t.moveToRegion),
            ),
          ),
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

/// Everything about a person, as the admin corrects it: name, email, WhatsApp number and (for a team
/// member) the store. Only what changed is returned. A changed email or number sends an unused
/// invitation again to the new contacts.
Future<Map<String, Object?>?> _editPerson(
  BuildContext context,
  Person person,
) => showModalBottomSheet<Map<String, Object?>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => _EditPersonSheet(person: person),
);

class _EditPersonSheet extends ConsumerStatefulWidget {
  const _EditPersonSheet({required this.person});

  final Person person;

  @override
  ConsumerState<_EditPersonSheet> createState() => _EditPersonSheetState();
}

class _EditPersonSheetState extends ConsumerState<_EditPersonSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.person.name);
  late final _email = TextEditingController(text: widget.person.email);
  late final _phone = TextEditingController(
    text: widget.person.phone == null ? '' : formatPhone(widget.person.phone!),
  );
  late String? _pdvId = widget.person.pdvId;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final p = widget.person;
    final email = _email.text.trim().toLowerCase();
    final phone = normalizeTunisianPhone(_phone.text)!;
    Navigator.pop(context, {
      if (_name.text.trim() != p.name) 'name': _name.text.trim(),
      if (email != p.email) 'email': email,
      if (phone != p.phone) 'phone': phone,
      if (_pdvId != null && _pdvId != p.pdvId) 'pdvId': _pdvId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = widget.person;
    final stores = (ref.watch(pdvsProvider(null)).value ?? const <Pdv>[])
        .where((s) => s.regionId == p.regionId && s.status == ItemStatus.active)
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Text(t.editPerson, style: context.text.titleMedium),
            const Gap(4),
            Text(
              t.editPersonHint,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
            const Gap(16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.fullName),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? t.fieldRequired : null,
            ),
            const Gap(12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.email),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? t.emailInvalid : null,
            ),
            const Gap(12),
            PhoneField(controller: _phone),
            if (p.role == Role.vendeur && stores.isNotEmpty) ...[
              const Gap(12),
              DropdownButtonFormField<String>(
                initialValue: stores.any((s) => s.id == _pdvId) ? _pdvId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.pointOfSale),
                items: [
                  for (final s in stores)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _pdvId = v),
              ),
            ],
            if (!p.activated && p.status == ItemStatus.active) ...[
              const Gap(8),
              Text(
                t.editPersonInviteNote,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ],
            const Gap(16),
            FilledButton(onPressed: _save, child: Text(t.save)),
            const Gap(8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
