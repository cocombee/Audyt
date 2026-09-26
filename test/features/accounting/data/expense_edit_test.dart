import 'dart:typed_data';
import 'dart:convert';

import 'package:audyt/core/documents/receipt_document.dart';

import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';

import 'expense_intake_test.dart' show draft;

void main() {
  test(
    'unposted edit survives restart and stale edit does not replace it',
    () async {
      final dir = Directory.systemTemp.createTempSync('expense-edit-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'cash',
          name: 'Cash',
          type: PaymentAccountType.cash,
          currencyCode: 'MYR',
        ),
      );
      final original = draft(
        paymentAccountId: 'cash',
        attachments: [
          ReceiptAttachment.queued(
            ReceiptAttachmentInput(
              originalId: 'kept-evidence',
              batchId: 'batch',
              filename: 'receipt.png',
              mimeType: 'image/png',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ],
      );
      final id = await workspace.saveExpenseIntake(original);
      final changed = RecordExpenseDraft.fromJson({
        ...original.toJson(),
        'notes': 'Corrected',
        'amount': '30.00',
        'attachments': <Object>[],
      });
      Future<void> edit(RecordExpenseDraft value) => workspace
          .updateExpenseIntake(id: id, expected: original, replacement: value);
      final raw = sqlite3.open(path);
      addTearDown(raw.dispose);
      raw.execute(
        "CREATE TRIGGER reject_edit_audit BEFORE INSERT ON ledger_audit BEGIN SELECT RAISE(ABORT, 'Simulated audit failure'); END",
      );
      await expectLater(edit(changed), throwsA(isA<SqliteException>()));
      final unchanged = (await workspace.expense(id))!;
      expect(unchanged.draft.toJson(), original.toJson());
      expect(unchanged.summary.amount.minorUnits, 2550);
      expect(
        await workspace.database.auditEvents(workspace.identity.businessId),
        isEmpty,
      );
      raw.execute('DROP TRIGGER reject_edit_audit');
      final changedOriginal = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'kept-evidence',
          batchId: 'batch',
          filename: 'receipt.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList([9, 9, 9]),
        ),
      );
      await expectLater(
        edit(
          RecordExpenseDraft.fromJson({
            ...original.toJson(),
            'attachments': [changedOriginal.toJson()],
          }),
        ),
        throwsStateError,
      );
      expect(
        (await workspace.expense(id))!.draft.attachments.single.originalBytes,
        [1, 2, 3],
      );
      expect(
        await workspace.database.auditEvents(workspace.identity.businessId),
        isEmpty,
      );

      await expectLater(
        workspace.database.updateExpenseIntake(
          businessId: workspace.identity.businessId,
          id: id,
          actorId: EntityId.random(),
          expected: original,
          replacement: changed,
          changedAt: DateTime.utc(2026, 9, 13),
        ),
        throwsStateError,
      );
      await expectLater(
        edit(
          RecordExpenseDraft.fromJson({
            ...original.toJson(),
            'paymentAccountId': 'missing-account',
          }),
        ),
        throwsStateError,
      );
      expect((await workspace.expense(id))!.draft.toJson(), original.toJson());
      expect(
        await workspace.database.auditEvents(workspace.identity.businessId),
        isEmpty,
      );
      await edit(changed);
      await edit(changed);
      await expectLater(
        edit(
          RecordExpenseDraft.fromJson({...original.toJson(), 'notes': 'Stale'}),
        ),
        throwsStateError,
      );
      expect(
        await workspace.database.auditEvents(workspace.identity.businessId),
        hasLength(1),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      final restored = (await workspace.expense(id))!;
      expect(restored.draft.notes, 'Corrected');
      expect(restored.draft.attachments, isEmpty);
      final events = await workspace.database.auditEvents(
        workspace.identity.businessId,
      );
      final before =
          jsonDecode(events.single['detail'] as String)['before']
              as Map<String, dynamic>;
      final retained = RecordExpenseDraft.fromJson(before);
      expect(retained.attachments.single.originalBytes, [1, 2, 3]);
      expect(restored.summary.amount.minorUnits, 3000);
      expect(restored.draft.submissionId, original.submissionId);
      expect(await workspace.journals(), isEmpty);
    },
  );
}
