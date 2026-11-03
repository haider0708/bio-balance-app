import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'planning_labels.dart';
import 'planning_models.dart';
import 'planning_places.dart';
import 'planning_repository.dart';

const _durations = [30, 60, 90, 120, 180];

/// Plan a visit, or change a planned one: where, what for, when and for how long.
class VisitFormScreen extends ConsumerStatefulWidget {
  const VisitFormScreen({this.day, this.visit, super.key});

  /// The day selected in the calendar (a new visit starts there).
  final DateTime? day;

  /// The visit being changed.
  final Visit? visit;

  @override
  ConsumerState<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends ConsumerState<VisitFormScreen> {
  PlaceOption? _place;
  VisitKind _kind = VisitKind.count;
  late DateTime _date;
  late TimeOfDay _time;
  int _minutes = 60;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final v = widget.visit;
    if (v != null) {
      _place = PlaceOption(
        isDepot: v.target.isDepot,
        id: v.target.id,
        name: v.target.name,
        subtitle: [
          v.target.address,
          v.target.city,
        ].where((s) => s.isNotEmpty).join(', '),
      );
      _kind = v.kind;
      _date = DateTime(
        v.plannedStart.year,
        v.plannedStart.month,
        v.plannedStart.day,
      );
      _time = TimeOfDay.fromDateTime(v.plannedStart);
      _minutes = v.plannedEnd.difference(v.plannedStart).inMinutes;
      _note.text = v.note ?? '';
    } else {
      final base = widget.day ?? DateTime.now();
      _date = DateTime(base.year, base.month, base.day);
      _time = const TimeOfDay(hour: 9, minute: 0);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime get _start =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _save({bool allowOverlap = false}) async {
    final t = AppLocalizations.of(context);
    final repo = ref.read(planningRepositoryProvider);
    final place = _place!;
    final body = <String, Object?>{
      'targetKind': place.kindWire,
      'targetId': place.id,
      'kind': _kind.wire,
      'start': _start.toUtc().toIso8601String(),
      'durationMinutes': _minutes,
      'note': _note.text.trim(),
      if (allowOverlap) 'allowOverlap': true,
    };
    try {
      if (widget.visit == null) {
        await repo.create(body);
      } else {
        await repo.update(widget.visit!.id, body);
        ref.invalidate(visitProvider(widget.visit!.id));
      }
      if (!mounted) return;
      showMessage(context, t.visitSaved);
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'VISIT_OVERLAP') {
        final keep = await confirm(
          context,
          title: t.visitOverlapTitle,
          message: t.visitOverlapBody,
          confirmLabel: t.visitKeepBoth,
        );
        if (keep && mounted) await _save(allowOverlap: true);
        return;
      }
      showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.visit == null ? t.planningPlanVisit : t.visitFormEdit,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.visitPlace, style: context.text.labelLarge),
          const Gap(8),
          AppCard(
            onTap: () async {
              final picked = await PlacePickerSheet.show(context);
              if (picked != null && mounted) setState(() => _place = picked);
            },
            child: Row(
              spacing: 12,
              children: [
                Icon(
                  _place?.isDepot ?? false
                      ? LucideIcons.warehouse
                      : LucideIcons.store,
                ),
                Expanded(
                  child: Text(
                    _place?.name ?? t.visitChoosePlace,
                    style: context.text.titleSmall,
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 18),
              ],
            ),
          ),
          const Gap(20),
          Text(t.visitType, style: context.text.labelLarge),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in VisitKind.values)
                ChoiceChip(
                  // The icon already says what it is; the colour says it is chosen.
                  showCheckmark: false,
                  avatar: Icon(k.icon, size: 16),
                  label: Text(k.label(t)),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          const Gap(20),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null && mounted) {
                      setState(() => _date = picked);
                    }
                  },
                  icon: const Icon(LucideIcons.calendar),
                  label: Text(Dates.full(_date, locale)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _time,
                    );
                    if (picked != null && mounted) {
                      setState(() => _time = picked);
                    }
                  },
                  icon: const Icon(LucideIcons.clock),
                  label: Text(_time.format(context)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
          const Gap(20),
          Text(t.visitDuration, style: context.text.labelLarge),
          const Gap(8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in _durations)
                ChoiceChip(
                  label: Text(t.minutes(m)),
                  selected: _minutes == m,
                  onSelected: (_) => setState(() => _minutes = m),
                ),
            ],
          ),
          const Gap(20),
          TextField(
            controller: _note,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: t.note,
              hintText: t.visitNoteHint,
            ),
          ),
          const Gap(8),
          AsyncButton(label: t.save, onPressed: _place == null ? null : _save),
        ],
      ),
    );
  }
}
