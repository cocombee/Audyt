import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/feature_registry.dart';
import 'package:audyt/app/routing.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/app/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Users preview notice reuses the temporary alert below its subtitle',
    (tester) async {
      final directory = PreviewUserDirectory();
      addTearDown(directory.dispose);
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: UsersPage(directory: directory)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      final notice = find.byType(AccountingTransientWarning);
      expect(notice, findsOneWidget);
      final subtitle = find.text(
        'Review employee registrations and manage business roles.',
      );
      expect(
        tester.getRect(notice).top,
        greaterThan(tester.getRect(subtitle).bottom),
      );
      expect(
        find.text('Director preview. Changes affect sample employees only.'),
        findsOneWidget,
      );
      final before = tester.getRect(find.text('Employee / Email')).top;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(
        find.text('Director preview. Changes affect sample employees only.'),
        findsNothing,
      );
      expect(
        tester.getRect(find.text('Employee / Email')).top,
        lessThan(before),
      );
    },
  );
  for (final approving in [true, false]) {
    testWidgets(
      'Director appointment requires Yes after ${approving ? 'approval' : 'role change'}',
      (tester) async {
        final directory = PreviewUserDirectory();
        addTearDown(directory.dispose);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: UsersPage(directory: directory)),
          ),
        );
        await tester.pumpAndSettle();
        final target = approving
            ? directory.pendingRegistrations.single
            : directory.users.firstWhere(
                (u) => u.role == BusinessRole.accountant,
              );
        Future<void> openWarning() async {
          await tester.tap(
            find.byKey(
              ValueKey(
                '${approving ? 'approve-user' : 'change-role'}-${target.id}',
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('user-role-selector')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Director').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('confirm-user-role')));
          await tester.pumpAndSettle();
          expect(find.text('Appoint Director?'), findsOneWidget);
        }

        await openWarning();
        expect(
          directory.users.firstWhere((u) => u.id == target.id).role,
          target.role,
        );
        await tester.tap(
          find.byKey(const ValueKey('cancel-director-appointment')),
        );
        await tester.pumpAndSettle();
        expect(
          directory.users.firstWhere((u) => u.id == target.id).role,
          target.role,
        );
        await openWarning();
        await tester.tap(
          find.byKey(const ValueKey('confirm-director-appointment')),
        );
        await tester.pumpAndSettle();
        expect(
          directory.users.firstWhere((u) => u.id == target.id).role,
          BusinessRole.director,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'batch commands validate every member before changing any user',
    () async {
      final pending = List.generate(
        2,
        (i) => RegisteredUser(
          id: 'pending-$i',
          name: 'Applicant $i',
          email: 'a$i@example.test',
          submittedAt: DateTime(2026),
        ),
      );
      final approved = RegisteredUser(
        id: 'approved',
        name: 'Accountant',
        email: 'approved@example.test',
        submittedAt: DateTime(2026),
        status: RegistrationStatus.approved,
        role: BusinessRole.accountant,
      );
      final directory = PreviewUserDirectory(users: [...pending, approved]);
      await expectLater(
        directory.applyBatch(
          [pending.first, approved],
          UserBatchAction.approve,
          role: BusinessRole.employee,
        ),
        throwsStateError,
      );
      expect(directory.users.first.status, RegistrationStatus.pending);
      await directory.applyBatch(
        pending,
        UserBatchAction.approve,
        role: BusinessRole.accountant,
      );
      expect(
        directory.users.every((u) => u.status == RegistrationStatus.approved),
        isTrue,
      );
      await expectLater(
        directory.applyBatch(pending, UserBatchAction.remove),
        throwsStateError,
      );
      expect(directory.users.length, 3);
      directory.dispose();
    },
  );

  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  });
  test(
    'preview commands enforce Director role and stale registration state',
    () async {
      final directory = PreviewUserDirectory();
      final applicant = directory.pendingRegistrations.single;
      await directory.approve(applicant, BusinessRole.accountant);
      expect(directory.pendingRegistrations, isEmpty);
      expect(() => directory.reject(applicant), throwsStateError);
      final approved = directory.users.last;
      expect(approved.role, BusinessRole.accountant);
      await directory.changeRole(approved, BusinessRole.employee);
      await directory.remove(directory.users.last);
      expect(directory.users, hasLength(2));
      expect(() => directory.remove(directory.users.first), throwsStateError);
      final accountant = PreviewUserDirectory(
        actorRole: BusinessRole.accountant,
      );
      expect(accountant.users, isEmpty);
      expect(accountant.pendingRegistrations, isEmpty);
      expect(
        () => accountant.approve(applicant, BusinessRole.director),
        throwsStateError,
      );
      expect(() => accountant.reject(applicant), throwsStateError);
      expect(
        () => accountant.changeRole(approved, BusinessRole.director),
        throwsStateError,
      );
      expect(() => accountant.remove(approved), throwsStateError);
      directory.dispose();
      accountant.dispose();
    },
  );

  testWidgets(
    'bulk actions appear only for multiple users and mixed selection only deletes',
    (tester) async {
      final directory = PreviewUserDirectory(
        users: [
          for (var i = 0; i < 3; i++)
            RegisteredUser(
              id: 'u$i',
              name: 'User $i',
              email: 'u$i@example.test',
              submittedAt: DateTime(2026),
              status: i == 2
                  ? RegistrationStatus.approved
                  : RegistrationStatus.pending,
              role: i == 2 ? BusinessRole.accountant : null,
            ),
        ],
      );
      addTearDown(directory.dispose);
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: UsersPage(directory: directory)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('users-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user-select-u0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('users-bulk-delete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('user-select-u1')));
      await tester.pumpAndSettle();
      final reject = find.byKey(const ValueKey('users-bulk-reject'));
      final remove = find.byKey(const ValueKey('users-bulk-delete'));
      final approve = find.byKey(const ValueKey('users-bulk-approve'));
      expect(
        tester.getCenter(reject).dx,
        lessThan(tester.getCenter(remove).dx),
      );
      expect(
        tester.getCenter(remove).dx,
        lessThan(tester.getCenter(approve).dx),
      );
      await tester.tap(find.byKey(const ValueKey('user-select-u2')));
      await tester.pumpAndSettle();
      expect(reject, findsNothing);
      expect(approve, findsNothing);
      expect(remove, findsOneWidget);
    },
  );

  testWidgets('Users shares column gaps, normal Role font and search anchors', (
    tester,
  ) async {
    final directory = PreviewUserDirectory(
      users: [
        ...PreviewUserDirectory().users,
        for (var i = 0; i < 9; i++)
          RegisteredUser(
            id: 'layout-$i',
            name: 'Applicant $i',
            email: 'applicant$i@example.test',
            submittedAt: DateTime(2026),
          ),
      ],
    );
    addTearDown(directory.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const capture = ValueKey('users-layout-capture');
    Future<void> show(double width, {double scale = 1}) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: UsersPage(directory: directory)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    for (final width in [1000.0, 700.0, 620.0]) {
      await show(width);
      Rect header(String name) =>
          tester.getRect(find.byKey(ValueKey('users-$name-header')));
      final user = header('user');
      final status = header('status');
      final role = header('role');
      final actions = header('actions');
      final gap = status.left - user.right;
      expect(gap, greaterThanOrEqualTo(accountingContentInset - .01));
      expect(role.left - status.right, closeTo(gap, .01));
      expect(actions.left - role.right, closeTo(gap, .01));
      for (final id in [
        'demo-director',
        'demo-accountant',
        'demo-registration',
      ]) {
        for (final column in ['status', 'role', 'actions']) {
          final cell = tester.getRect(
            find.byKey(ValueKey('user-$column-cell-$id')),
          );
          expect(cell.left, closeTo(header(column).left, .01));
          expect(cell.width, closeTo(header(column).width, .01));
        }
      }
      expect(find.text('Status / Role'), findsNothing);
      final roleText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('user-role-cell-demo-director')),
          matching: find.text('Director'),
        ),
      );
      expect(roleText.style!.fontSize, accountingControlFontSize);
      expect(roleText.style!.fontWeight, FontWeight.w400);
      final title = tester.getRect(find.text('Employees').last);
      final searchLabel = tester.getRect(find.text('Search'));
      final input = tester.getRect(find.byKey(const ValueKey('users-search')));
      final card = tester.getRect(find.byType(AccountingRecordList));
      expect(searchLabel.left, closeTo(title.left, .01));
      expect(input.left, closeTo(card.left, .01));
      expect(input.bottom + accountingContentInset, closeTo(card.top, .01));
      // Opening selection reserves the checkbox inside the same User column.
      await tester.tap(find.byKey(const ValueKey('users-select')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cell = tester.getRect(
        find.byKey(const ValueKey('user-status-cell-demo-director')),
      );
      expect(cell.left, closeTo(header('status').left, .01));
      await tester.tap(find.byKey(const ValueKey('users-select')));
      await tester.pumpAndSettle();
    }
    // Page-content widths: the native desktop window stops at 720px,
    // with at least 620px available beside its compact rail.
    for (final width in [1000.0, 620.0]) {
      await show(width);
      final output =
          Platform.environment['AUDYT_UI_CAPTURE_DIR'] ??
          const String.fromEnvironment('AUDYT_USERS_RENDER_DIR');
      if (output.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/Employees Search $width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await show(620, scale: 2);
  });

  testWidgets(
    'protected Director controls and mixed bulk deletion stay disabled',
    (tester) async {
      final directory = PreviewUserDirectory();
      addTearDown(directory.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1000, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: UsersPage(directory: directory)),
        ),
      );
      await tester.pumpAndSettle();
      IconButton control(String key) =>
          tester.widget<IconButton>(find.byKey(ValueKey(key)));
      expect(control('delete-user-demo-director').onPressed, isNull);
      expect(control('change-role-demo-director').onPressed, isNull);
      expect(control('delete-user-demo-accountant').onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('users-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user-select-demo-director')));
      await tester.tap(
        find.byKey(const ValueKey('user-select-demo-accountant')),
      );
      await tester.pumpAndSettle();
      final delete = tester.widget<FilledButton>(
        find.byKey(const ValueKey('users-bulk-delete')),
      );
      expect(delete.onPressed, isNull);
      expect(directory.users, hasLength(3));
    },
  );

  testWidgets('approval requires role; approved rows change role and delete', (
    tester,
  ) async {
    final directory = PreviewUserDirectory();
    addTearDown(directory.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const capture = ValueKey('users-capture');
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: Scaffold(body: UsersPage(directory: directory)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('users-search')), findsNothing);
    for (final width in [1000.0, 620.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final output =
          Platform.environment['AUDYT_UI_CAPTURE_DIR'] ??
          const String.fromEnvironment('AUDYT_USERS_RENDER_DIR');
      if (output.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/Employees $width.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('approve-user-demo-registration')),
    );
    await tester.tap(
      find.byKey(const ValueKey('approve-user-demo-registration')),
    );
    await tester.pumpAndSettle();
    expect(directory.pendingRegistrations, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('user-role-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employee').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-user-role')));
    await tester.pumpAndSettle();
    expect(directory.pendingRegistrations, isEmpty);
    expect(
      find.byKey(const ValueKey('change-role-demo-registration')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('delete-user-demo-registration')),
    );
    await tester.tap(
      find.byKey(const ValueKey('delete-user-demo-registration')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-user-action')));
    await tester.pumpAndSettle();
    expect(directory.users, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search uses total count and matches email', (tester) async {
    final users = List.generate(
      11,
      (i) => RegisteredUser(
        id: '$i',
        name: 'Person $i',
        email: 'person$i@example.test',
        submittedAt: DateTime(2026, 9, 26),
      ),
    );
    final directory = PreviewUserDirectory(users: users);
    addTearDown(directory.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(body: UsersPage(directory: directory)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('users-search')),
      'person10@',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-row-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-row-1')), findsNothing);
    expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
    await directory.remove(users.last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('users-search')), findsOneWidget);
    for (final user in users.skip(5).take(5)) {
      await directory.remove(user);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('users-search')), findsNothing);
    expect(find.byKey(const ValueKey('user-row-1')), findsOneWidget);
  });

  for (final actorRole in [BusinessRole.accountant, BusinessRole.employee]) {
    testWidgets('${actorRole.label} has no employee role controls', (
      tester,
    ) async {
      final directory = PreviewUserDirectory(actorRole: actorRole);
      addTearDown(directory.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: AccountingShell(
            initialRoute: AccountingRoute(FeatureRegistry.byId('home')!),
            userDirectory: directory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Employees'), findsNothing);
      expect(find.byKey(const ValueKey('user-role-selector')), findsNothing);
      expect(find.byKey(const ValueKey('batch-user-role')), findsNothing);
      final authorised = PreviewUserDirectory();
      addTearDown(authorised.dispose);
      final target = authorised.users.firstWhere(
        (u) => u.role == BusinessRole.accountant,
      );
      expect(directory.roleOptions(target), isEmpty);
      await expectLater(
        directory.changeRole(target, BusinessRole.director),
        throwsStateError,
      );
      await expectLater(
        directory.applyBatch(
          [target],
          UserBatchAction.approve,
          role: BusinessRole.director,
        ),
        throwsStateError,
      );
      expect(find.text('Demo Applicant'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AccountingTheme.light(),
          home: UsersPage(directory: directory),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Only Directors can manage employees.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('user-row-demo-registration')),
        findsNothing,
      );
    });
  }
  testWidgets(
    'Director registration notification opens Users without approving',
    (tester) async {
      final directory = PreviewUserDirectory();
      addTearDown(directory.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: AccountingShell(
            initialRoute: AccountingRoute(FeatureRegistry.byId('home')!),
            userDirectory: directory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Employees')).dy,
        greaterThan(tester.getTopLeft(find.text('Documents')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('global-notifications')));
      await tester.pumpAndSettle();
      final notification = find.byKey(
        const ValueKey('notification-registration-demo-registration'),
      );
      expect(notification, findsOneWidget);
      await tester.ensureVisible(notification);
      await tester.tap(notification);
      await tester.pumpAndSettle();
      expect(find.byType(UsersPage), findsOneWidget);
      expect(directory.pendingRegistrations, hasLength(1));
    },
  );
}
