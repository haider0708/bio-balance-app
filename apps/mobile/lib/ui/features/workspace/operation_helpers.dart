import 'package:flutter/material.dart';

import '../authentication/session_view_model.dart';

String statusLabel(dynamic status) =>
    {
      'requested': 'Demandée',
      'preparing': 'En préparation',
      'dispatched': 'Expédiée',
      'received': 'Réceptionnée',
      'partial': 'Partiellement livrée',
      'fulfilled': 'Remise confirmée',
      'rejected': 'Refusée',
      'cancelled': 'Annulée',
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
