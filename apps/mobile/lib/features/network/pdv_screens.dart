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
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import '../shared/status_chips.dart';
import 'network_models.dart';
import 'network_repository.dart';
import 'people_widgets.dart';

/// One point of sale: its state, its stock, its team, and what the viewer can do about it.
class PdvDetailScreen extends ConsumerWidget {
  const PdvDetailScreen({required this.pdvId, super.key});

  final String pdvId;

  void _reload(WidgetRef ref) {
    ref.invalidate(pdvProvider(pdvId));
    ref.invalidate(pdvsProvider);
    ref.invalidate(peopleProvider);
    ref.invalidate(approvalsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final pdv = ref.watch(pdvProvider(pdvId));
    final team = ref.watch(
      peopleProvider((
        role: 'VENDEUR',
        pdvId: pdvId,
        regionId: null,
        status: null,
      )),
    );
    final repo = ref.read(networkRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(pdv.value?.name ?? t.pointOfSale),
        actions: [
          if (pdv.hasValue && me.role != Role.vendeur)
            IconButton(
              tooltip: t.edit,
              icon: const Icon(LucideIcons.pencil),
              onPressed: () async {
                await context.push('/pdvs/$pdvId/edit', extra: pdv.value);
                _reload(ref);
              },
            ),
        ],
      ),
      body: AsyncBody(
        value: pdv,
        onRetry: () => _reload(ref),
        builder: (p) => RefreshIndicator(
          onRefresh: () async {
            _reload(ref);
            await ref.read(pdvProvider(pdvId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(p.name, style: context.text.titleLarge),
                        ),
                        ItemStatusChip(p.status),
                      ],
                    ),
                    const Gap(8),
                    InfoRow(t.address, '${p.address}, ${p.city}'),
                    if (p.phone != null) InfoRow(t.phone, p.phone!),
                    if (p.groupName != null) InfoRow(t.group, p.groupName!),
                    if (p.decisionNote != null)
                      InfoRow(t.decision, p.decisionNote!),
                  ],
                ),
              ),
              if (p.status == ItemStatus.pending && me.role == Role.responsable)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Notice(
                    icon: LucideIcons.clock,
                    tone: Tone.warning,
                    text: t.pdvWaitingNotice,
                  ),
                ),
              if (p.status == ItemStatus.rejected &&
                  me.role == Role.responsable)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AsyncButton(
                    label: t.resubmit,
                    icon: LucideIcons.refreshCw,
                    style: AsyncButtonStyle.outlined,
                    onPressed: () async {
                      if (await perform(
                        context,
                        () => repo.decidePdv(p.id, 'resubmit'),
                        success: t.resubmitted,
                      ))
                        _reload(ref);
                    },
                  ),
                ),
              if (me.role == Role.admin) ..._adminActions(context, ref, p),
              SectionHeader(t.stockTitle),
              AppCard(
                onTap: () => context.push('/stock/${p.id}', extra: p.name),
                child: Row(
                  children: [
                    const Icon(LucideIcons.boxes),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(switch (p.initialStock) {
                        'APPROVED' => t.stockApprovedLong,
                        'PENDING' => t.stockWaitingLong,
                        'REJECTED' => t.stockRejectedLong,
                        _ => t.stockMissingLong,
                      }, style: context.text.titleSmall),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: context.status.muted,
                    ),
                  ],
                ),
              ),
              if (me.role == Role.responsable &&
                  p.hasApprovedStock &&
                  p.status == ItemStatus.active) ...[
                const Gap(8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/restocks/new', extra: p.id),
                  icon: const Icon(LucideIcons.truck),
                  label: Text(t.requestRestock),
                ),
              ],
              if (me.role != Role.vendeur) ...[
                const Gap(8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/pdvs/${p.id}/sales'),
                  icon: const Icon(LucideIcons.receipt),
                  label: Text(t.viewSales),
                ),
              ],
              SectionHeader(
                t.team,
                trailing: me.role == Role.responsable
                    ? TextButton.icon(
                        onPressed: () async {
                          await context.push('/pdvs/${p.id}/members/new');
                          _reload(ref);
                        },
                        icon: const Icon(LucideIcons.userPlus, size: 18),
                        label: Text(t.addMember),
                      )
                    : null,
              ),
              AsyncBody(
                value: team,
                onRetry: () => ref.invalidate(peopleProvider),
                isEmpty: (l) => l.isEmpty,
                empty: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t.noTeamYet,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ),
                builder: (list) => Column(
                  children: [
                    for (final person in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PersonTile(
                          person: person,
                          onChanged: () => _reload(ref),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _adminActions(BuildContext context, WidgetRef ref, Pdv p) {
    final t = AppLocalizations.of(context);
    final repo = ref.read(networkRepositoryProvider);
    Future<void> act(String action, String done, {String? note}) async {
      if (await perform(
        context,
        () => repo.decidePdv(p.id, action, note: note),
        success: done,
      ))
        _reload(ref);
    }

    return [
      const Gap(12),
      if (p.status == ItemStatus.pending) ...[
        AsyncButton(
          label: t.approve,
          icon: LucideIcons.check,
          onPressed: () => act('approve', t.approved),
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
            if (note != null) await act('reject', t.rejected, note: note);
          },
        ),
      ],
      if (p.status == ItemStatus.active)
        AsyncButton(
          label: t.suspend,
          icon: LucideIcons.pause,
          style: AsyncButtonStyle.outlined,
          onPressed: () async {
            if (await confirm(
              context,
              title: t.suspendTitle(p.name),
              message: t.suspendPdvBody,
              confirmLabel: t.suspend,
              destructive: true,
            ))
              await act('suspend', t.suspended);
          },
        ),
      if (p.status == ItemStatus.suspended)
        AsyncButton(
          label: t.reactivate,
          icon: LucideIcons.play,
          onPressed: () => act('reactivate', t.reactivated),
        ),
    ];
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.tone, required this.text});

  final IconData icon;
  final Tone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = tone.colors(context);
    return AppCard(
      color: c.soft,
      borderColor: Colors.transparent,
      child: Row(
        children: [
          Icon(icon, color: c.strong, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(
                color: c.strong,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Create (or edit) a point of sale.
class PdvFormScreen extends ConsumerStatefulWidget {
  const PdvFormScreen({this.existing, super.key});

  final Pdv? existing;

  @override
  ConsumerState<PdvFormScreen> createState() => _PdvFormScreenState();
}

class _PdvFormScreenState extends ConsumerState<PdvFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late String? _groupId = widget.existing?.groupId;

  /// The admin chooses the region of a new store; a responsable's is their own.
  String? _regionId;

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final repo = ref.read(networkRepositoryProvider);
    final existing = widget.existing;
    String? createdId;
    final ok = await perform(context, () async {
      if (existing == null) {
        createdId = (await repo.createPdv(
          name: _name.text.trim(),
          address: _address.text.trim(),
          city: _city.text.trim(),
          phone: _phone.text.trim(),
          groupId: _groupId,
          regionId: _regionId,
        )).id;
      } else {
        await repo.updatePdv(existing.id, {
          'name': _name.text.trim(),
          'address': _address.text.trim(),
          'city': _city.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'groupId': _groupId,
        });
      }
    }, success: existing == null ? t.pdvCreated : t.saved);
    if (!ok || !mounted) return;
    ref.invalidate(pdvsProvider);
    ref.invalidate(approvalsProvider);
    if (createdId != null) {
      context.pushReplacement('/pdvs/$createdId');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    final chooseRegion = admin && widget.existing == null;
    final regions = ref.watch(regionsProvider).value ?? const [];
    final groups = ref.watch(groupsProvider(chooseRegion ? _regionId : null));
    String? required(String? v) =>
        (v == null || v.trim().length < 2) ? t.fieldRequired : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? t.newPdv : t.editPdv),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.existing == null && !admin) ...[
              Text(
                t.newPdvHint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(16),
            ],
            if (chooseRegion) ...[
              DropdownButtonFormField<String>(
                initialValue: _regionId,
                decoration: InputDecoration(labelText: t.region),
                items: [
                  for (final r in regions)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() {
                  _regionId = v;
                  _groupId = null;
                }),
                validator: (v) => v == null ? t.fieldRequired : null,
              ),
              const Gap(12),
            ],
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.pdvName),
              validator: required,
            ),
            const Gap(12),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.address),
              validator: required,
            ),
            const Gap(12),
            TextFormField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t.city),
              validator: required,
            ),
            const Gap(12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '${t.phone} (${t.optional})',
              ),
            ),
            const Gap(12),
            groups.maybeWhen(
              data: (list) => DropdownButtonFormField<String?>(
                initialValue: list.any((g) => g.id == _groupId)
                    ? _groupId
                    : null,
                decoration: InputDecoration(
                  labelText: '${t.group} (${t.optional})',
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(t.noGroup),
                  ),
                  for (final g in list)
                    DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() => _groupId = v),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const Gap(24),
            AsyncButton(
              label: widget.existing == null ? t.createPdv : t.save,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// A responsable adds someone to a point of sale. The admin approves before they get access.
class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({required this.pdvId, super.key});

  final String pdvId;

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(networkRepositoryProvider)
          .addMember(
            widget.pdvId,
            name: _name.text.trim(),
            email: _email.text.trim().toLowerCase(),
            phone: _phone.text.trim(),
          ),
      success: t.memberAdded,
    );
    if (ok && mounted) {
      ref.invalidate(approvalsProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.addMember)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              t.addMemberHint,
              style: context.text.bodyMedium?.copyWith(
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
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '${t.phone} (${t.optional})',
              ),
            ),
            const Gap(24),
            AsyncButton(
              label: t.sendForApproval,
              icon: LucideIcons.send,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// The admin creates a responsable, a grossiste or a team member directly.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _form = GlobalKey<FormState>();
  Role _role = Role.responsable;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _depot = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  String? _regionId;
  String? _pdvId;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _depot, _address, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final body = {
      'role': _role.wire,
      'name': _name.text.trim(),
      'email': _email.text.trim().toLowerCase(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      if (_role == Role.responsable || _role == Role.grossiste)
        'regionId': _regionId,
      if (_role == Role.vendeur) 'pdvId': _pdvId,
      if (_role == Role.grossiste)
        'depot': {
          'name': _depot.text.trim(),
          'address': _address.text.trim(),
          'city': _city.text.trim(),
        },
    };
    final ok = await perform(
      context,
      () => ref.read(networkRepositoryProvider).createUser(body),
      success: t.accountCreated,
    );
    if (ok && mounted) {
      ref.invalidate(peopleProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final regions = ref.watch(regionsProvider).value ?? const [];
    final pdvs =
        ref
            .watch(pdvsProvider(null))
            .value
            ?.where((p) => p.status == ItemStatus.active)
            .toList() ??
        const [];
    String? required(String? v) =>
        (v == null || v.trim().length < 2) ? t.fieldRequired : null;
    return Scaffold(
      appBar: AppBar(title: Text(t.newAccount)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<Role>(
              segments: [
                ButtonSegment(
                  value: Role.responsable,
                  label: Text(t.roleResponsable),
                ),
                ButtonSegment(
                  value: Role.grossiste,
                  label: Text(t.roleGrossiste),
                ),
                ButtonSegment(
                  value: Role.vendeur,
                  label: Text(t.roleVendeurShort),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const Gap(8),
            Text(
              t.newAccountHint,
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
              validator: required,
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
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '${t.phone} (${t.optional})',
              ),
            ),
            const Gap(12),
            if (_role == Role.responsable || _role == Role.grossiste)
              DropdownButtonFormField<String>(
                initialValue: _regionId,
                decoration: InputDecoration(labelText: t.region),
                items: [
                  for (final r in regions)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _regionId = v),
                validator: (v) => v == null ? t.fieldRequired : null,
              ),
            if (_role == Role.grossiste)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.grossisteHandledBy,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ),
            if (_role == Role.vendeur)
              DropdownButtonFormField<String>(
                initialValue: _pdvId,
                decoration: InputDecoration(labelText: t.pointOfSale),
                items: [
                  for (final p in pdvs)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _pdvId = v),
                validator: (v) => v == null ? t.fieldRequired : null,
              ),
            if (_role == Role.grossiste) ...[
              TextFormField(
                controller: _depot,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.depotName),
                validator: required,
              ),
              const Gap(12),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.address),
                validator: required,
              ),
              const Gap(12),
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t.city),
                validator: required,
              ),
            ],
            const Gap(24),
            AsyncButton(
              label: t.createAndInvite,
              icon: LucideIcons.mail,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
