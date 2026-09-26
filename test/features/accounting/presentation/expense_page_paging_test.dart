import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('expense page keeps controls usable at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Arial')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/Supplemental/Arial.ttf')
                      .readAsBytesSync(),
                ),
              ),
            ))
            .load();
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(
            initialPath: '/expenses-vendors',
            workspace: workspace,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-page-next')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureUi(tester, 'Expenses Page ${width.toInt()}');
    });
  }

  testWidgets(
    'expense page loads visible rows and clears them on company switch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = await createDemoWorkspace();
      addTearDown(first.dispose);
      final expenses = await first.expenses();
      expect(expenses.length, greaterThan(10));
      final directory = Directory.systemTemp.createTempSync(
        'audyt-page-switch-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final second = await AccountingWorkspace.open(
        '${directory.path}/empty.sqlite',
      );
      addTearDown(second.dispose);

      Widget page(AccountingWorkspace workspace) => MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ExpenseIntakePage(workspace: workspace, onRecordExpense: () {}),
        ),
      );

      await tester.pumpWidget(page(first));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('open-expense-${expenses.first.id.value}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('open-expense-${expenses[5].id.value}')),
        findsNothing,
      );
      final next = find.byKey(const ValueKey('expense-page-next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('open-expense-${expenses.first.id.value}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('open-expense-${expenses[5].id.value}')),
        findsOneWidget,
      );

      await tester.pumpWidget(page(second));
      await tester.pumpAndSettle();
      expect(find.text('No Saved Expenses'), findsOneWidget);
      expect(
        find.byKey(ValueKey('open-expense-${expenses[5].id.value}')),
        findsNothing,
      );
    },
  );
}
