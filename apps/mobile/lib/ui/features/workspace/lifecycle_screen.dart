import 'package:flutter/material.dart';

import '../../../data/repositories/group_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import 'lifecycle_view_model.dart';
import 'operation_helpers.dart';
import 'workspace_view_model.dart';

Future<void> manageLifecycle(
  BuildContext context,
  WorkspaceViewModel workspace, {
  required String groupId,
  String? storeId,
  required String name,
  required int version,
  required String status,
}) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => LifecycleScreen(
        model: LifecycleViewModel(
          GroupRepository(
            workspace.repositoryContext,
            workspace.repository,
            workspace.user.id,
          ),
          groupId: groupId,
          storeId: storeId,
          version: version,
          initialStatus: status,
        ),
        name: name,
      ),
    ),
  );
}

class LifecycleScreen extends StatefulWidget {
  final LifecycleViewModel model;
  final String name;
  const LifecycleScreen({super.key, required this.model, required this.name});
  @override
  State<LifecycleScreen> createState() => _LifecycleScreenState();
}

class _LifecycleScreenState extends State<LifecycleScreen> {
  final reason = TextEditingController();
  late String status = widget.model.initialStatus == 'active'
      ? 'suspended'
      : 'active';
  @override
  void initState() {
    super.initState();
    widget.model.load();
  }

  @override
  void dispose() {
    reason.dispose();
    widget.model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final vm = widget.model;
      return FormPage(
        title: vm.storeId == null ? 'Accès au groupe' : 'Accès au magasin',
        action: vm.initialStatus == 'archived'
            ? null
            : FilledButton(
                onPressed: vm.saving || vm.loading || vm.impact == null
                    ? null
                    : () async {
                        if (await vm.save(status, reason.text) &&
                            context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                child: Text(
                  vm.saving
                      ? 'Enregistrement…'
                      : status == 'active'
                      ? 'Réactiver'
                      : status == 'suspended'
                      ? 'Suspendre les accès'
                      : 'Archiver',
                ),
              ),
        children: [
          SectionTitle(
            widget.name,
            subtitle: 'État actuel : ${statusLabel(vm.initialStatus)}',
          ),
          const Text(
            'La suspension bloque les accès et conserve tout l’historique. La réactivation ne rétablit pas les membres désactivés séparément.',
          ),
          const SizedBox(height: 16),
          if (vm.loading) const LinearProgressIndicator(),
          if (vm.impact != null) ...[
            const SectionTitle('À régler avant l’archivage'),
            for (final entry in <String, String>{
              'orders': 'Commandes ouvertes',
              'deliveries': 'Livraisons en transit',
              'issues': 'Incidents ouverts',
              'rewards': 'Récompenses réservées',
              'stockLots': 'Lots avec stock',
            }.entries)
              CompactRow(
                title: entry.value,
                value: '${integer(vm.impact![entry.key])}',
              ),
          ],
          if (vm.initialStatus != 'archived') ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in [
                  'active',
                  'suspended',
                  'archived',
                ].where((s) => s != vm.initialStatus))
                  ChoiceChip(
                    label: Text(statusLabel(value)),
                    selected: status == value,
                    onSelected: vm.saving || vm.hasUncertainSubmission
                        ? null
                        : (_) => setState(() => status = value),
                  ),
              ],
            ),
            if (vm.hasUncertainSubmission && !vm.saving)
              const Notice(
                'La réponse n’a pas été confirmée. Réessayez la même action avant de la modifier.',
              ),
            if (status == 'archived')
              const Notice(
                'L’archivage est définitif. L’historique reste consultable. Réglez d’abord les éléments ci-dessus.',
              ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              enabled: !vm.saving && !vm.hasUncertainSubmission,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Motif obligatoire'),
            ),
            const SizedBox(height: 16),
          ],
          if (vm.error != null) Notice(vm.error!, retry: vm.load),
        ],
      );
    },
  );
}
