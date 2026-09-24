import 'package:biobalance/data/repositories/invitation_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/repositories/repository_context.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/invitation.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class LostResponseApi extends ApiClient {
  LostResponseApi() : super(baseUrl: 'http://unused') {
    authenticate('fixture', accountId: 'actor');
  }
  final calls = <InvitationManagementActionRequestDto>[];
  bool loseResponse = true;
  @override
  Future<InvitationManagementActionResponseDto> invitationManagementAction({
    required String id,
    required InvitationManagementActionRequestDto body,
  }) async {
    calls.add(body);
    if (loseResponse) {
      loseResponse = false;
      throw const AppFailure('NETWORK', 'Réessayez');
    }
    return InvitationManagementActionResponseDto(id: id);
  }
}

void main() {
  test(
    'invitation retries keep their identity after the editor is reopened',
    () async {
      final api = LostResponseApi(), db = AppDatabase(NativeDatabase.memory());
      final local = OfflineRepository(db, api),
          context = RepositoryContext(api);
      final item = Invitation.fromJson({
        'id': 'invite',
        'email': 'test@example.test',
        'kind': 'salesperson',
        'status': 'pending',
        'storeIds': ['store'],
        'version': 1,
        'expiresAt': '2026-09-25T10:00:00Z',
      });
      final first = InvitationRepository(context, local, 'actor');
      await expectLater(first.act(item, 'resend'), throwsA(isA<AppFailure>()));
      final reopened = InvitationRepository(context, local, 'actor');
      await reopened.act(item, 'resend');
      expect(api.calls[0].operationId, api.calls[1].operationId);
      expect(api.calls[0].toJson(), api.calls[1].toJson());
      await db.close();
    },
  );
  test(
    'invitation policies keep accepted access separate from removable history',
    () {
      final item = Invitation.fromJson({
        'id': 'invite',
        'email': 'test@example.test',
        'kind': 'responsible',
        'status': 'accepted',
        'storeIds': [],
        'version': 2,
        'expiresAt': '2026-09-25T10:00:00Z',
      });
      expect(item.canResend, false);
      expect(item.canRevoke, false);
      expect(item.canArchive, true);
    },
  );
}
