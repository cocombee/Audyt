import '../support/accounting_test_finders.dart';
import '../support/fixed_popout_host.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  testWidgets('expense list exposes preview and opens View as a popout', (
    tester,
  ) async {
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    await tester.binding.setSurfaceSize(const Size(1224, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ExpenseIntakePage(workspace: workspace, onRecordExpense: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final more = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('expense-more-'),
        )
        .first;
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            (w.key as ValueKey).value.toString().startsWith(
              'expense-row-attachment-',
            ),
      ),
      findsWidgets,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    final view = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('open-expense-'),
        )
        .first;
    await tester.tap(view);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(RecordExpensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets('all saved demo expense forms render at $width', (
      tester,
    ) async {
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
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
      installFixedPopoutHost(tester);
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      await tester.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final summaries = await workspace.expenses();
      expect(summaries, isNotEmpty);
      for (final summary in summaries) {
        final record = (await workspace.expense(summary.id))!;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: RecordExpensePage(
                  key: ValueKey(summary.id.value),
                  savedDraft: record.draft,
                  includeTopSafeArea: false,
                  readOnly: summary.isPosted,
                  accounts: workspace.paymentAccounts,
                  payeeStore: workspace.payees,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: summary.id.value);
        if (summary.id == summaries.first.id) {
          await captureUi(tester, 'Saved Expense ${width.toInt()}');
        }
        expect(find.text(record.draft.category), findsWidgets);
        if (summary.isPosted) {
          expect(
            find.byKey(const ValueKey('record-expense-save')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('expense-add-account')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('expense-add-payee')), findsNothing);
        }
        for (final attachment in record.draft.attachments) {
          final view = find.byKey(
            ValueKey('expense-attachment-view-${attachment.originalId}'),
          );
          await tester.ensureVisible(view);
          await tester.tap(view);
          await tester.pump();
          // Image codec completion needs real event-loop time. Fake-clock
          // pumpAndSettle cannot finish a native decode still in flight.
          final loading = find.descendant(
            of: find.byType(AttachmentPreviewDialog),
            matching: find.byType(CircularProgressIndicator),
          );
          for (
            var attempt = 0;
            attempt < 250 && loading.evaluate().isNotEmpty;
            attempt++
          ) {
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
            await tester.pump();
          }
          expect(
            loading,
            findsNothing,
            reason: 'Receipt preview finishes loading',
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: find.byType(AttachmentPreviewDialog),
              matching: find.text(attachment.filename),
            ),
            attachment.isImage ? findsNothing : findsWidgets,
          );
          await tester.tap(accountingCloseIcon().last);
          await tester.pumpAndSettle();
        }
      }
    });
  }
}
