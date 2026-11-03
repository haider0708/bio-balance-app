import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/update/app_update.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_models.dart';
import '../network/network_repository.dart';
import 'app_settings.dart';
import 'setting_widgets.dart';

/// The admin's settings for the whole application: the oldest app version still allowed, and
/// (further down) the working hours and who may choose a grossiste.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.appSettingsTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(appSettingsProvider.future),
        child: AsyncBody(
          value: settings,
          onRetry: () => ref.invalidate(appSettingsProvider),
          builder: (s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _SupplierChoice(s),
              _MinimumVersion(s),
              _WorkingHours(s),
              _WhatsAppCodes(s),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card: what the setting is for, then its controls.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.hint,
    required this.children,
  });

  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text(
                hint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                  height: 1.4,
                ),
              ),
              ...children,
            ],
          ),
        ),
      ],
    ),
  );
}

class _MinimumVersion extends ConsumerStatefulWidget {
  const _MinimumVersion(this.settings);

  final AppSettings settings;

  @override
  ConsumerState<_MinimumVersion> createState() => _MinimumVersionState();
}

class _MinimumVersionState extends ConsumerState<_MinimumVersion> {
  late final _ios = TextEditingController(
    text: '${widget.settings.minimumIos}',
  );
  late final _android = TextEditingController(
    text: '${widget.settings.minimumAndroid}',
  );

  @override
  void initState() {
    super.initState();
    _ios.addListener(_changed);
    _android.addListener(_changed);
  }

  @override
  void dispose() {
    _ios.dispose();
    _android.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  int _value(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Nothing to save until a number differs from what the server holds.
  bool get _dirty =>
      _value(_ios) != widget.settings.minimumIos ||
      _value(_android) != widget.settings.minimumAndroid;

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref.read(appSettingsRepositoryProvider).save({
        'minimumBuild': {'ios': _value(_ios), 'android': _value(_android)},
      }),
      success: t.saved,
    );
    if (ok) ref.invalidate(appSettingsProvider);
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon,
  ) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(7),
    ],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: context.status.muted),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final build = ref.watch(appBuildProvider).value ?? 0;
    return _Section(
      title: t.minimumVersionTitle,
      hint: t.minimumVersionHint,
      children: [
        _field(_ios, t.minimumIosLabel, LucideIcons.smartphone),
        _field(_android, t.minimumAndroidLabel, LucideIcons.tabletSmartphone),
        if (build > 0)
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  t.thisBuild(build),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => setState(() {
                  _ios.text = '$build';
                  _android.text = '$build';
                }),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: Text(t.useThisBuild),
              ),
            ],
          ),
        AsyncButton(
          label: t.save,
          icon: LucideIcons.check,
          onPressed: _dirty ? _save : null,
        ),
      ],
    );
  }
}

/// Whether responsables may suggest the grossiste of a store's restock, and which ones.
class _SupplierChoice extends ConsumerWidget {
  const _SupplierChoice(this.settings);

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final people = settings.supplierChoice
        ? ref.watch(_responsablesProvider)
        : null;
    return _Section(
      title: t.supplierChoiceTitle,
      hint: t.supplierChoiceHint,
      children: [
        SettingGroup(
          children: [
            SettingSwitch(
              title: t.supplierChoiceSwitch,
              value: settings.supplierChoice,
              onChanged: (on) async {
                final ok = await perform(
                  context,
                  () => ref.read(appSettingsRepositoryProvider).save({
                    'supplierChoice': on,
                  }),
                );
                if (ok) ref.invalidate(appSettingsProvider);
              },
            ),
          ],
        ),
        if (people != null)
          people.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? Text(
                    t.supplierChoiceNone,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  )
                : SettingGroup(
                    children: [
                      for (final p in list)
                        SettingSwitch(
                          leading: Avatar(p.initials, size: 36),
                          title: p.name,
                          subtitle: p.email,
                          value: p.canChooseSupplier,
                          onChanged: (on) async {
                            final ok = await perform(
                              context,
                              () => ref
                                  .read(networkRepositoryProvider)
                                  .setSupplierChoice(p.id, allowed: on),
                            );
                            if (ok) ref.invalidate(_responsablesProvider);
                          },
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

final _responsablesProvider = FutureProvider.autoDispose<List<Person>>(
  (ref) => ref
      .watch(networkRepositoryProvider)
      .people(role: 'RESPONSABLE', status: 'ACTIVE'),
);

/// The opening hours, per weekday (Sunday first, like the server), in Tunis time.
class _WorkingHours extends ConsumerStatefulWidget {
  const _WorkingHours(this.settings);

  final AppSettings settings;

  @override
  ConsumerState<_WorkingHours> createState() => _WorkingHoursState();
}

class _WorkingHoursState extends ConsumerState<_WorkingHours> {
  late bool _enabled = widget.settings.hoursEnabled;
  late final List<DayHours?> _days = List.of(widget.settings.days);

  Future<void> _pick(int day, {required bool open}) async {
    final current = _days[day]!;
    final text = open ? current.open : current.close;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(text.substring(0, 2)),
        minute: int.parse(text.substring(3, 5)),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _days[day] = open
          ? DayHours(value, current.close)
          : DayHours(current.open, value);
    });
  }

  bool get _valid =>
      _days.every((d) => d == null || d.open.compareTo(d.close) < 0);

  /// Nothing to save until something differs from what the server holds.
  bool get _dirty {
    final saved = widget.settings;
    if (_enabled != saved.hoursEnabled) return true;
    for (var i = 0; i < 7; i++) {
      final a = _days[i];
      final b = saved.days[i];
      if ((a == null) != (b == null)) return true;
      if (a != null && (a.open != b!.open || a.close != b.close)) return true;
    }
    return false;
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref.read(appSettingsRepositoryProvider).save({
        'hours': {
          'enabled': _enabled,
          'days': [for (final d in _days) d?.toJson()],
        },
      }),
      success: t.hoursSaved,
    );
    if (ok) ref.invalidate(appSettingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = t.localeName;
    return _Section(
      title: t.workingHoursTitle,
      hint: t.workingHoursHint,
      children: [
        SettingGroup(
          children: [
            SettingSwitch(
              title: t.workingHoursSwitch,
              subtitle: widget.settings.open
                  ? t.hoursOpenNow
                  : t.hoursClosedNow,
              value: _enabled,
              onChanged: (on) => setState(() => _enabled = on),
            ),
          ],
        ),
        if (_enabled)
          SettingGroup(
            children: [
              for (var day = 0; day < 7; day++)
                _DayRow(
                  // 7 January 2024 was a Sunday.
                  name: toBeginningOfSentenceCase(
                    DateFormat.E(locale).format(DateTime(2024, 1, 7 + day)),
                  ),
                  hours: _days[day],
                  onOpen: () => _pick(day, open: true),
                  onClose: () => _pick(day, open: false),
                  onChanged: (on) => setState(() {
                    _days[day] = on ? const DayHours('08:00', '21:00') : null;
                  }),
                ),
            ],
          ),
        if (!_valid)
          Text(
            t.hoursInvalid,
            style: context.text.bodySmall?.copyWith(
              color: context.status.danger,
            ),
          ),
        AsyncButton(
          label: t.hoursSave,
          icon: LucideIcons.check,
          onPressed: _valid && _dirty ? _save : null,
        ),
      ],
    );
  }
}

/// One weekday: its name, the opening and closing times in boxes, and whether it is open at all.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.name,
    required this.hours,
    required this.onOpen,
    required this.onClose,
    required this.onChanged,
  });

  final String name;
  final DayHours? hours;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final open = hours != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              name,
              style: context.text.titleSmall?.copyWith(
                color: open ? null : context.status.muted,
              ),
            ),
          ),
          Expanded(
            child: open
                // Shrinks a little on a narrow screen or with a large text size, never overflows.
                ? FittedBox(
                    alignment: AlignmentDirectional.centerStart,
                    fit: BoxFit.scaleDown,
                    child: Row(
                      spacing: 8,
                      children: [
                        TimeBox(hours!.open, onTap: onOpen),
                        Text('–', style: context.text.bodyMedium),
                        TimeBox(hours!.close, onTap: onClose),
                      ],
                    ),
                  )
                : Text(
                    t.closedDay,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
          ),
          Switch(value: open, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Codes (invitations, password resets) also go by WhatsApp, from the dedicated number, when this is on.
class _WhatsAppCodes extends ConsumerWidget {
  const _WhatsAppCodes(this.settings);

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final status = settings.whatsappStatus;
    final configured = status != 'NOT_CONFIGURED';
    final connected = status == 'CONNECTED';
    return _Section(
      title: t.whatsappSettingsTitle,
      hint: t.whatsappSettingsHint,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: StatusChip(
            !configured
                ? t.whatsappNotSetUp
                : connected
                ? t.whatsappConnected
                : t.whatsappDisconnected,
            tone: connected ? Tone.success : Tone.warning,
            icon: connected ? LucideIcons.circleCheck : LucideIcons.circleAlert,
          ),
        ),
        SettingGroup(
          children: [
            SettingSwitch(
              title: t.whatsappSwitch,
              value: settings.whatsappEnabled,
              onChanged: configured
                  ? (on) async {
                      final ok = await perform(
                        context,
                        () => ref.read(appSettingsRepositoryProvider).save({
                          'whatsapp': {'enabled': on},
                        }),
                      );
                      if (ok) ref.invalidate(appSettingsProvider);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
