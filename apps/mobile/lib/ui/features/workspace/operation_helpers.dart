import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';

import '../authentication/session_view_model.dart';

String statusLabel(dynamic status) =>
    {
      'pending': 'En attente de synchronisation',
      'accepted': 'Synchronisation du stock en cours',
      'conflict': 'À vérifier',
      'blocked': 'Opération précédente à vérifier',
      'retryable': 'Nouvelle tentative prévue',
      'requested': 'Demandée',
      'preparing': 'En préparation',
      'dispatched': 'Expédiée',
      'received': 'Réceptionnée',
      'partial': 'Partiellement livrée',
      'fulfilled': 'Remise confirmée',
      'rejected': 'Refusée',
      'cancelled': 'Annulée',
      'closed_partial': 'Terminée · reliquat annulé',
      'lost': 'Perdue',
      'returned': 'Retournée',
      'open': 'À traiter',
      'in_progress': 'Recherche en cours',
      'resolved': 'Résolu',
      'suspended': 'Suspendu',
      'archived': 'Archivé',
      'active': 'Actif',
    }[status] ??
    '$status';
Future<void> run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(SessionViewModel.message(e))));
    }
  }
}

String receiptCondition(Json line) => switch (line['condition']) {
  'damaged' => 'non vendables',
  'refused' => 'refusées',
  _ => 'vendables',
};
