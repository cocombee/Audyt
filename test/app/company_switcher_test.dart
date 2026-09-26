import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/company_switcher.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';

void main() {
  testWidgets('sidebar switches company from a selector menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('company-selector-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final workspace = await AccountingWorkspace.open(
      '${dir.path}/books.sqlite',
    );
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      AudytApp(initialPath: '/home', workspace: workspace),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const ValueKey('company-switcher'));
    expect(DemoCompany.active(tester.element(trigger)), false);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('company-option-current')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('company-option-demo')), findsOneWidget);
    expect(find.text('Switch Company'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('company-option-demo')));
    await tester.pumpAndSettle();
    expect(DemoCompany.active(tester.element(trigger)), true);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('company-option-current')));
    await tester.pumpAndSettle();
    expect(DemoCompany.active(tester.element(trigger)), false);
  });

  testWidgets('company preview opens and switches isolated example context', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(body: CompanySwitcher()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Example companies contain no live records'),
      findsOneWidget,
    );
    await tester.tap(find.text('Example Company A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example Company B').last);
    await tester.pumpAndSettle();
    expect(find.text('Example Company B'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
