import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../workspace/operation_helpers.dart';

enum OrderSection {
  all('Toutes'),
  issues('Problèmes'),
  preparation('À préparer'),
  transit('À réceptionner'),
  complete('Terminées');

  final String label;
  const OrderSection(this.label);
  bool contains(Json order) => switch (this) {
    all => true,
    issues => integer(order['openIssues']) > 0,
    preparation => [
      'requested',
      'preparing',
      'partial',
    ].contains(order['status']),
    transit => order['status'] == 'dispatched',
    complete => [
      'received',
      'cancelled',
      'closed_partial',
    ].contains(order['status']),
  };
  String title(bool admin) => admin && this == transit ? 'Expédiées' : label;
  String description(bool admin) => switch (this) {
    all =>
      'Toutes les commandes de cet espace, avec leur magasin et leur suivi.',
    issues => 'Livraisons signalées et écarts de réception à traiter.',
    preparation =>
      admin ? 'Demandes des magasins et compléments restant à expédier.' : 'BioBalance prépare vos produits. Ouvrez une commande pour suivre son avancement.',
    transit => 'Les produits sont en route. Le stock augmente seulement après réception.',
    complete => 'Commandes réceptionnées et historique des livraisons.',
  };
}

class OrderSections extends StatefulWidget {
  final OrderSection selected;
  final bool admin;
  final ValueChanged<OrderSection> onChanged;
  const OrderSections({
    super.key,
    required this.selected,
    required this.admin,
    required this.onChanged,
  });
  @override
  State<OrderSections> createState() => _OrderSectionsState();
}

class _OrderSectionsState extends State<OrderSections> {
  final scroll = ScrollController();
  final anchors = {
    for (final section in OrderSection.values) section: GlobalKey(),
  };
  @override
  void initState() {
    super.initState();
    revealSelection();
  }

  @override
  void didUpdateWidget(covariant OrderSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) revealSelection();
  }

  void revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = anchors[widget.selected]?.currentContext;
      if (anchor != null && scroll.hasClients) {
        scroll.position.ensureVisible(
          anchor.findRenderObject()!,
          alignment: .5,
        );
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final section in OrderSection.values)
                  Padding(
                    key: anchors[section],
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('orders.${section.name}'),
                      label: Text(section.title(widget.admin)),
                      selected: section == widget.selected,
                      onSelected: (_) => widget.onChanged(section),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.selected.description(widget.admin),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class OrderRow extends StatelessWidget {
  final Json order;
  final String storeName, groupName;
  final VoidCallback? onTap;
  const OrderRow({
    super.key,
    required this.order,
    required this.storeName,
    required this.groupName,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final id = '${order['id']}';
    final reference = id.substring(0, id.length.clamp(0, 8)).toUpperCase();
    return CompactRow(
      title: storeName,
      subtitle:
          '$groupName\nCommande $reference · ${TunisDates.timestampLabel(order['createdAt'])}\n${objects(order['lines']).fold<int>(0, (s, l) => s + integer(l['quantity']))} unités demandées',
      icon: AppIcons.package,
      tone: order['status'] == 'received' ? AppTone.success : AppTone.info,
      footer: StatusChip(
        statusLabel(order['status']),
        icon: order['status'] == 'received'
            ? AppIcons.checkCircleOutline
            : AppIcons.package,
        tone: order['status'] == 'received' ? AppTone.success : AppTone.info,
      ),
      onTap: onTap,
    );
  }
}
