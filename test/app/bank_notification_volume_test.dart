import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

void main() {
  test('bank review keeps exact totals and bounded notices at 100000 rows', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-bank-notification-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${root.path}/books.sqlite',
    );
    addTearDown(workspace.dispose);
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    final csv = StringBuffer('Date,Description,Amount,Reference\n');
    for (var i = 0; i < 100000; i++) {
      csv.writeln('2026-09-01,Movement $i,-1.00,REF$i');
    }
    final source = BankStatementImport.csv(
      filename: 'Volume.csv',
      currency: 'MYR',
      bytes: Uint8List.fromList(utf8.encode(csv.toString())),
    );
    workspace.database.importBankStatement(
      id: EntityId.random(),
      businessId: workspace.identity.businessId,
      paymentAccountId: 'bank',
      statement: source,
      importedAt: DateTime.utc(2026, 9, 29),
    );
    final stopwatch = Stopwatch()..start();
    final rows = workspace.unresolvedBankStatementRows;
    final first = stopwatch.elapsedMilliseconds;
    final awaiting = workspace.bankStatementsAwaitingApproval;
    final second = stopwatch.elapsedMilliseconds;
    final count = workspace.bankReviewNotificationCount;
    final third = stopwatch.elapsedMilliseconds;
    expect(rows, 100000);
    expect(awaiting, 1);
    expect(count, 100001);
    expect(workspace.bankReviewSnapshot.recent, hasLength(50));
    expect(workspace.bankReviewSnapshot.total, 100001);
    final updated = BankStatementImport.csv(
      filename: 'Later.csv',
      currency: 'MYR',
      bytes: Uint8List.fromList(
        utf8.encode(
          'Date,Description,Amount,Reference\n2026-09-29,Later movement,-2.00,LATER\n',
        ),
      ),
    );
    workspace.database.importBankStatement(
      id: EntityId.random(),
      businessId: workspace.identity.businessId,
      paymentAccountId: 'bank',
      statement: updated,
      importedAt: DateTime.utc(2026, 9, 30),
    );
    expect(workspace.bankReviewSnapshot.total, 100003);
    expect(workspace.bankReviewSnapshot.recent, hasLength(50));
    expect(workspace.bankReviewSnapshot.recent.first.title, 'Later movement');
    final otherConnection = await AccountingWorkspace.open(
      '${root.path}/books.sqlite',
    );
    addTearDown(otherConnection.dispose);
    expect(otherConnection.identity.businessId, workspace.identity.businessId);
    otherConnection.database.importBankStatement(
      id: EntityId.random(),
      businessId: workspace.identity.businessId,
      paymentAccountId: 'bank',
      statement: BankStatementImport.csv(
        filename: 'Other Connection.csv',
        currency: 'MYR',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Date,Description,Amount\n2026-09-30,Cross-connection movement,-3.00\n',
          ),
        ),
      ),
      importedAt: DateTime.utc(2026, 9, 30),
    );
    expect(workspace.bankReviewSnapshot.total, 100005);
    expect(
      workspace.bankReviewSnapshot.recent.first.title,
      'Cross-connection movement',
    );
    debugPrint(
      'Bank notifications 100000 rows: first=${first}ms awaiting=${second - first}ms combined=${third - second}ms total=${third}ms db=${File('${root.path}/books.sqlite').lengthSync()} bytes',
    );
  });

  testWidgets('bank notification bell keeps exact count and routes overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = Directory.systemTemp.createTempSync('audyt-bank-bell-');
    addTearDown(() => root.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${root.path}/books.sqlite',
    );
    addTearDown(workspace.dispose);
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'bank',
        name: 'Bank',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    final csv = StringBuffer('Date,Description,Amount\n');
    for (var i = 0; i < 60; i++) {
      csv.writeln('2026-09-01,Movement $i,-1.00');
    }
    workspace.database.importBankStatement(
      id: EntityId.random(),
      businessId: workspace.identity.businessId,
      paymentAccountId: 'bank',
      statement: BankStatementImport.csv(
        filename: 'Volume.csv',
        currency: 'MYR',
        bytes: Uint8List.fromList(utf8.encode(csv.toString())),
      ),
      importedAt: DateTime.utc(2026, 9, 29),
    );
    await tester.pumpWidget(AudytApp(workspace: workspace));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('global-notification-badge')),
        matching: find.text('61'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('global-notifications')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notifications-read-more')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('notifications-scroll-list')),
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();
    expect(find.text('More Bank Activity'), findsOneWidget);
    expect(find.text('11 more need review in Banking'), findsOneWidget);
    final other = await AccountingWorkspace.open('${root.path}/other.sqlite');
    addTearDown(other.dispose);
    expect(other.identity.businessId, isNot(workspace.identity.businessId));
    await tester.pumpWidget(AudytApp(workspace: other));
    await tester.pumpAndSettle();
    expect(find.text('More Bank Activity'), findsNothing);
    expect(find.text('61'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('global-notifications')));
    await tester.pumpAndSettle();
    expect(find.text('No notifications'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
