import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_repository.dart';
import 'messages_repository.dart';

/// Announcements the admin has sent or scheduled.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final messages = ref.watch(announcementsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.announcementsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () async {
          await context.push('/messages/new');
          ref.invalidate(announcementsProvider);
        },
        icon: const Icon(LucideIcons.megaphone),
        label: Text(t.newAnnouncement),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(announcementsProvider);
          await ref.read(announcementsProvider.future);
        },
        child: AsyncBody(
          value: messages,
          onRetry: () => ref.invalidate(announcementsProvider),
          isEmpty: (l) => l.isEmpty,
          empty: ListView(
            children: [
              EmptyState(
                icon: LucideIcons.megaphone,
                title: t.noAnnouncements,
                message: t.noAnnouncementsHint,
              ),
            ],
          ),
          builder: (list) {
            final scheduled = list.where((m) => m.scheduled).toList();
            final sent = list.where((m) => !m.scheduled).toList();
            Widget card(Announcement m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => context.push('/messages/${m.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(m.title, style: context.text.titleSmall),
                        ),
                        if (m.pinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(LucideIcons.pin, size: 16),
                          ),
                      ],
                    ),
                    const Gap(4),
                    Text(
                      m.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                    const Gap(10),
                    Row(
                      children: [
                        Icon(
                          m.scheduled ? LucideIcons.clock : LucideIcons.send,
                          size: 14,
                          color: context.status.muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${Dates.dateTime(m.scheduledFor ?? m.sentAt ?? m.createdAt, t.localeName)} · ${t.sentTo(m.recipientCount)}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                        ),
                        if (!m.scheduled && m.recipientCount > 0)
                          StatusChip(
                            t.readOf(m.readCount, m.recipientCount),
                            tone: m.readCount == m.recipientCount
                                ? Tone.success
                                : Tone.muted,
                            icon: LucideIcons.eye,
                          ),
                      ],
                    ),
                    if (!m.scheduled && m.recipientCount > 0) ...[
                      const Gap(8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: m.readCount / m.recipientCount,
                          minHeight: 4,
                          backgroundColor: context.status.mutedSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (scheduled.isNotEmpty) ...[
                  SectionHeader(t.scheduledSection),
                  for (final m in scheduled) card(m),
                ],
                if (sent.isNotEmpty) ...[
                  SectionHeader(t.sentSection),
                  for (final m in sent) card(m),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class MessageDetailScreen extends ConsumerWidget {
  const MessageDetailScreen({required this.messageId, super.key});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final data = ref.watch(recipientsProvider(messageId));
    return Scaffold(
      appBar: AppBar(title: Text(t.announcement)),
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(recipientsProvider(messageId)),
        builder: (d) {
          final m = d.message;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title, style: context.text.titleLarge),
                    const Gap(8),
                    SelectableText(m.body, style: context.text.bodyLarge),
                    const Gap(12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (m.pinned)
                          StatusChip(
                            t.pinned,
                            tone: Tone.info,
                            icon: LucideIcons.pin,
                          ),
                        if (m.scheduled)
                          StatusChip(
                            t.scheduledFor(
                              Dates.dateTime(m.scheduledFor!, t.localeName),
                            ),
                            tone: Tone.info,
                          )
                        else
                          StatusChip(
                            t.readOf(m.readCount, m.recipientCount),
                            tone: Tone.success,
                            icon: LucideIcons.eye,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (m.scheduled) ...[
                const Gap(16),
                AsyncButton(
                  label: t.withdrawAnnouncement,
                  icon: LucideIcons.trash2,
                  style: AsyncButtonStyle.outlined,
                  onPressed: () async {
                    if (!await confirm(
                          context,
                          title: t.withdrawTitle,
                          message: t.withdrawBody,
                          confirmLabel: t.withdrawAnnouncement,
                          destructive: true,
                        ) ||
                        !context.mounted)
                      return;
                    if (await perform(
                          context,
                          () => ref
                              .read(messagesRepositoryProvider)
                              .withdraw(m.id),
                          success: t.withdrawn,
                        ) &&
                        context.mounted) {
                      ref.invalidate(announcementsProvider);
                      context.pop();
                    }
                  },
                ),
              ],
              SectionHeader(t.recipients),
              for (final r in d.recipients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(
                    r.name.isEmpty ? '?' : r.name[0].toUpperCase(),
                    size: 36,
                    tone: r.readAt == null ? Tone.muted : Tone.success,
                  ),
                  title: Text(r.name),
                  subtitle: Text(
                    r.readAt == null
                        ? t.notReadYet
                        : t.readAt(Dates.dateTime(r.readAt!, t.localeName)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Write an announcement, choose who gets it (the count updates as you choose), send now or later.
class ComposeMessageScreen extends ConsumerStatefulWidget {
  const ComposeMessageScreen({super.key});

  @override
  ConsumerState<ComposeMessageScreen> createState() =>
      _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends ConsumerState<ComposeMessageScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  Audience _audience = const Audience();
  bool _pinned = false;
  DateTime? _scheduledFor;
  int? _recipients;
  bool _counting = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _change(Audience next) {
    setState(() => _audience = next);
    _debounce?.cancel();
    if (next.isEmpty) {
      setState(() => _recipients = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _counting = true);
      try {
        final result = await ref.read(messagesRepositoryProvider).preview(next);
        if (mounted) setState(() => _recipients = result.recipients);
      } catch (_) {
        if (mounted) setState(() => _recipients = null);
      } finally {
        if (mounted) setState(() => _counting = false);
      }
    });
  }

  Set<String> _toggle(Set<String> set, String value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  Future<void> _schedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return;
    setState(
      () => _scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    if (!await confirm(
      context,
      title: _scheduledFor == null
          ? t.sendNowTitle(_recipients ?? 0)
          : t.scheduleTitle,
      confirmLabel: _scheduledFor == null ? t.send : t.schedule,
    ))
      return;
    if (!mounted) return;
    final ok = await perform(
      context,
      () => ref
          .read(messagesRepositoryProvider)
          .send(
            title: _title.text.trim(),
            body: _body.text.trim(),
            audience: _audience,
            pinned: _pinned,
            scheduledFor: _scheduledFor,
          ),
      success: _scheduledFor == null
          ? t.announcementSent
          : t.announcementScheduled,
    );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final regions = ref.watch(regionsProvider).value ?? const [];
    final pdvs = ref.watch(pdvsProvider(null)).value ?? const [];
    final valid =
        _title.text.trim().length >= 2 &&
        _body.text.trim().length >= 2 &&
        !_audience.isEmpty &&
        (_recipients ?? 0) > 0;
    Widget chip(String label, bool selected, VoidCallback onTap) => FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.newAnnouncement)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: t.title),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(8),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 10,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.message,
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          SectionHeader(t.whoIsItFor),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(
                t.everyone,
                _audience.all,
                () => _change(
                  _audience.all ? const Audience() : const Audience(all: true),
                ),
              ),
              if (!_audience.all) ...[
                chip(
                  t.roleResponsablePlural,
                  _audience.roles.contains('RESPONSABLE'),
                  () => _change(
                    _audience.copyWith(
                      roles: _toggle(_audience.roles, 'RESPONSABLE'),
                    ),
                  ),
                ),
                chip(
                  t.roleVendeurPlural,
                  _audience.roles.contains('VENDEUR'),
                  () => _change(
                    _audience.copyWith(
                      roles: _toggle(_audience.roles, 'VENDEUR'),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!_audience.all) ...[
            const Gap(12),
            Text(t.inRegions, style: context.text.labelLarge),
            const Gap(6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in regions)
                  chip(
                    r.name,
                    _audience.regionIds.contains(r.id),
                    () => _change(
                      _audience.copyWith(
                        regionIds: _toggle(_audience.regionIds, r.id),
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(12),
            OutlinedButton.icon(
              onPressed: () async {
                final chosen = await showModalBottomSheet<Set<String>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _PdvChooser(
                    pdvs: [for (final p in pdvs) (p.id, p.name)],
                    selected: _audience.pdvIds,
                  ),
                );
                if (chosen != null) _change(_audience.copyWith(pdvIds: chosen));
              },
              icon: const Icon(LucideIcons.store),
              label: Text(
                _audience.pdvIds.isEmpty
                    ? t.choosePdvs
                    : t.pdvsChosen(_audience.pdvIds.length),
              ),
            ),
          ],
          const Gap(12),
          AppCard(
            color: (_recipients ?? 0) > 0
                ? context.colors.primaryContainer
                : context.status.mutedSoft,
            borderColor: Colors.transparent,
            child: Row(
              children: [
                Icon(LucideIcons.users, color: context.colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _audience.isEmpty
                        ? t.chooseAudience
                        : (_counting
                              ? t.counting
                              : t.willReach(_recipients ?? 0)),
                    style: context.text.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
            title: Text(t.pinAnnouncement),
            subtitle: Text(t.pinAnnouncementHint),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.clock),
            title: Text(
              _scheduledFor == null
                  ? t.sendNowOption
                  : t.scheduledFor(
                      Dates.dateTime(_scheduledFor!, t.localeName),
                    ),
            ),
            trailing: _scheduledFor == null
                ? TextButton(onPressed: _schedule, child: Text(t.schedule))
                : IconButton(
                    onPressed: () => setState(() => _scheduledFor = null),
                    icon: const Icon(LucideIcons.x),
                  ),
          ),
          const Gap(8),
          AsyncButton(
            label: _scheduledFor == null ? t.send : t.schedule,
            icon: LucideIcons.send,
            onPressed: valid ? _send : null,
          ),
        ],
      ),
    );
  }
}

class _PdvChooser extends StatefulWidget {
  const _PdvChooser({required this.pdvs, required this.selected});

  final List<(String, String)> pdvs;
  final Set<String> selected;

  @override
  State<_PdvChooser> createState() => _PdvChooserState();
}

class _PdvChooserState extends State<_PdvChooser> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(t.choosePdvs, style: context.text.titleLarge),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                for (final (id, name) in widget.pdvs)
                  CheckboxListTile(
                    value: _selected.contains(id),
                    title: Text(name),
                    onChanged: (v) => setState(
                      () => v! ? _selected.add(id) : _selected.remove(id),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: Text(t.done),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
