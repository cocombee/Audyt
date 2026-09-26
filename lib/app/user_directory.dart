import 'membership_service.dart';

import 'package:flutter/foundation.dart';

import '../features/accounting/domain/payee.dart';

enum BusinessRole { director, accountant, employee }

extension BusinessRoleLabel on BusinessRole {
  String get label => switch (this) {
    BusinessRole.director => 'Director',
    BusinessRole.accountant => 'Accountant',
    BusinessRole.employee => 'Employee',
  };
}

enum UserBatchAction { approve, reject, remove }

enum RegistrationStatus { pending, approved, rejected }

@immutable
class RegisteredUser {
  const RegisteredUser({
    required this.id,
    required this.name,
    required this.email,
    required this.submittedAt,
    this.status = RegistrationStatus.pending,
    this.role,
    this.revision = 0,
  });
  final String id;
  final String name;
  final String email;
  final DateTime submittedAt;
  final RegistrationStatus status;
  final BusinessRole? role;
  final int revision;

  RegisteredUser changed(RegistrationStatus status, BusinessRole? role) =>
      RegisteredUser(
        id: id,
        name: name,
        email: email,
        submittedAt: submittedAt,
        status: status,
        role: role,
        revision: revision + 1,
      );
}

/// UI boundary. A connected implementation must obtain membership from the
/// server and authorize each command there; local profile labels are not input.
abstract class UserDirectory extends ChangeNotifier {
  /// No local profile or Payee creates a registered claimant. A disconnected
  /// directory has no Claim authority projection.
  Future<ServiceClaimantContext?> findClaimants(String search) async => null;

  Future<List<Payee>> findEmployeePayees(String search) async => [
    for (final user in users)
      if (user.status == RegistrationStatus.approved &&
          user.role == BusinessRole.employee &&
          user.name.toLowerCase().contains(search.trim().toLowerCase()))
        Payee(
          id: 'registered-employee-${user.id}',
          name: user.name,
          type: PayeeType.staff,
        ),
  ];

  bool get isPreview;
  bool get canManageUsers;
  List<RegisteredUser> get users;
  List<RegisteredUser> get pendingRegistrations => canManageUsers
      ? users
            .where((user) => user.status == RegistrationStatus.pending)
            .toList()
      : const [];

  /// Presentation hints only. Connected commands remain server-authorized.
  String? removalRestriction(RegisteredUser user) =>
      canManageUsers ? null : 'Only Directors can manage employees.';
  List<BusinessRole> roleOptions(RegisteredUser user) =>
      canManageUsers ? BusinessRole.values : const [];

  Future<void> applyBatch(
    List<RegisteredUser> users,
    UserBatchAction action, {
    BusinessRole? role,
  });
  Future<void> approve(RegisteredUser user, BusinessRole role);
  Future<void> reject(RegisteredUser user);
  Future<void> changeRole(RegisteredUser user, BusinessRole role);
  Future<void> remove(RegisteredUser user);
}

/// A directory page supplied by the service rather than sliced locally.
abstract class PagedUserDirectory extends UserDirectory {
  int get total;
  int get matched;
  int get offset;
  int get pageSize;
  int get pendingCount;
  String get search;
  bool get loading;
  String? get error;
  bool get hasUnconfirmedChange;
  Future<void> retryUnconfirmedChange();
  Future<void> refresh();
  Future<void> loadPage({
    required int offset,
    required int limit,
    required String search,
  });
}

/// Isolated, disposable design data. Never writes to the accounting workspace
/// or claims to authorize a real Google account.
class PreviewUserDirectory extends UserDirectory {
  PreviewUserDirectory({
    this.actorRole = BusinessRole.director,
    this.actorId = 'demo-director',
    this.masterDirectorId = 'demo-director',
    int extraApplicants = 0,
    List<RegisteredUser>? users,
  }) : _users = List.of(
         users ??
             [
               RegisteredUser(
                 id: 'demo-director',
                 name: 'Demo Director',
                 email: 'director@example.test',
                 submittedAt: DateTime(2026, 9, 20),
                 status: RegistrationStatus.approved,
                 role: BusinessRole.director,
               ),
               RegisteredUser(
                 id: 'demo-accountant',
                 name: 'Demo Accountant',
                 email: 'accountant@example.test',
                 submittedAt: DateTime(2026, 9, 21),
                 status: RegistrationStatus.approved,
                 role: BusinessRole.accountant,
               ),
               RegisteredUser(
                 id: 'demo-registration',
                 name: 'Demo Applicant',
                 email: 'applicant@example.test',
                 submittedAt: DateTime(2026, 9, 26),
               ),
               for (var i = 0; i < extraApplicants; i++)
                 RegisteredUser(
                   id: 'demo-registration-${i + 2}',
                   name: 'Demo Applicant ${i + 2}',
                   email: 'applicant${i + 2}@example.test',
                   submittedAt: DateTime(2026, 9, 26, 0, i + 1),
                 ),
             ],
       );
  final BusinessRole actorRole;
  final String actorId;
  final String masterDirectorId;
  final List<RegisteredUser> _users;
  @override
  bool get isPreview => true;
  @override
  bool get canManageUsers => actorRole == BusinessRole.director;
  @override
  List<RegisteredUser> get users =>
      canManageUsers ? List.unmodifiable(_users) : const [];

  @override
  String? removalRestriction(RegisteredUser user) {
    if (!canManageUsers) return 'Only Directors can manage employees.';
    if (user.id == actorId) return 'You cannot remove your own access.';
    if (user.id == masterDirectorId) {
      return 'The Master Director’s access is protected.';
    }
    if (user.role == BusinessRole.director && actorId != masterDirectorId) {
      return 'Only the Master Director can remove a Director.';
    }
    return null;
  }

  @override
  List<BusinessRole> roleOptions(RegisteredUser user) {
    if (!canManageUsers) return const [];
    if (user.status == RegistrationStatus.approved &&
        user.role == BusinessRole.director &&
        (user.id == actorId ||
            user.id == masterDirectorId ||
            actorId != masterDirectorId)) {
      return const [BusinessRole.director];
    }
    return BusinessRole.values;
  }

  int _check(RegisteredUser user) {
    if (!canManageUsers) {
      throw StateError('Only Directors can manage employees.');
    }
    final index = _users.indexWhere((entry) => entry.id == user.id);
    if (index < 0 || _users[index].revision != user.revision) {
      throw StateError('This user changed. Review the latest details.');
    }
    return index;
  }

  void _protectDirector(RegisteredUser user) {
    if (user.id == actorId) {
      throw StateError('You cannot remove or change your own Director access.');
    }
    if (user.id == masterDirectorId) {
      throw StateError('The Master Director’s access is protected.');
    }
    if (user.role == BusinessRole.director && actorId != masterDirectorId) {
      throw StateError(
        'Only the Master Director can remove or demote a Director.',
      );
    }
    if (user.role == BusinessRole.director &&
        _users
                .where(
                  (entry) =>
                      entry.status == RegistrationStatus.approved &&
                      entry.role == BusinessRole.director,
                )
                .length <=
            1) {
      throw StateError('Keep at least one approved Director.');
    }
  }

  @override
  Future<void> approve(RegisteredUser user, BusinessRole role) async {
    final index = _check(user);
    if (user.status != RegistrationStatus.pending) {
      throw StateError('This registration is no longer pending.');
    }
    _users[index] = user.changed(RegistrationStatus.approved, role);
    notifyListeners();
  }

  @override
  Future<void> reject(RegisteredUser user) async {
    final index = _check(user);
    if (user.status != RegistrationStatus.pending) {
      throw StateError('This registration is no longer pending.');
    }
    _users[index] = user.changed(RegistrationStatus.rejected, null);
    notifyListeners();
  }

  @override
  Future<void> changeRole(RegisteredUser user, BusinessRole role) async {
    final index = _check(user);
    if (user.status != RegistrationStatus.approved) {
      throw StateError('Approve this user first.');
    }
    if (role != BusinessRole.director) _protectDirector(user);
    _users[index] = user.changed(RegistrationStatus.approved, role);
    notifyListeners();
  }

  @override
  Future<void> remove(RegisteredUser user) async {
    final index = _check(user);
    _protectDirector(user);
    _users.removeAt(index);
    notifyListeners();
  }

  @override
  Future<void> applyBatch(
    List<RegisteredUser> users,
    UserBatchAction action, {
    BusinessRole? role,
  }) async {
    if (users.length < 2 ||
        users.map((u) => u.id).toSet().length != users.length) {
      throw StateError('Select at least two different users.');
    }
    if (action == UserBatchAction.approve && role == null) {
      throw StateError('Select a role first.');
    }
    // Validate the entire selection before mutating any preview record.
    for (final user in users) {
      _check(user);
      if (action == UserBatchAction.remove) {
        _protectDirector(user);
      } else if (user.status != RegistrationStatus.pending) {
        throw StateError(
          'Only pending registrations can be approved or rejected.',
        );
      }
    }
    final ids = users.map((u) => u.id).toSet();
    if (action == UserBatchAction.remove) {
      final directors = _users.where(
        (u) =>
            u.status == RegistrationStatus.approved &&
            u.role == BusinessRole.director,
      );
      if (directors.isNotEmpty && directors.every((u) => ids.contains(u.id))) {
        throw StateError('Keep at least one Director.');
      }
      _users.removeWhere((u) => ids.contains(u.id));
    } else {
      for (var i = 0; i < _users.length; i++) {
        if (ids.contains(_users[i].id)) {
          _users[i] = _users[i].changed(
            action == UserBatchAction.approve
                ? RegistrationStatus.approved
                : RegistrationStatus.rejected,
            action == UserBatchAction.approve ? role : null,
          );
        }
      }
    }
    notifyListeners();
  }
}
