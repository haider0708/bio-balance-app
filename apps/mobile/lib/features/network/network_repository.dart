import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import 'network_models.dart';

class NetworkRepository {
  NetworkRepository(this._ref);

  final Ref _ref;

  Future<List<Region>> regions() async =>
      jsonList(await _ref.read(apiClientProvider).get('/v1/regions'))
          .map(Region.fromJson)
          .toList();

  // Groups
  Future<List<Group>> groups({String? status, String? regionId}) async =>
      jsonList(
        await _ref
            .read(apiClientProvider)
            .get('/v1/groups', query: {'status': status, 'regionId': regionId}),
      ).map(Group.fromJson).toList();

  Future<void> createGroup(String name) =>
      _ref.read(apiClientProvider).post('/v1/groups', {'name': name});

  Future<void> renameGroup(String id, String name) =>
      _ref.read(apiClientProvider).patch('/v1/groups/$id', {'name': name});

  Future<void> decideGroup(String id, String action, {String? note}) => _ref
      .read(apiClientProvider)
      .post('/v1/groups/$id/$action', {'note': ?note});

  // Points of sale
  Future<List<Pdv>> pdvs({
    String? status,
    String? regionId,
    String? groupId,
  }) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get(
          '/v1/pdvs',
          query: {'status': status, 'regionId': regionId, 'groupId': groupId},
        ),
  ).map(Pdv.fromJson).toList();

  Future<Pdv> pdv(String id) async => Pdv.fromJson(
    await _ref.read(apiClientProvider).get('/v1/pdvs/$id') as Json,
  );

  Future<Pdv> createPdv({
    required String name,
    required String address,
    required String city,
    String? phone,
    String? groupId,
  }) async => Pdv.fromJson(
    await _ref.read(apiClientProvider).post('/v1/pdvs', {
      'name': name,
      'address': address,
      'city': city,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'groupId': ?groupId,
    }) as Json,
  );

  Future<void> updatePdv(String id, Json body) =>
      _ref.read(apiClientProvider).patch('/v1/pdvs/$id', body);

  Future<void> decidePdv(String id, String action, {String? note}) => _ref
      .read(apiClientProvider)
      .post('/v1/pdvs/$id/$action', {'note': ?note});

  // People
  Future<List<Person>> people({
    String? role,
    String? status,
    String? regionId,
    String? pdvId,
    String? q,
  }) async => jsonList(
    await _ref
        .read(apiClientProvider)
        .get(
          '/v1/users',
          query: {
            'role': role,
            'status': status,
            'regionId': regionId,
            'pdvId': pdvId,
            'q': q,
          },
        ),
  ).map(Person.fromJson).toList();

  Future<Person> addMember(
    String pdvId, {
    required String name,
    required String email,
    String? phone,
  }) async => Person.fromJson(
    await _ref.read(apiClientProvider).post('/v1/pdvs/$pdvId/members', {
      'name': name,
      'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    }) as Json,
  );

  Future<Person> createUser(Json body) async => Person.fromJson(
    await _ref.read(apiClientProvider).post('/v1/users', body) as Json,
  );

  Future<void> updatePerson(String id, Json body) =>
      _ref.read(apiClientProvider).patch('/v1/users/$id', body);

  Future<void> decidePerson(String id, String action, {String? note}) => _ref
      .read(apiClientProvider)
      .post('/v1/users/$id/$action', {'note': ?note});

  Future<void> resendInvite(String id) =>
      _ref.read(apiClientProvider).post('/v1/users/$id/resend-invite');

  Future<List<Depot>> depots() async =>
      jsonList(await _ref.read(apiClientProvider).get('/v1/depots'))
          .map(Depot.fromJson)
          .toList();
}

final networkRepositoryProvider = Provider<NetworkRepository>(
  NetworkRepository.new,
);

final regionsProvider = FutureProvider<List<Region>>(
  (ref) => ref.watch(networkRepositoryProvider).regions(),
);

final pdvsProvider = FutureProvider.autoDispose.family<List<Pdv>, String?>(
  (ref, regionId) =>
      ref.watch(networkRepositoryProvider).pdvs(regionId: regionId),
);

final pdvProvider = FutureProvider.autoDispose.family<Pdv, String>(
  (ref, id) => ref.watch(networkRepositoryProvider).pdv(id),
);

final groupsProvider = FutureProvider.autoDispose.family<List<Group>, String?>(
  (ref, regionId) =>
      ref.watch(networkRepositoryProvider).groups(regionId: regionId),
);

final depotsProvider = FutureProvider.autoDispose<List<Depot>>(
  (ref) => ref.watch(networkRepositoryProvider).depots(),
);

/// Everyone a manager may see, filtered by role / point of sale / region.
typedef PeopleQuery = ({
  String? role,
  String? pdvId,
  String? regionId,
  String? status,
});

final peopleProvider = FutureProvider.autoDispose
    .family<List<Person>, PeopleQuery>(
      (ref, q) => ref
          .watch(networkRepositoryProvider)
          .people(
            role: q.role,
            pdvId: q.pdvId,
            regionId: q.regionId,
            status: q.status,
          ),
    );
