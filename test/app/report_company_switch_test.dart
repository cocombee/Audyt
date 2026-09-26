import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/ledger_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Reports clears company measures when its workspace changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final alpha = await createDemoWorkspace();
    addTearDown(alpha.dispose);
    final directory = Directory.systemTemp.createTempSync(
      'audyt-report-switch-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final beta = await AccountingWorkspace.open(
      '${directory.path}/beta.sqlite',
    );
    addTearDown(beta.dispose);
    expect(alpha.identity.businessId, isNot(beta.identity.businessId));

    Widget page(AccountingWorkspace workspace) => MaterialApp(
      theme: AccountingTheme.light(),
      home: Scaffold(
        body: LedgerReportsPage(workspace: workspace, compact: false),
      ),
    );
    await tester.pumpWidget(page(alpha));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-0'))).data,
      isNot('—'),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-summary-Accounts Tracked')),
        matching: find.text('0 Accounts'),
      ),
      findsNothing,
    );

    await tester.pumpWidget(page(beta));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('quality-value-0'))).data,
      '—',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-summary-Accounts Tracked')),
        matching: find.text('0 Accounts'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
