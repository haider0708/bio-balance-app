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
      final result = await widget.vm.rewards.ranking(widget.vm.state.store!);
      if (mounted) setState(() => ranking = objects(result['scores']));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    final vm = widget.vm, data = vm.state.data;
    if (data == null || vm.state.store == null) {
      return const Content(
        children: [Notice('Accès à vérifier. Vos saisies sont conservées.')],
      );
    }
    final rewards = data.list('rewards'), claims = data.list('claims');
    final manage = vm.state.store!.canManage || vm.user.admin;
    return Content.builder(
      itemCount: rewards.length + claims.length + ranking.length + 2,
      itemBuilder: (context, index) {
        if (index < rewards.length) {
          final reward = rewards[index];
          return CompactRow(
            title: reward['title'],
            value: '${reward['cost']} pts',
            subtitle: reward['active'] == false ? 'Archivée' : 'Disponible',
            icon: reward['imageId'] == null ? Icons.redeem_outlined : null,
            leading: reward['imageId'] == null
                ? null
                : SizedBox(
                    width: 40,
                    child: ProtectedImage(
                      vm: vm,
                      id: reward['imageId'],
                      height: 40,
                    ),
                  ),
            onTap: () => rewardDetails(context, reward),
            footer: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed:
                      data.available < integer(reward['cost']) ||
                          reward['active'] == false
                      ? null
                      : () => requestReward(context, reward),
                  child: const Text('Demander cette récompense'),
                ),
                if (manage)
                  TextButton(
                    onPressed: () => configure(context, reward),
                    child: const Text('Modifier la récompense'),
                  ),
              ],
            ),
          );
        }
        var next = index - rewards.length;
        if (next == 0) {
          return const Padding(
            padding: EdgeInsets.only(top: 20),
            child: SectionTitle('Demandes'),
          );
        }
        next--;
        if (next < claims.length) {
          final claim = claims[next];
          return CompactRow(
            title: claim['title'],
            value: '${claim['cost']} pts',
            subtitle:
                '${statusLabel(claim['status'])}${manage ? ' · ${data.list('team').where((m) => m['userId'] == claim['userId']).firstOrNull?['name'] ?? (claim['userId'] == vm.user.id ? vm.user.name : 'Membre de l’équipe')}' : ''}',
            footer: claim['status'] != 'requested'
                ? null
                : Wrap(
                    spacing: 8,
                    children: [
                      if (manage) ...[
                        FilledButton.tonal(
                          onPressed: () => resolve(context, claim, 'fulfilled'),
                          child: const Text('Confirmer la remise'),
                        ),
                        TextButton(
                          onPressed: () => resolve(context, claim, 'rejected'),
                          child: const Text('Refuser'),
                        ),
                      ],
                      TextButton(
                        onPressed: () => resolve(context, claim, 'cancelled'),
                        child: const Text('Annuler la demande'),
                      ),
                    ],
                  ),
          );
        }
        next -= claims.length;
        if (next == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: SectionTitle(
              'Classement du mois',
              subtitle: ranking.isEmpty
                  ? 'Disponible après les premières ventes synchronisées.'
                  : 'Les cadeaux échangés ne diminuent pas votre classement.',
            ),
          );
        }
        final score = ranking[next - 1];
        return CompactRow(
          title: '${score['rank']}. ${score['name']}',
          value: '${score['score']} pts',
        );
      },
      children: [
        SectionTitle(
          'Récompenses',
          subtitle: 'Points et cadeaux du magasin',
          action: manage
              ? OutlinedButton.icon(
                  onPressed: () => configure(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer une récompense'),
                )
              : null,
        ),
        MetricStrip(
          metrics: [
            (label: 'Disponibles', value: '${data.available}'),
            (label: 'Réservés', value: '${data.reserved}'),
            (label: 'Solde', value: '${data.balance}'),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryScreen(
                  vm: vm,
                  resource: 'points',
                  title: 'Historique des points',
                ),
              ),
            ),
            icon: const Icon(Icons.history),
            label: const Text('Historique des points'),
          ),
        ),
        const SizedBox(height: 8),
        const SectionTitle('À échanger'),
        if (rewards.isEmpty)
          const EmptyState(
            title: 'Les récompenses arrivent bientôt',
            description:
                'Le responsable peut créer les récompenses de ce magasin.',
            icon: Icons.redeem_outlined,
          ),
      ],
    );
  }

  Future<void> rewardDetails(BuildContext context, Json reward) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(reward['title']),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reward['imageId'] != null)
                  ProtectedImage(vm: widget.vm, id: reward['imageId']),
                Text('${reward['cost']} points'),
                const SizedBox(height: 12),
                Text(reward['description'] ?? ''),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );

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
        await vm.rewards.save(store, {
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
        });
      },
    )) {
      await vm.synchronize();
    }
  }
}
