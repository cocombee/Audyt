import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/expense_intake_test.dart' show draft;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Expense remove/cancel/restart/view/restore on actual route at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = Directory.systemTemp.createTempSync('expense-remove-ui-');
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/books.sqlite';
        var w = await AccountingWorkspace.open(path);
        final original = draft();
        final id = await w.saveExpenseIntake(original);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        Widget app() => RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: w, initialPath: '/expenses-vendors'),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        Future<void> tap(String key) async {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await tap('expense-delete-${id.value}');
        await tap('expense-cancel-removal');
        expect((await w.expense(id))!.summary.revision, 1);
        expect(await w.database.auditEvents(w.identity.businessId), isEmpty);
        await tap('expense-delete-${id.value}');
        await tap('expense-confirm-removal');
        expect(find.byKey(ValueKey('open-expense-${id.value}')), findsNothing);
        expect(
          find.byKey(const ValueKey('expense-toggle-removed')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        w.dispose();
        w = await AccountingWorkspace.open(path);
        addTearDown(w.dispose);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('open-expense-${id.value}')), findsNothing);
        await tap('expense-toggle-removed');
        expect(find.text('Removed'), findsOneWidget);
        expect(
          find.byKey(ValueKey('expense-delete-${id.value}')),
          findsNothing,
        );
        await captureUi(tester, 'Removed Expense ${width.toInt()}');
        await tap('open-expense-${id.value}');
        expect(find.byKey(const ValueKey('record-expense-save')), findsNothing);
        expect(
          find.byKey(ValueKey('review-expense-posting-${id.value}')),
          findsNothing,
        );
        for (final field in tester.widgetList<TextFormField>(
          find.byType(TextFormField),
        )) {
          expect(
            field.enabled,
            isFalse,
            reason: 'Removed Expense fields must be read-only.',
          );
        }
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        await tap('expense-restore-${id.value}');
        await tap('expense-cancel-removal');
        expect(await w.expenses(), isEmpty);
        await tap('expense-restore-${id.value}');
        await tap('expense-confirm-removal');
        expect((await w.expense(id))!.draft.toJson(), original.toJson());
        expect((await w.expense(id))!.summary.revision, 3);
        await tap('expense-toggle-removed');
        expect(
          find.byKey(ValueKey('expense-delete-${id.value}')),
          findsOneWidget,
        );
        await captureUi(tester, 'Restored Expense ${width.toInt()}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
