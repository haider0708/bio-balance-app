import 'package:flutter/material.dart';

import '../media/image_input.dart';

import '../reporting/history_screen.dart';

import 'package:uuid/uuid.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';

import '../workspace/operation_helpers.dart';

class RewardsPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const RewardsPage({super.key, required this.vm});
  @override
  State<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends State<RewardsPage> {
  List<Json> ranking = [];
  @override
  void initState() {
    super.initState();
    loadRanking();
  }

  Future<void> loadRanking() async {
    try {
      final result = await widget.vm.storeRequest('GET', 'ranking');
      if (mounted) setState(() => ranking = objects(result['scores']));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm, data = vm.state.data!;
    return Content(
      children: [
        SectionTitle(
          'Récompenses',
          subtitle: 'Les points et les cadeaux de ${vm.state.store!.name}.',
          action: vm.state.store!.canManage || vm.user.admin
              ? OutlinedButton.icon(
                  onPressed: () => configure(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer une récompense'),
                )
              : null,
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: darkGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vos points disponibles',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '${data.available}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${data.reserved} réservés · Solde ${data.balance}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HistoryScreen(
                vm: widget.vm,
                resource: 'points',
                title: 'Historique des points',
              ),
            ),
          ),
          icon: const Icon(Icons.history),
          label: const Text('Historique des points'),
        ),
        const SizedBox(height: 24),
        const SectionTitle('À échanger'),
        if (data.list('rewards').isEmpty)
          const EmptyState(
            title: 'Les récompenses arrivent bientôt',
            description:
                'Le responsable peut créer les récompenses de ce magasin.',
            icon: Icons.redeem_outlined,
          ),
        ...data
            .list('rewards')
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (r['imageId'] != null)
                          ProtectedImage(vm: vm, id: r['imageId']),
                        Text(
                          r['title'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (r['description'] != '') Text(r['description']),
                        const SizedBox(height: 8),
                        Text(
                          '${r['cost']} points',
                          style: const TextStyle(
                            color: darkGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (vm.state.store!.canManage || vm.user.admin)
                          TextButton.icon(
                            onPressed: () => configure(context, r),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Modifier la récompense'),
                          ),
                        FilledButton.tonal(
                          onPressed:
                              data.available < integer(r['cost']) ||
                                  r['active'] == false
                              ? null
                              : () => requestReward(context, r),
                          child: const Text('Demander cette récompense'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        const SizedBox(height: 24),
        const SectionTitle('Demandes en cours'),
        ...data
            .list('claims')
            .map(
              (c) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c['title'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${c['cost']} points · ${statusLabel(c['status'])}'),
                      if (c['status'] == 'requested')
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (vm.state.store!.canManage || vm.user.admin) ...[
                              FilledButton.tonal(
                                onPressed: () =>
                                    resolve(context, c, 'fulfilled'),
                                child: const Text('Confirmer la remise'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    resolve(context, c, 'rejected'),
                                child: const Text('Refuser'),
                              ),
                            ],
                            TextButton(
                              onPressed: () => resolve(context, c, 'cancelled'),
                              child: const Text('Annuler la demande'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 24),
        const SectionTitle(
          'Classement du mois',
          subtitle: 'Points gagnés nets. Les échanges de cadeaux ne diminuent pas votre classement.',
        ),
        if (ranking.isEmpty)
          const Text(
            'Le classement sera disponible après les premières ventes synchronisées.',
          ),
        ...ranking.map(
          (r) => ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFEBF5E7),
              child: Text('${r['rank']}'),
            ),
            title: Text(r['name']),
            trailing: Text('${r['score']} pts'),
          ),
        ),
      ],
    );
  }

  Future<void> requestReward(BuildContext context, Json reward) async {
    if (await confirmAction(
      context,
      'Réserver cette récompense ?',
      '${reward['cost']} points seront réservés. Ils seront déduits quand le responsable confirmera la remise.',
    )) {
      if (!context.mounted) return;
      await run(
        context,
        () => widget.vm.online({
          'type': 'reward.request',
          'claimId': const Uuid().v4(),
          'rewardId': reward['id'],
        }),
      );
    }
  }

  Future<void> resolve(
    BuildContext context,
    Json claim,
    String decision,
  ) async {
    if (await confirmAction(
      context,
      decision == 'fulfilled'
          ? 'Confirmer la remise physique ?'
          : 'Traiter cette demande ?',
      decision == 'fulfilled'
          ? 'Confirmez après avoir donné la récompense. Les points et les éventuels produits seront déduits une seule fois.'
          : 'Les points réservés seront libérés.',
    )) {
      if (!context.mounted) return;
      await run(
        context,
        () => widget.vm.online({
          'type': 'reward.resolve',
          'claimId': claim['id'],
          'decision': decision,
        }, expectedVersion: integer(claim['version'])),
      );
    }
  }

  Future<void> configure(BuildContext context, [Json? reward]) async {
    final vm = widget.vm, store = widget.vm.state.store!;
    if (await openEditor(
      context,
      title: reward == null ? 'Créer une récompense' : 'Modifier la récompense',
      fields: [
        FieldSpec(
          'title',
          'Nom de la récompense',
          initial: reward?['title'] ?? '',
        ),
        FieldSpec(
          'imageId',
          'Image de la récompense',
          initial: reward?['imageId'] ?? '',
          required: false,
          imagePurpose: 'reward',
        ),
        FieldSpec(
          'description',
          'Description',
          initial: reward?['description'] ?? '',
          required: false,
          multiline: true,
        ),
        FieldSpec(
          'cost',
          'Coût en points',
          initial: '${reward?['cost'] ?? ''}',
          numeric: true,
        ),
        FieldSpec(
          'product',
          'Produit offert (facultatif)',
          required: false,
          options: {
            'none': 'Aucun produit lié',
            for (final p in vm.state.data!.products) p.id: p.name,
          },
          initial: reward?['productId'] ?? 'none',
        ),
        FieldSpec(
          'quantity',
          'Unités offertes',
          initial: '${reward?['quantity'] ?? 1}',
          numeric: true,
        ),
        FieldSpec(
          'active',
          'Statut',
          initial: reward?['active'] == false ? 'no' : 'yes',
          options: const {'yes': 'Disponible', 'no': 'Archivée'},
        ),
      ],
      submit: (v) async {
        vm.requireAccess(store, 'manage');
        await vm.request(
          'POST',
          '/v1/stores/${store.id}/rewards',
          query: {'organizationId': store.organizationId},
          body: {
            if (reward != null) 'id': reward['id'],
            if (reward != null) 'expectedVersion': reward['version'],
            'imageId': v['imageId']!.isEmpty ? null : v['imageId'],
            'title': v['title'],
            'description': v['description'],
            'cost': whole(v['cost']!),
            'productId': v['product'] == 'none' || v['product'] == ''
                ? null
                : v['product'],
            'quantity': whole(v['quantity']!),
            'active': v['active'] == 'yes',
          },
        );
      },
    )) {
      await vm.synchronize();
    }
  }
}
