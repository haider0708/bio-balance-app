import 'package:flutter/material.dart';

import '../../core/design.dart';
import 'workspace_view_model.dart';
import '../authentication/session_view_model.dart';

const workspaceTips = [
  (
    'Changer d’espace',
    'Le groupe rassemble ses magasins. Choisissez un magasin pour travailler sur son stock, ses ventes et son équipe. Vos brouillons restent dans leur magasin d’origine.',
  ),
  (
    'Enregistrer une vente',
    'Scannez ou recherchez le produit, vérifiez le lot, la quantité et le prix, puis enregistrez. Sans connexion, la vente reste sur ce téléphone jusqu’à la synchronisation.',
  ),
  (
    'Réceptionner une livraison',
    'Ouvrez la livraison et saisissez les quantités réellement reçues, les lots et les dates de péremption. Le stock augmente uniquement lors de la réception.',
  ),
  (
    'Remettre une récompense',
    'Une demande réserve les points du vendeur. Le responsable confirme après avoir remis la récompense ; les points sont alors déduits. Chaque magasin conserve son propre barème.',
  ),
];

class FirstUseHint extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final String storeId;
  const FirstUseHint({
    super.key,
    required this.workspace,
    required this.storeId,
  });
  @override
  State<FirstUseHint> createState() => _FirstUseHintState();
}

class _FirstUseHintState extends State<FirstUseHint> {
  int? index;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final saved = await widget.workspace.repository.draft(
        widget.workspace.user.id,
        widget.storeId,
        'tutorial-progress',
      );
      if (mounted) {
        setState(() {
          error = null;
          index = (saved?['next'] as int? ?? 0).clamp(0, workspaceTips.length);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  Future<void> advance() async {
    if (saving || index == null) return;
    setState(() => saving = true);
    try {
      await widget.workspace.repository.saveDraft(
        widget.workspace.user.id,
        widget.storeId,
        'tutorial-progress',
        {'next': index! + 1},
      );
      if (mounted) setState(() => index = index! + 1);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return Notice(error!, retry: load);
    if (index == null || index! >= workspaceTips.length) {
      return const SizedBox.shrink();
    }
    final tip = workspaceTips[index!];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey('tutorial:${widget.storeId}'),
        tilePadding: EdgeInsets.zero,
        trailing: const Icon(AppIcons.keyboardArrowDown),
        leading: const Icon(AppIcons.help, color: darkGreen),
        title: Text(tip.$1),
        subtitle: Text('Conseil ${index! + 1}/${workspaceTips.length}'),
        children: [
          Text(tip.$2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: saving ? null : advance,
              child: const Text('Compris'),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceHelp extends StatelessWidget {
  const WorkspaceHelp({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aide et premiers pas')),
    body: Content(
      children: [
        const SectionTitle('Des repères pour travailler sereinement'),
        for (final tip in workspaceTips) ...[
          SectionTitle(tip.$1),
          Text(tip.$2),
          const SizedBox(height: 24),
        ],
        const SectionTitle('Une saisie ne passe pas ?'),
        const Text(
          'Consultez Synchronisation pour vérifier les opérations en attente ou à corriger. Ne supprimez pas les données de l’application : vos brouillons et ventes hors connexion y sont conservés.',
        ),
      ],
    ),
  );
}
