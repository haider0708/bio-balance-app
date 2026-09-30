import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/wholesale_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/workspace_scope.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../team/invitations_screen.dart';
import '../workspace/operation_helpers.dart';
import '../workspace/scope_view_model.dart';
import '../workspace/workspace_view_model.dart';

/// BioBalance creates each grossiste, invites its responsible account and
/// enters its opening stock from its depot.
class WholesalersScreen extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final ScopeViewModel? scope;
  const WholesalersScreen({super.key, required this.workspace, this.scope});
  @override
  State<WholesalersScreen> createState() => _WholesalersScreenState();
}

class _WholesalersScreenState extends State<WholesalersScreen> {
  late final repository = WholesaleRepository(
    widget.workspace.repositoryContext,
  );
  List<Json> items = const [];
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final result = await repository.list();
      if (mounted) {
        setState(() {
          items = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Grossistes')),
    body: Content(
      children: [
        SectionTitle(
          'Grossistes',
          subtitle: 'Un compte et un dépôt par grossiste',
          action: IconButton(
            tooltip: 'Actualiser',
            onPressed: loading ? null : load,
            icon: const Icon(AppIcons.refresh),
          ),
        ),
        FilledButton.icon(
          onPressed: loading ? null : create,
          icon: const Icon(AppIcons.add),
          label: const Text('Créer un grossiste'),
        ),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Notice(error!, retry: load),
        if (items.isEmpty && !loading && error == null)
          const EmptyState(
            title: 'Aucun grossiste',
            description: 'Créez un grossiste pour lui confier le stock et la livraison de commandes de magasins.',
            icon: AppIcons.localShippingOutlined,
          ),
        for (final item in items)
          CompactRow(
            title: item['name'],
            subtitle:
                '${item['city']} · ${item['activated'] == true ? (item['contactName'] ?? item['contactEmail']) : 'Invitation envoyée à ${item['contactEmail'] ?? '—'}'}',
            value: statusLabel(item['status']),
            icon: AppIcons.localShippingOutlined,
            tone: item['activated'] == true ? AppTone.info : AppTone.warning,
            onTap: () => open(item),
          ),
      ],
    ),
  );

  PartnerGroup groupOf(Json item) => PartnerGroup(
    id: item['id'],
    name: item['name'],
    kind: 'wholesale',
    status: item['status'],
    phone: item['phone'],
    version: integer(item['version']),
    storeCount: 1,
    canManage: true,
  );

  Future<void> open(Json item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Content(
        children: [
          SectionTitle(
            item['name'],
            subtitle: '${item['address']} · ${item['city']}',
          ),
          CompactRow(
            title: 'Stock, récompenses et points du dépôt',
            subtitle: 'Stock initial, lots, points par unité et récompenses',
            icon: AppIcons.inventory2Outlined,
            onTap: () => Navigator.pop(context, 'depot'),
          ),
          CompactRow(
            title: 'Invitation et accès',
            subtitle: item['activated'] == true
                ? 'Compte activé'
                : 'Renvoyer ou révoquer l’invitation',
            icon: AppIcons.mailOutline,
            onTap: () => Navigator.pop(context, 'invitation'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'invitation') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvitationsScreen(
            workspace: widget.workspace,
            group: groupOf(item),
          ),
        ),
      );
      if (mounted) await load();
      return;
    }
    final scope = widget.scope;
    if (scope == null) return;
    await run(context, () async {
      // Refresh so the new depot is among the stores this account may open.
      await scope.refresh();
      final group = scope.groups.where((g) => g.id == item['id']).firstOrNull;
      final store = widget.workspace.state.stores
          .where((s) => s.id == item['storeId'])
          .firstOrNull;
      if (group == null || store == null) {
        throw const AppFailure(
          'STORE_ACCESS_REVOKED',
          'Ce dépôt n’est pas encore disponible. Actualisez puis réessayez.',
        );
      }
      await scope.selectAssignedStore(group, store);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<void> create() async {
    // One operation id per form keeps a retry from creating a second grossiste.
    final operationId = const Uuid().v4();
    final created = await openEditor(
      context,
      title: 'Créer un grossiste',
      description: 'Le grossiste reçoit une invitation par email. Vous pourrez ensuite saisir son stock initial, ou il le fera lui-même.',
      fields: const [
        FieldSpec('name', 'Nom du grossiste'),
        FieldSpec('email', 'Email du responsable du compte'),
        FieldSpec('address', 'Adresse du dépôt'),
        FieldSpec('city', 'Ville'),
        FieldSpec('phone', 'Téléphone', required: false, numeric: true),
      ],
      draftKey: 'wholesaler-create',
      submit: (values) async {
        await repository.create({
          'name': values['name']!.trim(),
          'email': values['email']!.trim().toLowerCase(),
          'address': values['address']!.trim(),
          'city': values['city']!.trim(),
          if ((values['phone'] ?? '').trim().isNotEmpty)
            'phone': values['phone']!.trim(),
        }, operationId: operationId);
      },
      submitLabel: 'Créer et inviter',
    );
    if (created && mounted) {
      await widget.scope?.refresh();
      await load();
    }
  }
}
