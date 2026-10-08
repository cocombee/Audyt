import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/app/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture;

Finder keyed(String key) => find.byKey(ValueKey(key));
const guidance = 'Only Directors can approve employees and manage access.';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Employees popup family retains title help and Close/no-write at $width',
      (tester) async {
        await prepare(tester, width);
        final directory = PreviewUserDirectory(extraApplicants: 3);
        addTearDown(directory.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: UsersPage(directory: directory)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = [
          for (final user in directory.users)
            (user.id, user.role, user.status, user.revision),
        ];
        final applicant = directory.pendingRegistrations.first;
        final accountant = directory.users.firstWhere(
          (user) => user.role == BusinessRole.accountant,
        );
        Future<void> close() async {
          await tester.tap(find.bySemanticsLabel('Close').last);
          await tester.pumpAndSettle();
        }

        Future<void> checkRole(
          String group,
          String selector,
          String stem,
        ) async {
          expect(keyed(group), findsOneWidget);
          expect(find.text(guidance), findsNothing);
          expect(find.text('Cancel'), findsNothing);
          final field = tester.getRect(keyed(selector));
          final surface = tester.getRect(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Material && widget.type == MaterialType.card,
                  ),
                )
                .first,
          );
          expect(
            field.width,
            closeTo(AccountingPopoutTokens.normalContentWidth, .1),
          );
          expect(
            surface.width,
            closeTo(
              AccountingPopoutTokens.normalContentWidth +
                  accountingContentInset * 2,
              .1,
            ),
          );
          expect(field.left - surface.left, closeTo(20, .1));
          await capture(tester, '$stem ${width.toInt()}');
          await tester.tap(find.bySemanticsLabel('Help for Role'));
          await tester.pumpAndSettle();
          expect(find.text(guidance), findsOneWidget);
          await capture(tester, '$stem Help ${width.toInt()}');
          await tester.tap(keyed(selector));
          await tester.pumpAndSettle();
          for (final role in BusinessRole.values) {
            expect(find.text(role.label).last, findsOneWidget);
          }
          await capture(tester, '$stem Options ${width.toInt()}');
          await tester.tap(find.text('Director').last);
          await tester.pumpAndSettle();
        }

        await tester.tap(keyed('approve-user-${applicant.id}'));
        await tester.pumpAndSettle();
        await checkRole(
          'employee-role-fields',
          'user-role-selector',
          'Employee Approval Role',
        );
        await tester.tap(keyed('confirm-user-role'));
        await tester.pumpAndSettle();
        expect(find.text('Appoint Director?'), findsOneWidget);
        await capture(tester, 'Employee Director Appointment ${width.toInt()}');
        await close();
        expect(directory.pendingRegistrations.length, 4);

        await tester.tap(keyed('change-role-${accountant.id}'));
        await tester.pumpAndSettle();
        await checkRole(
          'employee-role-fields',
          'user-role-selector',
          'Employee Change Role',
        );
        await close();

        await tester.tap(keyed('reject-user-${applicant.id}'));
        await tester.pumpAndSettle();
        expect(find.text('Reject Registration'), findsOneWidget);
        await capture(tester, 'Employee Reject Registration ${width.toInt()}');
        await close();
        await tester.tap(keyed('delete-user-${accountant.id}'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Employee'), findsNWidgets(2));
        await capture(tester, 'Employee Remove Access ${width.toInt()}');
        await close();

        await tester.tap(keyed('users-select'));
        await tester.pumpAndSettle();
        await tester.tap(keyed('user-select-${applicant.id}'));
        await tester.pumpAndSettle();
        await tester.tap(
          keyed('user-select-${directory.pendingRegistrations[1].id}'),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(keyed('users-bulk-approve'));
        await tester.tap(keyed('users-bulk-approve'));
        await tester.pumpAndSettle();
        await checkRole(
          'employee-batch-role-fields',
          'batch-user-role',
          'Employee Batch Approval Role',
        );
        await close();
        expect([
          for (final user in directory.users)
            (user.id, user.role, user.status, user.revision),
        ], before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
