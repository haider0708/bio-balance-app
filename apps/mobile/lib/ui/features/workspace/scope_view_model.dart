import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import 'dart:async';

import '../../../data/services/api/session_transport.dart';

import '../../../data/repositories/group_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/workspace_scope.dart';
import '../authentication/session_view_model.dart';
import 'workspace_view_model.dart';

class ScopeViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  late final GroupRepository repository = GroupRepository(
    workspace.repositoryContext,
    workspace.repository,
    workspace.user.id,
  );
  WorkspaceScope scope = const WorkspaceScope.network();
  List<PartnerGroup> groups = const [];
  List<String> grants = const [];
  bool loading = true, switching = false, refreshing = false, closed = false;
  String? error;
  final Map<String, int> tabs = {};
  final _history = <({WorkspaceScope scope, int tab})>[];
  bool get canGoBack => _history.isNotEmpty || tab != 0;
  Future<void> back() async {
    if (switching) return;
    if (tab != 0) {
      await workspace.flushDrafts();
      tabs[scope.key] = 0;
      if (!closed) notifyListeners();
      return;
    }
    while (_history.isNotEmpty) {
      final previous = _history.last;
      final group = previous.scope.group;
      if (group != null &&
          (!groups.any((g) => g.id == group.id) ||
              previous.scope.store != null &&
                  !_available(previous.scope.store!))) {
        _history.removeLast();
        continue;
      }
      await _switch(previous.scope, remember: false, restoredTab: previous.tab);
      _history.removeLast();
      if (!closed) notifyListeners();
      return;
    }
  }

  final Set<String> revokedGroups = {};
  Future<void>? _refreshing;
  bool _confirmedDirectory = false;
  int _accessEpoch = 0;
  late final StreamSubscription<AccessEvent> _events;
  ScopeViewModel(this.workspace) {
    _events = workspace.api.accessEvents.listen((event) {
      if (event.binding.generation !=
              workspace.repositoryContext.binding.generation ||
          event.condition != AccessCondition.groupAccessRevoked ||
          event.groupId == null) {
        return;
      }
      unawaited(
        revoke(event.groupId!).catchError((Object e) {
          error = SessionViewModel.message(e);
          if (!closed) notifyListeners();
        }),
      );
    });
  }
  Future<void> revoke(String id) async {
    _accessEpoch++;
    revokedGroups.add(id);
    groups = groups.where((g) => g.id != id).toList();
    if (scope.group?.id == id) await workspace.denyAccess(scope.store?.id);
    await workspace.repository.saveDraft(
      workspace.user.id,
      '',
      'group-access',
      {'revoked': revokedGroups.toList()},
    );
    if (!closed) notifyListeners();
  }

  bool _available(Store store) {
    try {
      workspace.requireAccess(store);
      return true;
    } on AppFailure {
      return false;
    }
  }

  List<Store> storesFor(String? groupId) => workspace.state.stores
      .where((s) => s.organizationId == groupId && _available(s))
      .toList();
  List<Store> get stores => storesFor(scope.group?.id);
  Future<void> selectAssignedStore(PartnerGroup group, Store store) async {
    if (!storesFor(group.id).any((s) => s.id == store.id)) {
      throw const AppFailure('STORE_ACCESS_REVOKED', 'Magasin inaccessible.');
    }
    await _switch(WorkspaceScope.store(group, store));
  }

  int get tab => tabs[scope.key] ?? 0;
  void setTab(int value) {
    if (switching || value == tab) return;
    tabs[scope.key] = value;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      revokedGroups.addAll(
        List<String>.from(
          (await workspace.repository.draft(
                workspace.user.id,
                '',
                'group-access',
              ))?['revoked'] ??
              [],
        ),
      );
      final cached = await repository.cached();
      groups = cached.groups
          .where((g) => !revokedGroups.contains(g.id))
          .toList();
      grants = cached.grants;
      await refresh();
      await _openFirstWorkspace();
    } catch (e) {
      error = SessionViewModel.message(e);
    } finally {
      loading = false;
      if (!closed) notifyListeners();
    }
  }

  Future<void> _openFirstWorkspace() async {
    // A newly granted workspace must open after refresh, while an existing
    // workspace and its navigation history remain undisturbed.
    if (closed || workspace.user.admin || scope.kind != ScopeKind.network) {
      return;
    }
    final epoch = _accessEpoch;
    final managed = groups.where((g) => g.canManage).toList();
    final saved = await workspace.repository.draft(
      workspace.user.id,
      '',
      managed.isNotEmpty ? 'navigation' : 'selection',
    );
    if (closed || epoch != _accessEpoch || scope.kind != ScopeKind.network) {
      return;
    }
    workspace.repositoryContext.check();
    if (managed.isNotEmpty) {
      final group =
          managed.where((g) => g.id == saved?['groupId']).firstOrNull ??
          managed.first;
      await _switch(WorkspaceScope.group(group), remember: false);
      return;
    }
    final assigned = workspace.state.stores.where(_available).toList();
    if (assigned.isEmpty) return;
    final store =
        assigned.where((s) => s.id == saved?['storeId']).firstOrNull ??
        assigned.first;
    final group = groups.where((g) => g.id == store.organizationId).firstOrNull;
    if (group != null) {
      await _switch(WorkspaceScope.store(group, store), remember: false);
    }
  }

  Future<void> refresh() {
    if (closed) return Future.value();
    if (_refreshing != null) return _refreshing!;
    refreshing = true;
    final pending = _refresh().whenComplete(() {
      _refreshing = null;
      refreshing = false;
      if (!closed) notifyListeners();
    });
    _refreshing = pending;
    notifyListeners();
    return pending;
  }

  Future<void> _refresh() async {
    final epoch = _accessEpoch;
    await workspace.initialize(autoSelect: false);
    try {
      final fresh = await repository.refresh();
      if (closed || epoch != _accessEpoch) return;
      if (!_confirmedDirectory) {
        // A new authenticated workspace can recover a restored membership, but
        // cached selectors and in-flight responses cannot restore revoked access.
        revokedGroups.removeWhere((id) => fresh.groups.any((g) => g.id == id));
        await workspace.repository.saveDraft(
          workspace.user.id,
          '',
          'group-access',
          {'revoked': revokedGroups.toList()},
        );
        _confirmedDirectory = true;
      }
      groups = fresh.groups
          .where((g) => !revokedGroups.contains(g.id))
          .toList();
      grants = fresh.grants;
      final currentGroup = scope.group;
      if (currentGroup != null) {
        final updated = groups
            .where((g) => g.id == currentGroup.id)
            .firstOrNull;
        if (updated == null) {
          await revoke(currentGroup.id);
        } else {
          scope = scope.store == null
              ? WorkspaceScope.group(updated)
              : WorkspaceScope.store(updated, scope.store!);
        }
      }
      await _openFirstWorkspace();
      error = null;
    } catch (e) {
      error = SessionViewModel.message(e);
      if (e is DioException &&
          e.response == null &&
          !closed &&
          epoch == _accessEpoch) {
        workspace.repositoryContext.check();
        // An older installed version cached authorized stores but had no group
        // directory. Preserve those stores offline without inferring group roles.
        final known = groups.map((g) => g.id).toSet();
        for (final store in workspace.state.stores) {
          if (!revokedGroups.contains(store.organizationId) &&
              _available(store) &&
              known.add(store.organizationId)) {
            groups = [
              ...groups,
              PartnerGroup(
                id: store.organizationId,
                name: store.organizationName,
                canManage: false,
              ),
            ];
          }
        }
      }
      if (groups.isEmpty) rethrow;
    }
    if (!closed) notifyListeners();
  }

  Future<void> returnToAdministration() async {
    if (!workspace.user.admin || switching || closed) return;
    await _switch(const WorkspaceScope.network(), remember: false);
    // Clear only after the draft flush and switch succeed.
    _history.clear();
    if (!closed) notifyListeners();
  }

  Future<void> selectGroup(PartnerGroup? group) async {
    if (group == null && !workspace.user.admin) return;
    if (group != null && !group.canManage && !workspace.user.admin) {
      final assigned = workspace.state.stores
          .where((s) => s.organizationId == group.id)
          .firstOrNull;
      if (assigned == null) {
        throw const AppFailure(
          'STORE_ACCESS_REVOKED',
          'Aucun magasin attribué dans ce groupe.',
        );
      }
      await _switch(WorkspaceScope.store(group, assigned));
      return;
    }
    await _switch(
      group == null
          ? const WorkspaceScope.network()
          : WorkspaceScope.group(group),
    );
  }

  Future<void> selectStore(Store? store) async {
    final group = scope.group;
    if (group == null) return;
    if (store == null && !group.canManage && !workspace.user.admin) return;
    if (store != null && !stores.any((s) => s.id == store.id)) {
      throw const AppFailure('STORE_ACCESS_REVOKED', 'Magasin inaccessible.');
    }
    await _switch(
      store == null
          ? WorkspaceScope.group(group)
          : WorkspaceScope.store(group, store),
    );
  }

  void _remember() {
    _history.add((scope: scope, tab: tab));
    if (_history.length > 50) _history.removeAt(0);
  }

  Future<void> _switch(
    WorkspaceScope next, {
    bool remember = true,
    int? restoredTab,
  }) async {
    if (switching || closed) return;
    switching = true;
    notifyListeners();
    try {
      await workspace.flushDrafts();
      if (next.group != null && !groups.any((g) => g.id == next.group!.id)) {
        throw const AppFailure(
          'GROUP_ACCESS_REVOKED',
          'Ce groupe n’est plus accessible.',
        );
      }
      await workspace.repository.saveDraft(
        workspace.user.id,
        '',
        'navigation',
        {'groupId': next.group?.id, 'storeId': next.store?.id},
      );
      if (next.store != null) {
        await workspace.select(next.store!);
      } else {
        workspace.releaseStore();
      }
      if (closed) return;
      if (remember && next.key != scope.key) _remember();
      scope = next;
      if (restoredTab != null) tabs[next.key] = restoredTab;
      error = null;
    } catch (e) {
      error = SessionViewModel.message(e);
      rethrow;
    } finally {
      switching = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    _events.cancel();
    super.dispose();
  }
}
