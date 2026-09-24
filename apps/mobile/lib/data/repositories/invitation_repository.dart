import 'package:uuid/uuid.dart';

import '../../domain/models/invitation.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';
import 'offline_repository.dart';

class InvitationPage {
  final List<Invitation> items;
  final String? next;
  const InvitationPage(this.items, this.next);
}

class InvitationRepository {
  final RepositoryContext context;
  final OfflineRepository local;
  final String accountId;
  InvitationRepository(this.context, this.local, this.accountId);
  Future<InvitationPage> list({
    String? groupId,
    String? after,
    bool archived = false,
  }) => context.run(() async {
    final page = await context.api.invitationManagementList(
      organizationId: groupId,
      after: after,
      includeArchived: '$archived',
    );
    return InvitationPage(
      page.items.map((i) => Invitation.fromJson(i.toJson())).toList(),
      page.nextCursor,
    );
  });
  Future<void> act(Invitation invitation, String action) =>
      context.run(() async {
        final key =
            'invitation-action:${invitation.id}:${invitation.version}:$action';
        final saved = await local.draft(accountId, '', key);
        final operation = saved?['operationId'] as String? ?? const Uuid().v4();
        await local.saveDraft(accountId, '', key, {'operationId': operation});
        context.check();
        await context.api.invitationManagementAction(
          id: invitation.id,
          body: InvitationManagementActionRequestDto(
            action: action,
            expectedVersion: invitation.version,
            operationId: operation,
          ),
        );
        context.check();
        // A completed server action must not be reported as failed if cleanup fails.
        try {
          await local.saveDraft(accountId, '', key, {});
        } catch (_) {}
      });
}
