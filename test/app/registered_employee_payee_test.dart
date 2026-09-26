import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';

import 'dart:convert';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:audyt/app/connected_user_directory.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'membership_service_test.dart' show FakeTransport, business, member;
import 'claim_receipts_proposal_test.dart' show prepare, capture;
import '../support/fixed_popout_host.dart';

void main() {
  test('connected approved-employee search uses immutable service identities and no writes', () async {
    final transport = FakeTransport();
    transport.response = MembershipResponse(
      200,
      jsonEncode({
        'businessId': business,
        'payees': [
          {'id': member, 'name': 'Registered Employee'},
        ],
      }),
    );
    final directory = ConnectedUserDirectory(
      MembershipService(
        origin: Uri.parse('https://example.test'),
        businessId: business,
        tokenProvider: () async => 'verified.token.signature',
        transport: transport,
      ),
    );
    addTearDown(directory.dispose);
    final options = await directory.findEmployeePayees('Registered');
    expect(options.single.id, 'registered-employee-$member');
    expect(options.single.type, PayeeType.staff);
    expect(transport.calls.single.method, 'GET');
    expect(
      transport.calls.single.uri.path,
      '/v1/businesses/$business/employee-payees',
    );
    expect(transport.calls.single.uri.queryParameters['search'], 'Registered');
    expect(transport.calls.single.body, isNull);
    transport.response = MembershipResponse(
      200,
      jsonEncode({'businessId': 'other', 'payees': []}),
    );
    await expectLater(
      directory.findEmployeePayees(''),
      throwsA(isA<MembershipFailure>()),
    );
    transport.response = const MembershipResponse(
      403,
      '{"error":"accounting_access_required"}',
    );
    await expectLater(
      directory.findEmployeePayees(''),
      throwsA(isA<MembershipFailure>()),
    );
  });
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Expense route includes registration-owned Payee at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 1200);
        installFixedPopoutHost(tester);
        final directory = PreviewUserDirectory(
          users: [
            RegisteredUser(
              id: 'registered-employee',
              name: 'Registered Employee',
              email: 'employee@example.test',
              submittedAt: DateTime(2026, 10, 2),
              status: RegistrationStatus.approved,
              role: BusinessRole.employee,
            ),
          ],
        );
        addTearDown(directory.dispose);
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        final before = workspace.payees.all.length;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: workspace,
              userDirectory: directory,
              showInitialSetup: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final primary = find.byKey(const ValueKey('record-expense-primary'));
        await tester.tap(
          primary.evaluate().isNotEmpty
              ? primary
              : find.byKey(const ValueKey('home-record-expense-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
        await tester.pumpAndSettle();
        expect(find.text('Registered Employee'), findsOneWidget);
        expect(find.text('Employee'), findsOneWidget);
        await capture(
          tester,
          'Registered Employee Actual Expense ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('expense-add-payee')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('payee-type-field')));
        await tester.pumpAndSettle();
        expect(find.text('Employee'), findsNothing);
        await capture(
          tester,
          'Add Payee Actual Non Employee Types ${width.toInt()}',
        );
        expect(workspace.payees.all.length, before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Expense selects registered Employee but Add Payee cannot create one at $width',
      (tester) async {
        await prepare(tester, width);
        tester.view.physicalSize = Size(width, 1800);
        installFixedPopoutHost(tester);
        final employee = RegisteredUser(
          id: 'employee-id',
          name: 'Registered Employee',
          email: 'employee@example.test',
          submittedAt: DateTime(2026, 10, 2),
        );
        final directory = PreviewUserDirectory(users: [employee]);
        addTearDown(directory.dispose);
        expect(await directory.findEmployeePayees(''), isEmpty);
        await directory.approve(employee, BusinessRole.employee);
        expect(
          (await directory.findEmployeePayees('Registered')).single.type,
          PayeeType.staff,
        );
        final writes = <Payee>[];
        final store = PayeeStore(
          payees: const [
            Payee(
              id: 'unregistered-old-staff',
              name: 'Unregistered Old Staff',
              type: PayeeType.staff,
            ),
            Payee(id: 'vendor', name: 'Vendor', type: PayeeType.vendor),
          ],
          persist: writes.add,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: RecordExpensePage(
                  includeTopSafeArea: false,
                  payeeStore: store,
                  employeePayeeSearch: directory.findEmployeePayees,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
        await tester.pumpAndSettle();
        expect(find.text('Unregistered Old Staff'), findsNothing);
        expect(find.text('Registered Employee'), findsOneWidget);
        expect(find.text('Employee'), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const ValueKey('expense-add-payee'))).top,
          lessThan(tester.getRect(find.text('Registered Employee')).top),
        );
        await capture(tester, 'Registered Employee Payee ${width.toInt()}');
        await tester.tap(find.text('Registered Employee'));
        await tester.pumpAndSettle();
        final editable = find.descendant(
          of: find.byKey(const ValueKey('expense-field-payee')),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).controller.text,
          'Registered Employee',
        );
        expect(writes, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('expense-field-payee')),
          '',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('expense-add-payee')));
        await tester.pumpAndSettle();
        final selector = tester.widget<AccountingSelector<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is AccountingSelector<String> &&
                w.triggerKey == const ValueKey('payee-type-field'),
          ),
        );
        expect(
          selector.options.any(
            (option) => option.value == PayeeType.staff.name,
          ),
          isFalse,
        );
        await tester.tap(find.byKey(const ValueKey('payee-type-field')));
        await tester.pumpAndSettle();
        expect(find.text('Employee'), findsNothing);
        await capture(tester, 'Add Payee Non Employee Types ${width.toInt()}');
        expect(directory.users.single.status, RegistrationStatus.approved);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
