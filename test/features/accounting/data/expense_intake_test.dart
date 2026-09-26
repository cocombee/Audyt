import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/receipt_review_queue.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';

RecordExpenseDraft draft({
  String amount = '25.50',
  String? paymentAccountId,
  RecurrenceRule? recurrence,
  List<ReceiptAttachment> attachments = const [],
  List<Map<String, dynamic>> reviews = const [],
}) => RecordExpenseDraft(
  submissionId: 'stable-submission',
  amount: amount,
  date: '13-09-2026',
  payee: 'Stationery Shop',
  paymentAccount: 'Cash',
  paymentAccountId: paymentAccountId,
  recurrence: recurrence,
  category: 'Office Operations',
  tax: 'Review Needed',
  customer: '',
  billable: false,
  dimensions: '',
  itemOrSplitDetails: '',
  notes: 'Original note',
  attachments: attachments,
  reviewSnapshots: reviews,
);
void main() {
  test('expense recurrence survives restart without generating or posting occurrences', () async {
    final dir = Directory.systemTemp.createTempSync('expense-recurrence-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final rule = RecurrenceRule(
      startsOn: DateTime.utc(2026, 9, 30),
      unit: RecurrenceUnit.months,
      every: 3,
      occurrenceCount: 4,
    );
    final intake = draft(recurrence: rule);
    final raw = sqlite3.open(path);
    raw.execute(
      "CREATE TRIGGER reject_initial_schedule BEFORE INSERT ON recurring_expense_template_history BEGIN SELECT RAISE(ABORT, 'Storage failure'); END",
    );
    await expectLater(
      workspace.saveExpenseIntake(intake),
      throwsA(isA<SqliteException>()),
    );
    expect(raw.select('SELECT id FROM expense_intakes'), isEmpty);
    expect(raw.select('SELECT id FROM recurring_expense_templates'), isEmpty);
    raw.execute('DROP TRIGGER reject_initial_schedule');
    raw.dispose();
    final id = await workspace.saveExpenseIntake(intake);
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    final saved = (await workspace.expense(id))!.draft;
    expect(saved.recurrence!.toJson(), rule.toJson());
    final templates = workspace.database.recurringExpenseTemplates(
      workspace.identity.businessId,
    );
    expect(templates.single.sourceExpenseId, id.value);
    expect(templates.single.schedule.toJson(), rule.toJson());
    expect(
      workspace.database
          .recurringExpenseTemplateHistory(
            workspace.identity.businessId,
            templates.single.id,
          )
          .length,
      1,
    );

    expect(saved.recurrence!.preview(), [
      DateTime.utc(2026, 9, 30),
      DateTime.utc(2026, 12, 31),
      DateTime.utc(2027, 3, 31),
      DateTime.utc(2027, 6, 30),
    ]);
    expect(await workspace.saveExpenseIntake(intake), id);
    expect(draft().toJson().containsKey('recurrence'), isFalse);
  });
  test(
    'expense account identity validates currency and survives account rename',
    () async {
      final dir = Directory.systemTemp.createTempSync('expense-account-link-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      final intake = draft(paymentAccountId: 'cash');
      await expectLater(workspace.saveExpenseIntake(intake), throwsStateError);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'cash',
          name: 'Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'USD',
        ),
      );
      await expectLater(workspace.saveExpenseIntake(intake), throwsStateError);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'cash',
          name: 'Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
      final id = await workspace.saveExpenseIntake(intake);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'cash',
          name: 'Office Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
      expect(await workspace.saveExpenseIntake(intake), id);
      final saved = (await workspace.expense(id))!.draft;
      expect(saved.paymentAccountId, 'cash');
      expect(saved.paymentAccount, 'Cash');
      expect(workspace.paymentAccounts.single.name, 'Office Cash');
    },
  );
  test('expense intake retries once, retains evidence after reopen, and creates no financial posting', () async {
    final dir = Directory.systemTemp.createTempSync('audyt-intake-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ledger.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    final receipt =
        ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'receipt',
            batchId: 'batch',
            filename: 'original.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ).withDerivative(
          derivativeId: 'crop',
          bytes: Uint8List.fromList([4, 5]),
          mimeType: 'image/png',
          width: 20,
          height: 30,
          printReadyAt300Dpi: false,
        );
    final item = ReceiptReviewItem(receipt);
    item.cropHistory.apply(
      const NormalizedCropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9),
    );
    item.save();
    final intake = draft(
      attachments: [receipt],
      reviews: [Map<String, dynamic>.from(item.toJson())],
    );
    item.dispose();
    final savedId = await workspace.saveExpenseIntake(intake);
    expect(await workspace.saveExpenseIntake(intake), savedId);
    await expectLater(
      workspace.saveExpenseIntake(draft(amount: '26.00')),
      throwsStateError,
    );
    expect(await workspace.journals(), isEmpty);
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    expect(await workspace.expenses(), hasLength(1));
    final restored = (await workspace.expense(savedId))!;
    expect(restored.summary.isPosted, isFalse);
    expect(restored.summary.amount.minorUnits, 2550);
    expect(restored.draft.notes, 'Original note');
    expect(restored.draft.attachments.single.originalBytes, [1, 2, 3]);
    expect(restored.draft.attachments.single.derivativeBytes, [4, 5]);
    final history = ReceiptReviewItem.fromJson(
      restored.draft.reviewSnapshots.single,
    );
    addTearDown(history.dispose);
    expect(history.cropHistory.canUndo, isTrue);
    history.cropHistory.undo();
    expect(history.cropHistory.present, NormalizedCropRect.full);
  });
  test(
    'mismatched receipt history fails before any intake is committed',
    () async {
      final dir = Directory.systemTemp.createTempSync('audyt-intake-invalid-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      final receipt = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'wrong',
          batchId: 'batch',
          filename: 'wrong.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final item = ReceiptReviewItem(receipt);
      addTearDown(item.dispose);
      await expectLater(
        workspace.saveExpenseIntake(
          draft(reviews: [Map<String, dynamic>.from(item.toJson())]),
        ),
        throwsFormatException,
      );
      expect(await workspace.expenses(), isEmpty);
      expect(await workspace.journals(), isEmpty);
    },
  );
}
