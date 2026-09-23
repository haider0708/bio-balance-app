import 'package:flutter/material.dart';

import '../../../data/repositories/store_settings_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../media/image_input.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/lifecycle_screen.dart';
import '../workspace/operation_helpers.dart';

class StoreSettingsPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const StoreSettingsPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final store = vm.state.store, saved = vm.state.data?.raw['store'] as Map?;
      if (store == null || saved == null) {
        return const Content(
          children: [Notice('Choisissez un magasin pour continuer.')],
        );
      }
      return Content(
        children: [
          SectionTitle(
            store.name,
            subtitle: 'Coordonnées et image',
            action: FilledButton.icon(
              onPressed: saved['status'] == 'archived'
                  ? null
                  : () =>
                        edit(context, store, Map<String, dynamic>.from(saved)),
              icon: const Icon(AppIcons.editOutlined),
              label: const Text('Modifier le magasin'),
            ),
          ),
          if (vm.user.admin)
            OutlinedButton(
              onPressed: () => run(context, () async {
                await manageLifecycle(
                  context,
                  vm,
                  groupId: store.organizationId,
                  storeId: store.id,
                  name: store.name,
                  version: integer(saved['version']),
                  status: saved['status'] ?? 'active',
                );
                await vm.initialize();
              }),
              child: Text(
                'Accès au magasin · ${statusLabel(saved['status'] ?? 'active')}',
              ),
            ),
          if (saved['imageId'] != null)
            ProtectedImage(vm: vm, id: saved['imageId'], height: 160),
          CompactRow(
            title: 'Adresse',
            subtitle: '${saved['address']}\n${saved['city']}',
            icon: AppIcons.locationOnOutlined,
          ),
          CompactRow(
            title: 'Téléphone',
            subtitle: '${saved['phone'] ?? ''}'.isEmpty
                ? 'Non renseigné'
                : saved['phone'],
            icon: AppIcons.phoneOutlined,
          ),
        ],
      );
    },
  );
  Future<void> edit(BuildContext context, Store store, Json saved) async {
    if (await openEditor(
      context,
      title: 'Modifier le magasin',
      fields: [
        FieldSpec('name', 'Nom du magasin', initial: saved['name']),
        FieldSpec('address', 'Adresse', initial: saved['address']),
        FieldSpec('city', 'Ville', initial: saved['city']),
        FieldSpec(
          'phone',
          'Téléphone (facultatif)',
          initial: saved['phone'] ?? '',
          required: false,
        ),
        FieldSpec(
          'imageId',
          'Image du magasin',
          initial: saved['imageId'] ?? '',
          required: false,
          imagePurpose: 'store',
        ),
      ],
      submit: (values) async {
        vm.requireAccess(store, 'manage');
        await StoreSettingsRepository(vm.api).update(store, {
          ...values,
          'imageId': values['imageId']!.isEmpty ? null : values['imageId'],
          'expectedVersion': saved['version'],
        });
      },
    )) {
      await vm.initialize();
    }
  }
}
