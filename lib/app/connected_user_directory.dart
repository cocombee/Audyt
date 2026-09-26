import 'accounting_components.dart';

import 'dart:convert';

import 'membership_service.dart';
import 'user_directory.dart';
import '../features/accounting/domain/payee.dart';

/// Owns one verified account/business session. No profile label grants access.
/// The composition owner must dispose this instance on sign-out/company change.
class ConnectedUserDirectory extends PagedUserDirectory {
  ConnectedUserDirectory(this.service);
  final MembershipService service;
  ServiceMembership? _self;
  ServiceMembership? get membership => _disposed ? null : _self;
  DateTime? refreshedAt;
  MembershipPage? _page;
  int _generation = 0;
  bool _disposed = false;
  bool _commandBusy = false;
  MembershipMutation? _uncertain;

  @override
  Future<ServiceClaimantContext?> findClaimants(String search) async {
    if (_disposed) return null;
    try {
      final result = await service.claimants(search);
      return _disposed ? null : result;
    } on MembershipFailure {
      if (_disposed) return null;
      rethrow;
    }
  }

  @override
  Future<List<Payee>> findEmployeePayees(String search) async {
    if (_disposed) return const [];
    final result = await service.employeePayees(search);
    if (_disposed) return const [];
    return result;
  }

  @override
  bool loading = false;
  @override
  String? error;
  @override
  int offset = 0;
  @override
  int pageSize = AccountingRecordPageSizes.read('users');
  @override
  String search = '';
  @override
  bool get isPreview => false;
  @override
  bool get hasUnconfirmedChange => _uncertain != null;

  @override
  Future<void> retryUnconfirmedChange() async {
    final command = _uncertain;
    if (command == null) return;
    if (!canManageUsers || _commandBusy || loading) {
      throw StateError(
        'Check access and wait for the current request to finish.',
      );
    }
    await _sendCommand(command);
  }

  @override
  bool get canManageUsers => !_disposed && (_self?.isDirector ?? false);
  @override
  int get total => canManageUsers ? _page?.total ?? 0 : 0;
  @override
  int get matched => canManageUsers ? _page?.matched ?? 0 : 0;
  @override
  int get pendingCount => canManageUsers ? _page?.pendingCount ?? 0 : 0;
  @override
  List<RegisteredUser> get users => !canManageUsers
      ? const []
      : List.unmodifiable([
          for (final user in _page?.users ?? <ServiceUser>[])
            RegisteredUser(
              id: user.id,
              name: user.name,
              email: user.email,
              submittedAt: DateTime.parse(user.submittedAt),
              status: RegistrationStatus.values.byName(user.status),
              role: user.role == null
                  ? null
                  : BusinessRole.values.byName(user.role!),
              revision: user.revision,
            ),
        ]);

  bool _isCurrent(RegisteredUser user) =>
      canManageUsers &&
      (_page?.users.any(
            (entry) =>
                entry.id == user.id &&
                entry.revision == user.revision &&
                entry.status == user.status.name &&
                entry.role == user.role?.name,
          ) ??
          false);

  @override
  String? removalRestriction(RegisteredUser user) {
    if (!_isCurrent(user)) return 'Review the latest user details first.';
    if (user.id == _self!.identityId) {
      return 'You cannot remove your own access.';
    }
    if (user.id == _self!.masterDirectorId) {
      return 'The Master Director’s access is protected.';
    }
    if (user.role == BusinessRole.director &&
        _self!.identityId != _self!.masterDirectorId) {
      return 'Only the Master Director can remove a Director.';
    }
    return null;
  }

  @override
  List<BusinessRole> roleOptions(RegisteredUser user) {
    if (!_isCurrent(user)) return const [];
    if (user.status == RegistrationStatus.approved &&
        user.role == BusinessRole.director &&
        (user.id == _self!.identityId ||
            user.id == _self!.masterDirectorId ||
            _self!.identityId != _self!.masterDirectorId)) {
      return const [BusinessRole.director];
    }
    return BusinessRole.values;
  }

  @override
  Future<void> refresh() =>
      loadPage(offset: offset, limit: pageSize, search: search);

  @override
  Future<void> loadPage({
    required int offset,
    required int limit,
    required String search,
  }) async {
    if (_disposed) return;
    if (offset < 0 ||
        offset > 1000000 ||
        !AccountingRecordControlsPolicy.pageSizes.contains(limit) ||
        utf8.encode(search).length > 640) {
      error = 'Choose a valid page or a shorter search.';
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final actor = await service.self();
      if (_disposed || generation != _generation) return;
      if (actor?.isDirector != true) {
        _self = actor;
        refreshedAt = DateTime.now();
        _page = null;
        return;
      }
      var page = await service.directory(
        offset: offset,
        limit: limit,
        search: search,
      );
      // Deleting the last row on a page returns to the preceding valid page.
      var nextOffset = offset;
      if (offset > 0 && offset >= page.matched) {
        nextOffset = page.matched == 0
            ? 0
            : ((page.matched - 1) ~/ limit) * limit;
        page = await service.directory(
          offset: nextOffset,
          limit: limit,
          search: search,
        );
      }
      if (_disposed || generation != _generation) return;
      _self = actor;
      refreshedAt = DateTime.now();
      _page = page;
      this.offset = nextOffset;
      pageSize = limit;
      this.search = search;
    } on MembershipFailure catch (failure) {
      if (_disposed || generation != _generation) return;
      _self = null;
      _page = null;
      error = failure.toString();
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _mutate(
    List<RegisteredUser> targets,
    String action,
    BusinessRole? role,
  ) async {
    if (!canManageUsers) {
      throw StateError('Only approved Directors can manage employees.');
    }
    if (_commandBusy || loading) {
      throw StateError('Wait for the current request to finish.');
    }
    final revisions = {for (final user in targets) user.id: user.revision};
    if (revisions.length != targets.length) {
      throw ArgumentError('Duplicate users.');
    }
    final candidate = MembershipMutation(
      businessId: service.businessId,
      expectedRevisions: revisions,
      action: action,
      role: role?.name,
    );
    final prior = _uncertain;
    // Repeating an uncertain operation keeps its exact idempotency key/body.
    // A different intent is blocked until its original result is resolved.
    if (prior != null &&
        (prior.action != action ||
            prior.role != role?.name ||
            prior.revisions.length != revisions.length ||
            revisions.entries.any((e) => prior.revisions[e.key] != e.value))) {
      throw StateError(
        'The previous change could not be confirmed. Retry that change first.',
      );
    }
    final command = prior ?? candidate;
    await _sendCommand(command);
  }

  Future<void> _sendCommand(MembershipMutation command) async {
    _commandBusy = true;
    try {
      await service.execute(command);
      _uncertain = null;
      if (!_disposed) await refresh();
    } on MembershipFailure catch (failure) {
      if (_disposed) return;
      if (const [
        'service_unavailable',
        'invalid_response',
      ].contains(failure.code)) {
        _uncertain = command;
      } else {
        _uncertain = null;
      }
      if (const [
        'authentication_required',
        'invalid_google_token',
        'director_required',
      ].contains(failure.code)) {
        _self = null;
        _page = null;
        ++_generation;
        loading = false;
        notifyListeners();
      }
      error = failure.toString();
      notifyListeners();
      throw StateError(failure.toString());
    } finally {
      _commandBusy = false;
    }
  }

  @override
  Future<void> applyBatch(
    List<RegisteredUser> users,
    UserBatchAction action, {
    BusinessRole? role,
  }) => _mutate(users, switch (action) {
    UserBatchAction.approve => 'approve',
    UserBatchAction.reject => 'reject',
    UserBatchAction.remove => 'revoke',
  }, role);
  @override
  Future<void> approve(RegisteredUser user, BusinessRole role) =>
      _mutate([user], 'approve', role);
  @override
  Future<void> reject(RegisteredUser user) => _mutate([user], 'reject', null);
  @override
  Future<void> changeRole(RegisteredUser user, BusinessRole role) =>
      _mutate([user], 'changeRole', role);
  @override
  Future<void> remove(RegisteredUser user) => _mutate([user], 'revoke', null);

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _self = null;
    _page = null;
    _uncertain = null;
    service.close();
    super.dispose();
  }
}
