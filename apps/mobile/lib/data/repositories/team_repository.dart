import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

class TeamRepository {
  final RepositoryContext context;
  TeamRepository(this.context);
  Future<void> invite(Json input) => context.run(() async {
    await context.api.identityInvite(
      body: IdentityInviteRequestDto.fromJson(input),
    );
  });
}
