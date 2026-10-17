import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            children: [_SupplierChoice(s), _MinimumVersion(s)],
          ),
        ),
      ),
    );
  }
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
  void dispose() {
    _ios.dispose();
    _android.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref.read(appSettingsRepositoryProvider).save({
        'minimumBuild': {
          'ios': int.tryParse(_ios.text.trim()) ?? 0,
          'android': int.tryParse(_android.text.trim()) ?? 0,
        },
      }),
      success: t.saved,
    );
    if (ok) ref.invalidate(appSettingsProvider);
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(7),
    ],
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final build = ref.watch(appBuildProvider).value ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(t.minimumVersionTitle),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(
                t.minimumVersionHint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              _field(_ios, t.minimumIosLabel),
              _field(_android, t.minimumAndroidLabel),
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
                    TextButton(
                      onPressed: () => setState(() {
                        _ios.text = '$build';
                        _android.text = '$build';
                      }),
                      child: Text(t.useThisBuild),
                    ),
                  ],
                ),
              AsyncButton(
                label: t.save,
                icon: LucideIcons.check,
                onPressed: _save,
              ),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(t.supplierChoiceTitle),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.supplierChoiceHint,
                style: context.text.bodyMedium?.copyWith(
                  color: context.status.muted,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.supplierChoiceSwitch),
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
              if (people != null)
                people.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) => list.isEmpty
                      ? Text(t.supplierChoiceNone)
                      : Column(
                          children: [
                            for (final p in list)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: Avatar(p.initials, size: 36),
                                title: Text(p.name),
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
          ),
        ),
        const Gap(16),
      ],
    );
  }
}

final _responsablesProvider = FutureProvider.autoDispose<List<Person>>(
  (ref) => ref
      .watch(networkRepositoryProvider)
      .people(role: 'RESPONSABLE', status: 'ACTIVE'),
);
