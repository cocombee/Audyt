import 'dart:async';
import 'dart:convert';

import 'package:audyt/app/connected_user_directory.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:audyt/app/google_membership_connection.dart';
import 'package:audyt/app/google_account_session.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/app/users_page.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/routing.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const business = '11111111-1111-4111-8111-111111111111';
const actor = '22222222-2222-4222-8222-222222222222';
const target = '33333333-3333-4333-8333-333333333333';

class DirectoryTransport implements MembershipTransport {
  final calls = <({Uri uri, String? body})>[];
  String role = 'director';
  String status = 'approved';
  String? masterDirectorId = actor;
  String targetId = target;
  String targetStatus = 'pending';
  String? targetRole;
  bool noMembership = false;
  int pendingCount = 1;
  int registrations = 0;
  bool loseFirstRegistrationReceipt = false;
  int total = 12;
  bool denied = false;
  bool loseFirstReceipt = false;
  int commands = 0;
  Completer<MembershipResponse>? heldPage;
  bool closed = false;
  MembershipResponse page(Uri uri) => MembershipResponse(
    200,
    jsonEncode({
      'businessId': business,
      'revision': 0,
      'total': total,
      'pendingCount': pendingCount,
      'matched': uri.queryParameters['search'] == 'missing' ? 0 : total,
      'offset': int.parse(uri.queryParameters['offset']!),
      'limit': int.parse(uri.queryParameters['limit']!),
      'users':
          uri.queryParameters['search'] == 'missing' ||
              int.parse(uri.queryParameters['offset']!) >= total
          ? []
          : [
              {
                'id': targetId,
                'name': 'Fictional Applicant',
                'email': 'applicant@example.test',
                'status': targetStatus,
                'role': targetRole,
                'revision': 0,
                'submittedAt': '2026-09-26 00:00:00',
              },
            ],
    }),
  );
  @override
  Future<MembershipResponse> send({
    required String method,
    required Uri uri,
    required String token,
    String? body,
  }) async {
    calls.add((uri: uri, body: body));
    if (denied) {
      return const MembershipResponse(403, '{"error":"director_required"}');
    }
    if (uri.path.endsWith('/self')) {
      if (noMembership) {
        return const MembershipResponse(200, '{"membership":null}');
      }
      return MembershipResponse(
        200,
        jsonEncode({
          'membership': {
            'identityId': actor,
            'masterDirectorId': status == 'approved' && role == 'director'
                ? masterDirectorId
                : null,
            'status': status,
            'role': status == 'approved' ? role : null,
            'revision': 0,
          },
        }),
      );
    }
    if (uri.path.endsWith('/users')) return heldPage?.future ?? page(uri);
    if (uri.path.endsWith('/registrations')) {
      registrations++;
      final registration = jsonDecode(body!) as Map;
      noMembership = false;
      status = 'pending';
      if (loseFirstRegistrationReceipt && registrations == 1) {
        throw StateError('lost registration receipt');
      }
      return MembershipResponse(
        200,
        jsonEncode({
          'businessId': business,
          'requestId': registration['requestId'],
          'identityId': actor,
          'membership': {'status': status, 'role': null, 'revision': 0},
        }),
      );
    }
    commands++;
    if (loseFirstReceipt && commands == 1) throw StateError('lost response');
    final command = jsonDecode(body!) as Map<String, dynamic>;
    return MembershipResponse(
      200,
      jsonEncode({
        'requestId': command['requestId'],
        'memberships': {
          target: {
            'businessId': business,
            'revision': 1,
            'status': command['action'] == 'approve' ? 'approved' : 'rejected',
            'role': command['role'],
          },
        },
      }),
    );
  }

  @override
  void close() {
    closed = true;
  }
}

class FixtureAccount implements GoogleSignInAccount {
  FixtureAccount(this.id);
  @override
  final String id;
  @override
  GoogleSignInAuthentication get authentication =>
      const GoogleSignInAuthentication(idToken: 'header.payload.signature');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FixtureGoogle extends GoogleAccountSession {
  void setAccount(String? id) {
    account = id == null ? null : FixtureAccount(id);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DirectoryTransport transport;
  late ConnectedUserDirectory directory;
  setUp(() {
    transport = DirectoryTransport();
    directory = ConnectedUserDirectory(
      MembershipService(
        origin: Uri.parse('https://audyt.example.test'),
        businessId: business,
        tokenProvider: () async => 'header.payload.signature',
        transport: transport,
      ),
    );
  });
  tearDown(() => directory.dispose());

  test(
    'capability hints use verified Master binding and current target state',
    () async {
      transport.targetStatus = 'approved';
      transport.targetRole = 'director';
      transport.masterDirectorId = '44444444-4444-4444-8444-444444444444';
      await directory.refresh();
      var user = directory.users.single;
      expect(directory.removalRestriction(user), contains('Only the Master'));
      expect(directory.roleOptions(user), [BusinessRole.director]);
      // Missing older-server metadata fails closed for Director changes.
      transport.masterDirectorId = null;
      await directory.refresh();
      user = directory.users.single;
      expect(directory.removalRestriction(user), isNotNull);
      expect(directory.roleOptions(user), [BusinessRole.director]);
      transport.masterDirectorId = actor;
      await directory.refresh();
      user = directory.users.single;
      expect(directory.removalRestriction(user), isNull);
      expect(directory.roleOptions(user), BusinessRole.values);
      transport.masterDirectorId = target;
      await directory.refresh();
      user = directory.users.single;
      expect(directory.removalRestriction(user), contains('protected'));
      expect(directory.roleOptions(user), [BusinessRole.director]);
      transport.masterDirectorId = actor;
      transport.targetId = actor;
      await directory.refresh();
      user = directory.users.single;
      expect(directory.removalRestriction(user), contains('own access'));
      expect(directory.roleOptions(user), [BusinessRole.director]);
      transport.targetId = target;
      transport.targetRole = 'employee';
      await directory.refresh();
      user = directory.users.single;
      expect(directory.removalRestriction(user), isNull);
      expect(directory.roleOptions(user), BusinessRole.values);
      expect(
        directory.removalRestriction(
          user.changed(RegistrationStatus.approved, BusinessRole.director),
        ),
        isNotNull,
      );
      transport.role = 'accountant';
      await directory.refresh();
      expect(directory.removalRestriction(user), isNotNull);
      expect(directory.roleOptions(user), isEmpty);
      expect(transport.commands, 0);
    },
  );

  test('Google sign-out closes the old account service before another account loads', () async {
    final google = FixtureGoogle();
    final transports = <DirectoryTransport>[];
    final connection = GoogleMembershipConnection(
      origin: Uri.parse('https://audyt.example.test'),
      businessId: business,
      google: google,
      refreshInterval: Duration.zero,
      transportFactory: () {
        final transport = DirectoryTransport();
        transports.add(transport);
        return transport;
      },
    );
    addTearDown(connection.dispose);
    addTearDown(google.dispose);
    expect(connection.directory, null);
    google.setAccount('fictional-first');
    await Future<void>.delayed(Duration.zero);
    final first = connection.directory!;
    expect(first.canManageUsers, true);
    google.setAccount(null);
    expect(connection.directory, null);
    expect(first.canManageUsers, false);
    expect(first.users, isEmpty);
    expect(transports.first.closed, true);
    google.setAccount('fictional-second');
    await Future<void>.delayed(Duration.zero);
    expect(identical(connection.directory, first), false);
    expect(connection.directory!.canManageUsers, true);
    expect(await google.idTokenForAccount('fictional-first'), null);
  });

  test(
    'approval authority and page totals come from verified self and server',
    () async {
      expect(directory.canManageUsers, false);
      await directory.refresh();
      expect(directory.canManageUsers, true);
      expect(directory.total, 12);
      expect(directory.users.length, 1);
      expect(directory.pendingCount, 1);
      await directory.loadPage(offset: 10, limit: 10, search: '');
      expect(directory.offset, 10);
      expect(transport.calls.last.uri.queryParameters['offset'], '10');
    },
  );
  for (final actorRole in ['accountant', 'employee']) {
    test('$actorRole cannot fetch employees or change roles', () async {
      transport.role = actorRole;
      await directory.refresh();
      expect(directory.canManageUsers, false);
      expect(transport.calls.length, 1);
      expect(directory.users, isEmpty);
      final targets = PreviewUserDirectory();
      addTearDown(targets.dispose);
      final target = targets.users.first;
      expect(directory.roleOptions(target), isEmpty);
      await expectLater(
        directory.changeRole(target, BusinessRole.director),
        throwsStateError,
      );
      expect(transport.calls.length, 1);
      await expectLater(
        directory.applyBatch([], UserBatchAction.reject),
        throwsStateError,
      );
    });
  }
  test(
    'failed authorization clears loaded private rows and authority',
    () async {
      await directory.refresh();
      transport.denied = true;
      await directory.refresh();
      expect(directory.canManageUsers, false);
      expect(directory.users, isEmpty);
      expect(directory.total, 0);
      expect(directory.error, contains('Directors'));
    },
  );
  test('late page after disposal cannot repopulate the old account', () async {
    transport.heldPage = Completer();
    final pending = directory.refresh();
    await Future<void>.delayed(Duration.zero);
    directory.dispose();
    transport.heldPage!.complete(transport.page(transport.calls.last.uri));
    await pending;
    expect(directory.canManageUsers, false);
    expect(directory.users, isEmpty);
    expect(transport.closed, true);
    // The tearDown owns the normal instance; use a replacement after disposal.
    directory = ConnectedUserDirectory(
      MembershipService(
        origin: Uri.parse('https://audyt.example.test'),
        businessId: business,
        tokenProvider: () async => null,
      ),
    );
  });
  test(
    'lost receipt requires identical explicit retry, never a new command',
    () async {
      await directory.refresh();
      final user = directory.users.single;
      transport.loseFirstReceipt = true;
      await expectLater(
        directory.approve(user, BusinessRole.employee),
        throwsStateError,
      );
      await expectLater(directory.reject(user), throwsStateError);
      expect(transport.commands, 1);
      await directory.loadPage(offset: 0, limit: 10, search: 'missing');
      expect(directory.users, isEmpty);
      expect(directory.hasUnconfirmedChange, true);
      await directory.retryUnconfirmedChange();
      expect(directory.hasUnconfirmedChange, false);
      final bodies = transport.calls
          .where((c) => c.body != null)
          .map((c) => c.body)
          .toList();
      expect(bodies.length, 2);
      expect(bodies[0], bodies[1]);
    },
  );
  test(
    'requested Director profile submits pending and old accounts cannot submit',
    () async {
      final google = FixtureGoogle();
      transport.noMembership = true;
      final connection = GoogleMembershipConnection(
        origin: Uri.parse('https://audyt.example.test'),
        businessId: business,
        google: google,
        refreshInterval: Duration.zero,
        transportFactory: () => transport,
      );
      addTearDown(connection.dispose);
      addTearDown(google.dispose);
      google.setAccount('fictional-first');
      await Future<void>.delayed(Duration.zero);
      await connection.submitProfile(
        googleSubject: 'fictional-first',
        name: 'Fictional Applicant',
        email: 'contact@example.test',
        requestedRole: 'director',
      );
      expect(connection.approvalStatus, 'pending');
      expect(connection.directory!.canManageUsers, false);
      expect(transport.registrations, 1);
      await expectLater(
        connection.submitProfile(
          googleSubject: 'other-account',
          name: 'Fictional Applicant',
          email: 'contact@example.test',
          requestedRole: 'director',
        ),
        throwsA(
          isA<MembershipFailure>().having(
            (failure) => failure.code,
            'code',
            'session_changed',
          ),
        ),
      );
      expect(transport.registrations, 1);
    },
  );
  test(
    'lost registration receipt survives membership refresh and retries exactly',
    () async {
      final google = FixtureGoogle();
      transport.noMembership = true;
      transport.loseFirstRegistrationReceipt = true;
      final connection = GoogleMembershipConnection(
        origin: Uri.parse('https://audyt.example.test'),
        businessId: business,
        google: google,
        refreshInterval: Duration.zero,
        transportFactory: () => transport,
      );
      addTearDown(connection.dispose);
      addTearDown(google.dispose);
      google.setAccount('fictional-first');
      await Future<void>.delayed(Duration.zero);
      Future<void> submit() => connection.submitProfile(
        googleSubject: 'fictional-first',
        name: 'Fictional Applicant',
        email: 'contact@example.test',
        requestedRole: 'director',
      );
      await expectLater(submit(), throwsA(isA<MembershipFailure>()));
      await connection.directory!.refresh();
      expect(connection.approvalStatus, 'pending');
      expect(connection.hasUnconfirmedRegistration, true);
      await submit();
      expect(connection.hasUnconfirmedRegistration, false);
      final bodies = transport.calls
          .where((call) => call.uri.path.endsWith('/registrations'))
          .map((call) => call.body)
          .toList();
      expect(bodies.length, 2);
      expect(bodies[0], bodies[1]);
    },
  );

  testWidgets('polling pauses when inactive and resumes with an access check', (
    tester,
  ) async {
    final google = FixtureGoogle()..setAccount('fictional-first');
    final connection = GoogleMembershipConnection(
      origin: Uri.parse('https://audyt.example.test'),
      businessId: business,
      google: google,
      transportFactory: () => transport,
    );
    var closed = false;
    addTearDown(() {
      if (!closed) connection.dispose();
    });
    addTearDown(google.dispose);
    await tester.pumpAndSettle();
    final initial = transport.calls.length;
    connection.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 1));
    expect(transport.calls.length, initial);
    connection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(transport.calls.length, greaterThan(initial));
    connection.dispose();
    closed = true;
    final stopped = transport.calls.length;
    await tester.pump(const Duration(minutes: 1));
    expect(transport.calls.length, stopped);
  });
  testWidgets(
    'Director registration notifications use server count across pages',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      transport.total = 25;
      transport.pendingCount = 23;
      await directory.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: AccountingShell(
            initialRoute: AccountingRouting.resolve('/home')!,
            userDirectory: directory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('global-notifications')));
      await tester.pumpAndSettle();
      final reminder = find.byKey(
        const ValueKey('notification-registrations-pending-23'),
      );
      expect(reminder, findsOneWidget);
      expect(find.text('23 awaiting Director approval'), findsOneWidget);
      await tester.ensureVisible(reminder);
      await tester.tap(reminder);
      await tester.pumpAndSettle();
      expect(find.byType(UsersPage), findsOneWidget);
      expect(directory.pendingCount, 23);
      expect(transport.commands, 0);
    },
  );

  test('removing the last page clamps to a valid server offset', () async {
    transport.total = 9;
    await directory.loadPage(offset: 10, limit: 10, search: '');
    expect(directory.offset, 0);
    expect(
      transport.calls.where((c) => c.uri.path.endsWith('/users')).length,
      2,
    );
  });
  testWidgets(
    'an approval dialog cannot apply to a replacement account directory',
    (tester) async {
      final first = PreviewUserDirectory();
      final second = PreviewUserDirectory();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = ValueNotifier<UserDirectory>(first);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: ValueListenableBuilder<UserDirectory>(
              valueListenable: source,
              builder: (context, directory, _) =>
                  UsersPage(directory: directory),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('approve-user-demo-registration')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user-role-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Employee').last);
      await tester.pumpAndSettle();
      source.value = second;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-user-role')));
      await tester.pumpAndSettle();
      expect(first.pendingRegistrations.length, 1);
      expect(second.pendingRegistrations.length, 1);
    },
  );

  testWidgets('real Users search uses total and Next fetches the server page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await directory.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: UsersPage(directory: directory)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
    expect(find.text('1–5 of 12'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('users-page-next')));
    await tester.pumpAndSettle();
    expect(directory.offset, 5);
    expect(find.text('6–10 of 12'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('users-search')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(directory.search, 'missing');
    expect(find.text('No matching employees.'), findsOneWidget);
    expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
  });
}
