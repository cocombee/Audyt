import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';

void main() {
  testWidgets('home replaces stale data and listeners when workspace changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('home-workspace-state-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = await AccountingWorkspace.open('${dir.path}/first.sqlite');
    final second = await AccountingWorkspace.open('${dir.path}/second.sqlite');
    Widget host(AccountingWorkspace workspace) => MaterialApp(
      home: Scaffold(
        body: WorkspaceAccountingHome(
          workspace: workspace,
          includeTopSafeArea: true,
          onRecordExpense: () {},
        ),
      ),
    );
    await tester.pumpWidget(host(first));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AccountingHomePage>(find.byType(AccountingHomePage))
          .data
          .status,
      AccountingHomeStatus.ready,
    );
    second.database.close();
    await tester.pumpWidget(host(second));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AccountingHomePage>(find.byType(AccountingHomePage))
          .data
          .status,
      AccountingHomeStatus.error,
    );
    expect(find.text('Total Expenses'), findsNothing);
    await tester.pumpWidget(host(first));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AccountingHomePage>(find.byType(AccountingHomePage))
          .data
          .status,
      AccountingHomeStatus.ready,
    );
    await tester.pumpWidget(const SizedBox());
    first.dispose();
    second.dispose();
    expect(tester.takeException(), isNull);
  });
}
