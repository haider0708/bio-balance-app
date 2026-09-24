import 'models.dart';

/// Display capabilities mirror server rules; server transactions remain authoritative.
class OrderWorkflow {
  final String status;
  final bool admin, manager;
  final List<Json> fulfillment;
  OrderWorkflow(
    Json order,
    this.fulfillment, {
    required this.admin,
    required this.manager,
  }) : status = order['status'] ?? 'requested';
  bool get complete =>
      ['received', 'cancelled', 'closed_partial'].contains(status);
  int get inTransit =>
      fulfillment.fold(0, (sum, line) => sum + integer(line['inTransit']));
  int get toDispatch => fulfillment.fold(
    0,
    (sum, line) => sum + integer(line['remainingToDispatch']),
  );
  bool get canPrepare =>
      admin &&
      ['requested', 'partial'].contains(status) &&
      toDispatch > 0 &&
      inTransit == 0;
  bool get canDispatch =>
      admin &&
      !complete &&
      status != 'requested' &&
      !canPrepare &&
      toDispatch > 0;
  bool get canAmend => admin && !complete;
  bool get canCancel =>
      !complete &&
      (admin
          ? toDispatch > 0
          : manager && status == 'requested' && inTransit == 0);
  String get nextStep => switch (status) {
    'requested' => admin ? 'Vérifiez la demande, puis lancez la préparation.' : 'Demande envoyée à BioBalance. Vous pouvez encore l’annuler avant la préparation.',
    'preparing' =>
      admin ? 'Préparez les quantités à envoyer, puis confirmez l’expédition.' : 'BioBalance prépare les produits. Vous pourrez confirmer leur réception après l’expédition.',
    'dispatched' => admin ? 'En attente de la réception du magasin.' : 'Les produits sont en route. Confirmez uniquement ce que vous recevez réellement.',
    'partial' => 'Une partie de la commande reste à recevoir ou un écart est en cours de traitement.',
    'cancelled' =>
      'Commande annulée. Aucune réception supplémentaire n’est attendue.',
    'closed_partial' =>
      'Commande clôturée avec une réception partielle. Le reste a été annulé.',
    _ => 'Commande réceptionnée. Retrouvez les lots et les quantités dans le suivi ci-dessous.',
  };
}
