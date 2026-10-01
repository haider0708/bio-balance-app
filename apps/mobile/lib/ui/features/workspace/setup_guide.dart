import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/store_nature.dart';
import '../../core/design.dart';

/// The steps a new responsable walks through, in order.
enum GuideStep {
  welcome('Bienvenue'),
  group('Votre groupe'),
  stores('Vos magasins'),
  team('Votre équipe'),
  stock('Votre stock de départ'),
  prices('Vos prix de vente'),
  done('C’est prêt');

  final String title;
  const GuideStep(this.title);
}

/// What the guide needs from the app, so it can be shown anywhere and tested alone.
class SetupGuideActions {
  final bool Function() hasGroup;
  final String? Function() groupName;
  final List<Store> Function() stores;
  final Future<void> Function() createGroup;
  final Future<void> Function() addStore;
  final Future<void> Function() inviteTeam;
  final Future<void> Function(Store store) enterStock;
  final Future<void> Function(Store store) noStock;
  final Future<void> Function(Store store) setPrices;
  const SetupGuideActions({
    required this.hasGroup,
    required this.groupName,
    required this.stores,
    required this.createGroup,
    required this.addStore,
    required this.inviteTeam,
    required this.enterStock,
    required this.noStock,
    required this.setPrices,
  });
}

/// Where the guide is, kept across restarts.
class SetupGuideModel extends ChangeNotifier {
  GuideStep step = GuideStep.welcome;
  bool busy = false;
  String? error;
  final Future<void> Function(Map<String, dynamic>) save;
  final String Function(Object error) describe;
  SetupGuideModel({
    required this.save,
    required this.describe,
    GuideStep? start,
  }) : step = start ?? GuideStep.welcome;

  static GuideStep fromName(String? name) =>
      GuideStep.values.where((s) => s.name == name).firstOrNull ??
      GuideStep.welcome;

  void go(GuideStep next) {
    step = next;
    error = null;
    unawaited(save({'step': next.name}).catchError((Object _) {}));
    notifyListeners();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work();
    } catch (e) {
      error = describe(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class SetupGuidePage extends StatelessWidget {
  final SetupGuideModel model;
  final SetupGuideActions actions;
  final VoidCallback onFinish;
  const SetupGuidePage({
    super.key,
    required this.model,
    required this.actions,
    required this.onFinish,
  });

  static const steps = GuideStep.values;

  /// A step that cannot be skipped until it is done.
  bool required(GuideStep step) => switch (step) {
    GuideStep.group => !actions.hasGroup(),
    GuideStep.stores => actions.stores().isEmpty,
    _ => false,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final step = model.step;
      final index = steps.indexOf(step);
      final last = step == GuideStep.done;
      final blocked = required(step);
      return Column(
        children: [
          Expanded(
            child: Content(
              maxWidth: 640,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        last
                            ? 'Terminé'
                            : 'Étape ${index + 1} sur ${steps.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    if (!last)
                      TextButton(
                        onPressed: model.busy ? null : onFinish,
                        child: const Text('Passer le guide'),
                      ),
                  ],
                ),
                LinearProgressIndicator(value: (index + 1) / steps.length),
                const SizedBox(height: 20),
                SectionTitle(step.title),
                ..._body(context, step),
                if (model.error != null) ...[
                  const SizedBox(height: 12),
                  Notice(model.error!, error: true),
                ],
              ],
            ),
          ),
          // Navigation stays in reach whatever the length of the step.
          BottomAction(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (blocked)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Terminez cette étape pour continuer.',
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                  ),
                Row(
                  children: [
                    if (index > 0 && !last)
                      TextButton(
                        onPressed: model.busy
                            ? null
                            : () => model.go(steps[index - 1]),
                        child: const Text('Retour'),
                      ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('guide.next'),
                      onPressed: model.busy || blocked
                          ? null
                          : last
                          ? onFinish
                          : () => model.go(steps[index + 1]),
                      child: Text(
                        last
                            ? 'Ouvrir mon espace'
                            : step == GuideStep.welcome
                            ? 'Commencer'
                            : 'Suivant',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget action(String label, Future<void> Function() work, {IconData? icon}) =>
      FilledButton.tonalIcon(
        onPressed: model.busy ? null : () => model.run(work),
        icon: Icon(icon ?? AppIcons.add, size: 20),
        label: Text(label),
      );

  List<Widget> _body(BuildContext context, GuideStep step) {
    final stores = actions.stores();
    switch (step) {
      case GuideStep.welcome:
        return [
          const Text(
            'En quelques minutes, votre activité est prête. Nous allons ensemble :',
          ),
          const SizedBox(height: 12),
          for (final line in const [
            ('1', 'Créer votre groupe'),
            ('2', 'Ajouter vos magasins'),
            ('3', 'Inviter votre équipe'),
            ('4', 'Déclarer votre stock de départ'),
            ('5', 'Fixer vos prix de vente'),
          ])
            CompactRow(title: line.$2, leading: _number(line.$1)),
          const SizedBox(height: 8),
          const Text(
            'Chaque étape s’explique. Vous pouvez quitter le guide et le reprendre plus tard.',
            style: TextStyle(fontSize: 14, color: muted),
          ),
        ];
      case GuideStep.group:
        return [
          const Text(
            'Un groupe rassemble vos magasins et votre équipe. Exemple : Parahouse.',
          ),
          const SizedBox(height: 16),
          if (actions.hasGroup())
            CompactRow(
              title: actions.groupName() ?? 'Votre groupe',
              subtitle: 'Groupe créé',
              icon: AppIcons.checkCircleOutline,
            )
          else
            action('Créer mon groupe', () async {
              await actions.createGroup();
              if (actions.hasGroup()) model.go(GuideStep.stores);
            }),
        ];
      case GuideStep.stores:
        return [
          const Text(
            'Chaque magasin a son propre stock, ses ventes et ses prix. Un magasin est soit une pharmacie, soit une parapharmacie.',
          ),
          const SizedBox(height: 16),
          for (final store in stores)
            CompactRow(
              title: store.name,
              subtitle: '${storeNatureLabel(store.nature)} · ${store.city}',
              icon: AppIcons.storefrontOutlined,
            ),
          action(
            stores.isEmpty
                ? 'Ajouter mon premier magasin'
                : 'Ajouter un autre magasin',
            actions.addStore,
          ),
        ];
      case GuideStep.team:
        return [
          const Text(
            'Invitez vos vendeurs et vos autres responsables par email. Un vendeur travaille dans un seul magasin ; un responsable gère tout le groupe.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Vous travaillez seul pour le moment ? Passez cette étape : vous pourrez inviter plus tard depuis l’onglet Équipe.',
            style: TextStyle(fontSize: 14, color: muted),
          ),
          const SizedBox(height: 16),
          action(
            'Inviter quelqu’un',
            actions.inviteTeam,
            icon: AppIcons.personAddAlt,
          ),
        ];
      case GuideStep.stock:
        return [
          const Text(
            'Vous avez une seule occasion de déclarer le stock que vous avez déjà. Ensuite, les produits arrivent par commande et livraison, pour que chaque quantité reste vérifiable.',
          ),
          const SizedBox(height: 16),
          for (final store in stores)
            CompactRow(
              title: store.name,
              subtitle: store.openingClosed
                  ? 'Stock de départ déclaré'
                  : 'Avez-vous déjà du stock ?',
              icon: store.openingClosed
                  ? AppIcons.checkCircleOutline
                  : AppIcons.inventory2Outlined,
              footer: store.openingClosed
                  ? null
                  : Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: model.busy
                              ? null
                              : () =>
                                    model.run(() => actions.enterStock(store)),
                          child: const Text('Oui, je le saisis'),
                        ),
                        TextButton(
                          onPressed: model.busy
                              ? null
                              : () => model.run(() => actions.noStock(store)),
                          child: const Text('Non, je commande'),
                        ),
                      ],
                    ),
            ),
        ];
      case GuideStep.prices:
        return [
          const Text(
            'Vous fixez le prix de vente de chaque produit dans votre magasin. Les prix sont conservés avec leur historique : une vente passée ne change jamais.',
          ),
          const SizedBox(height: 16),
          for (final store in stores)
            CompactRow(
              title: store.name,
              subtitle: store.onboardingStep >= 5
                  ? 'Configuration terminée'
                  : 'Prix et seuils à fixer',
              icon: store.onboardingStep >= 5
                  ? AppIcons.checkCircleOutline
                  : AppIcons.tune,
              footer: FilledButton.tonal(
                onPressed: model.busy
                    ? null
                    : () => model.run(() => actions.setPrices(store)),
                child: const Text('Fixer mes prix'),
              ),
            ),
        ];
      case GuideStep.done:
        return [
          const Text(
            'Votre groupe, vos magasins et votre équipe sont en place. Vous pouvez maintenant commander vos produits, suivre le stock et vos ventes.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Vous retrouverez ce guide à tout moment dans « Plus ».',
            style: TextStyle(fontSize: 14, color: muted),
          ),
        ];
    }
  }

  Widget _number(String value) => CircleAvatar(
    radius: 14,
    backgroundColor: darkGreen,
    child: Text(
      value,
      style: const TextStyle(color: Colors.white, fontSize: 13),
    ),
  );
}
