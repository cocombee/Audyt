import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:audyt/core/documents/receipt_document.dart';

import '../features/accounting/data/expense_intake_test.dart' show draft;

import 'dart:io';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'saved receipt preview keeps original and derivative evidence without writes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('saved-receipt-view-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      final original = Uint8List.fromList(
        image.encodePng(image.Image(width: 20, height: 30)),
      );
      final edited = Uint8List.fromList(
        image.encodePng(image.Image(width: 10, height: 15)),
      );
      final attachment =
          ReceiptAttachment.queued(
            ReceiptAttachmentInput(
              originalId: 'saved-image',
              batchId: 'batch',
              filename: 'Receipt.png',
              mimeType: 'image/png',
              bytes: original,
            ),
          ).withDerivative(
            derivativeId: 'edited',
            bytes: edited,
            mimeType: 'image/png',
            width: 10,
            height: 15,
            printReadyAt300Dpi: false,
          );
      final id = await workspace.saveExpenseIntake(
        draft(
          attachments: [attachment],
          recurrence: RecurrenceRule(
            startsOn: DateTime.utc(2026, 9, 30),
            unit: RecurrenceUnit.months,
            every: 3,
            occurrenceCount: 4,
          ),
        ),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final before = (await workspace.expense(id))!.draft.toJson();
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/expenses-vendors'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('open-expense-${id.value}')));
      await tester.pumpAndSettle();
      expect(find.text('Every 3 months'), findsOneWidget);
      expect(find.text('After 4 occurrences'), findsOneWidget);
      final action = find.byKey(
        const ValueKey('expense-attachment-view-saved-image'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
      final preview = tester.widget<Image>(find.byType(Image).last);
      expect((preview.image as MemoryImage).bytes, original);
      expect(
        (await workspace.expense(id))!.draft.attachments.single.originalBytes,
        original,
      );
      expect(
        (await workspace.expense(id))!.draft.attachments.single.derivativeBytes,
        edited,
      );
      expect((await workspace.expense(id))!.draft.toJson(), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'production expense save survives restart as intake without a guessed journal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      final dir = Directory.systemTemp.createTempSync('audyt-expense-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'cash-id',
          name: 'Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
      await tester.pumpWidget(AudytApp(workspace: workspace));
      await tester.tap(
        find.byKey(const ValueKey('home-record-expense-action')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('expense-field-amount')),
        '25.50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expense-field-payee')),
        'Local stationery shop',
      );
      await _chooseDropdown(
        tester,
        const ValueKey('expense-field-payment-account'),
        'Cash · Cash · RM',
      );
      await _chooseDropdown(
        tester,
        const ValueKey('expense-field-category'),
        'Office Operations',
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('record-expense-save')),
      );
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('page-title-expenses-vendors')),
        findsOneWidget,
      );
      final expenseTitle = tester.getRect(
        find.byKey(const ValueKey('page-title-expenses-vendors')),
      );
      expect(expenseTitle.left, greaterThan(0));
      expect(
        find.byKey(const ValueKey('expense-recurring-schedules')),
        findsNothing,
      );
      expect(find.text('Expense saved for accounting review'), findsOneWidget);
      expect(find.text('Local stationery shop'), findsOneWidget);
      expect(find.text('RM 25.50'), findsWidgets);
      expect(await workspace.journals(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        AudytApp(workspace: workspace, initialPath: '/expenses-vendors'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Local stationery shop'), findsOneWidget);
      expect(find.text('RM 25.50'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.byTooltip('Needs Review'), findsOneWidget);
      final record = (await workspace.expenses()).single;
      final view = find.byKey(ValueKey('open-expense-${record.id.value}'));
      await tester.ensureVisible(view);
      await tester.tap(view);
      await tester.pumpAndSettle();
      expect(find.text('Expense Details'), findsOneWidget);
      expect(find.text('Cash · Cash · RM'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  Key fieldKey,
  String option,
) async {
  await tester.ensureVisible(find.byKey(fieldKey));
  await tester.tap(find.byKey(fieldKey));
  await tester.pumpAndSettle();
  if (find.textContaining(option).evaluate().isEmpty &&
      find.byKey(fieldKey).evaluate().isNotEmpty) {
    tester.widget<OutlinedButton>(find.byKey(fieldKey)).onPressed?.call();
    await tester.pumpAndSettle();
  }
  final optionFinder = find.textContaining(option).last;
  await tester.ensureVisible(optionFinder);
  await tester.tap(optionFinder);
  await tester.pumpAndSettle();
}
