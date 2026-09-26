import 'package:image/image.dart' as img;

import 'dart:typed_data';

import 'package:audyt/core/documents/receipt_document.dart';

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';

void main() {
  test(
    'invoice line account overrides are validated, posted and retry-safe',
    () async {
      final dir = Directory.systemTemp.createTempSync('invoice-posting-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      await w.createAccount(
        code: '1100',
        name: 'Receivables',
        type: AccountType.asset,
      );
      await w.createAccount(
        code: '4000',
        name: 'Sales',
        type: AccountType.income,
      );
      await w.createAccount(
        code: '4100',
        name: 'Services',
        type: AccountType.income,
      );
      await w.createAccount(
        code: '2200',
        name: 'Tax Payable',
        type: AccountType.liability,
      );
      final accounts = await w.accounts();
      final taxAccount = accounts
          .firstWhere((a) => a.account.code == '2200')
          .account
          .id;
      final services = accounts
          .firstWhere((a) => a.account.code == '4100')
          .account
          .id;
      final ar = accounts
          .firstWhere((a) => a.account.code == '1100')
          .account
          .id;
      final sales = accounts
          .firstWhere((a) => a.account.code == '4000')
          .account
          .id;
      final c = Customer.create(
        metadata: RecordMetadata.initial(
          recordId: EntityId.random(),
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        displayName: 'Test Customer',
        contact: const CustomerContact(),
        taxProfile: const CustomerTaxProfile(),
        currency: Currency.parse('MYR'),
        paymentTerms: PaymentTerms.netDays(30),
      );
      w.saveCustomer(c);
      final first = EntityId.random(), second = EntityId.random();
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: c.id,
        documentNumber: 'INV-LINES',
        classification: 'Projects',
        location: 'Branch A',
        taxMode: 'Exclusive',
        issueDate: DateTime.utc(2026, 1, 1),
        lines: [
          SalesLineItem.category(
            id: first,
            categoryId: sales,
            description: 'Goods',
            quantity: SalesQuantity.fromInt(1),
            rate: Money.fromMinor(3000, 'MYR'),
          ),
          SalesLineItem.category(
            id: second,
            categoryId: services,
            description: 'Work',
            quantity: SalesQuantity.fromInt(2),
            rate: Money.fromMinor(4000, 'MYR'),
            discount: Money.fromMinor(1000, 'MYR'),
            taxInclusive: true,
            taxRatePercent: '8',
          ),
        ],
      );
      w.saveInvoiceDraft(
        invoice,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      final request = EntityId.random();
      EntityId post(
        Map<EntityId, EntityId> overrides, {
        String number = 'INV-LINES',
      }) => w.postInvoice(
        requestId: request,
        invoiceId: invoice.id,
        expectedRevision: 1,
        expectedCustomerRevision: 1,
        documentNumber: number,
        receivableAccountId: ar,
        incomeAccountId: sales,
        taxAccountId: taxAccount,
        lineIncomeAccounts: overrides,
        approvedAt: DateTime.utc(2026, 1, 3),
      );
      expect(() => post({}, number: 'DIFFERENT'), throwsStateError);
      expect(
        w.invoiceDrafts().single.invoice.draftSnapshot(),
        invoice.draftSnapshot(),
      );
      expect(() => post({EntityId.random(): services}), throwsStateError);
      expect(() => post({second: ar}), throwsStateError);
      expect(await w.journals(), isEmpty);
      expect(post({first: sales, second: services}), request);
      final lines = (await w.journals()).single.entry.lines;
      expect(
        lines.singleWhere((l) => l.accountId == services).amount.minorUnits,
        6481,
      );
      expect(
        lines.singleWhere((l) => l.accountId == sales).amount.minorUnits,
        3000,
      );
      expect(
        lines.singleWhere((l) => l.accountId == ar).amount.minorUnits,
        10000,
      );
      expect(
        lines.singleWhere((l) => l.accountId == taxAccount).amount.minorUnits,
        519,
      );
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(post({second: services, first: sales}), request);
      expect(() => post({second: sales, first: sales}), throwsStateError);
      expect(await w.journals(), hasLength(1));
      expect(
        w.postedInvoices().single.sourceDraft.draftSnapshot(),
        invoice.draftSnapshot(),
      );
      final mapping = w.database.invoicePostingAccounts(
        w.identity.businessId,
        invoice.id,
      )!;
      expect(mapping.receivable, ar);
      expect(mapping.income, sales);
      expect(mapping.tax, taxAccount);
      expect(mapping.lineIncome, {first: sales, second: services});
      expect(
        () => mapping.lineIncome[first] = services,
        throwsUnsupportedError,
      );
      final creditId = EntityId.random();
      final evidence = [
        await const ReceiptDocumentPipeline().process(
          ReceiptAttachmentInput(
            originalId: 'credit-proof',
            batchId: 'batch',
            filename: 'proof.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(
              img.encodePng(img.Image(width: 100, height: 100)),
            ),
          ),
        ),
      ];
      saveCredit({int revision = 0, String reason = 'Returned service'}) =>
          w.saveInvoiceCreditDraft(
            attachments: evidence,
            draftId: creditId,
            invoiceId: invoice.id,
            lineCredits: {second: Money.fromMinor(3500, 'MYR')},
            reason: reason,
            creditDate: DateTime.utc(2026, 1, 4),
            expectedRevision: revision,
            savedAt: DateTime.utc(2026, 1, 4),
          );
      expect(saveCredit(), 1);
      expect(saveCredit(), 1);
      expect(() => saveCredit(reason: 'Changed stale draft'), throwsStateError);
      expect(saveCredit(revision: 1, reason: 'Reviewed return'), 2);
      expect(await w.journals(), hasLength(1));
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(saveCredit(revision: 1, reason: 'Reviewed return'), 2);
      final savedCredit = w.invoiceCreditDrafts().single;
      final restoredDraft = w.creditDrafts().single;
      final review = w.reviewCreditDraft(creditId);
      expect(review.allocation.receivableReduction.minorUnits, 3500);
      expect(review.allocation.customerCredit.minorUnits, 0);
      expect(
        review.lines[second]!.net.minorUnits +
            review.lines[second]!.tax.minorUnits,
        3500,
      );
      expect(() => w.reviewCreditDraft(EntityId.random()), throwsStateError);
      expect(
        restoredDraft.attachments.single.originalBytes,
        evidence.single.originalBytes,
      );
      expect(
        restoredDraft.attachments.single.originalSha256,
        evidence.single.originalSha256,
      );
      expect(
        restoredDraft.attachments.single.derivativeSha256,
        evidence.single.derivativeSha256,
      );
      final history = w.creditDraftHistory(creditId);
      expect(history.map((d) => d.revision), [2, 1]);
      expect(history.last.reason, 'Returned service');
      expect(
        history.last.attachments.single.originalSha256,
        evidence.single.originalSha256,
      );
      expect(
        w.database.invoiceCreditDraftHistory(EntityId.random(), creditId),
        isEmpty,
      );
      expect(restoredDraft.id, creditId);
      expect(restoredDraft.total, Money.fromMinor(3500, 'MYR'));
      expect(restoredDraft.date, DateTime.utc(2026, 1, 4));
      expect(restoredDraft.reason, 'Reviewed return');
      expect(() => restoredDraft.lineCredits.clear(), throwsUnsupportedError);
      expect(savedCredit.id, creditId);
      expect(savedCredit.revision, 2);
      expect(savedCredit.snapshot['reason'], 'Reviewed return');
      expect(savedCredit.snapshot['lines'], [
        {'id': second.value, 'minor': 3500, 'currency': 'MYR'},
      ]);
      expect(w.database.readInvoiceCreditDrafts(EntityId.random()), isEmpty);
      final replacement = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: evidence.single.originalId,
          batchId: 'replacement',
          filename: 'different.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList([...evidence.single.originalBytes, 0]),
        ),
      );
      expect(replacement.originalSha256, isNot(evidence.single.originalSha256));
      expect(
        () => w.saveInvoiceCreditDraft(
          draftId: creditId,
          invoiceId: invoice.id,
          lineCredits: {second: Money.fromMinor(3500, 'MYR')},
          reason: 'Replacement attempt',
          creditDate: DateTime.utc(2026, 1, 4),
          expectedRevision: 2,
          savedAt: DateTime.utc(2026, 1, 5),
          attachments: [replacement],
        ),
        throwsStateError,
      );
      expect(w.creditDrafts().single.revision, 2);
      expect(
        w.creditDrafts().single.attachments.single.originalSha256,
        evidence.single.originalSha256,
      );
      final raw = sqlite3.open(path);
      addTearDown(raw.dispose);
      expect(
        raw.select('SELECT * FROM invoice_credit_draft_history'),
        hasLength(2),
      );
      expect(
        () => raw.execute(
          "UPDATE invoice_credit_draft_history SET payload = '{}'",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => raw.execute('DELETE FROM invoice_credit_draft_history'),
        throwsA(isA<SqliteException>()),
      );
      raw.execute(
        "CREATE TRIGGER fail_credit_history BEFORE INSERT ON invoice_credit_draft_history BEGIN SELECT RAISE(ABORT, 'injected history failure'); END",
      );
      expect(
        () => saveCredit(revision: 2, reason: 'Final review'),
        throwsA(isA<SqliteException>()),
      );
      final afterFailure = w.invoiceCreditDrafts().single;
      expect(afterFailure.revision, 2);
      expect(afterFailure.snapshot, savedCredit.snapshot);
      expect(
        raw.select('SELECT * FROM invoice_credit_draft_history'),
        hasLength(2),
      );
      expect(await w.journals(), hasLength(1));
      raw.execute('DROP TRIGGER fail_credit_history');
      expect(saveCredit(revision: 2, reason: 'Final review'), 3);
      expect(
        raw.select('SELECT * FROM invoice_credit_draft_history'),
        hasLength(3),
      );
      await w.createAccount(
        code: '1000',
        name: 'Bank',
        type: AccountType.asset,
      );
      final bank = (await w.accounts())
          .singleWhere((a) => a.account.code == '1000')
          .account
          .id;
      w.receiveInvoicePayment(
        requestId: EntityId.random(),
        customerId: c.id,
        bankAccountId: bank,
        allocations: {invoice.id: Money.fromMinor(8000, 'MYR')},
        reference: 'Credit review payment',
        receivedAt: DateTime.utc(2026, 1, 5),
      );
      final afterPayment = w.reviewCreditDraft(creditId);
      expect(afterPayment.allocation.receivableReduction.minorUnits, 2000);
      expect(afterPayment.allocation.customerCredit.minorUnits, 1500);
      expect(afterPayment.allocation.remainingReceivable.minorUnits, 0);
      await expectLater(w.creditDraftJournal(creditId), throwsStateError);
      await expectLater(
        w.creditDraftJournal(creditId, customerCreditAccount: bank),
        throwsStateError,
      );
      await expectLater(
        w.creditDraftJournal(creditId, customerCreditAccount: taxAccount),
        throwsStateError,
      );
      await w.createAccount(
        code: '2300',
        name: 'Customer Credits',
        type: AccountType.liability,
      );
      final creditAccount = (await w.accounts())
          .singleWhere((a) => a.account.code == '2300')
          .account
          .id;
      final proposal = await w.creditDraftJournal(
        creditId,
        customerCreditAccount: creditAccount,
      );
      expect(
        proposal
            .singleWhere((line) => line.accountId == creditAccount)
            .amount
            .minorUnits,
        1500,
      );
      expect(
        proposal.singleWhere((line) => line.accountId == ar).amount.minorUnits,
        2000,
      );

      expect(w.creditDrafts().single.total.minorUnits, 3500);
      expect(await w.journals(), hasLength(2));
      expect(
        () => w.restoreCreditDraftRevision(
          draftId: creditId,
          sourceRevision: 1,
          expectedRevision: 2,
          restoredAt: DateTime.utc(2026, 1, 6),
        ),
        throwsStateError,
      );
      expect(
        w.restoreCreditDraftRevision(
          draftId: creditId,
          sourceRevision: 1,
          expectedRevision: 3,
          restoredAt: DateTime.utc(2026, 1, 6),
        ),
        4,
      );
      expect(w.creditDrafts().single.reason, 'Returned service');
      expect(w.creditDraftHistory(creditId).map((r) => r.revision), [
        4,
        3,
        2,
        1,
      ]);
      expect(
        w.creditDrafts().single.attachments.single.originalSha256,
        evidence.single.originalSha256,
      );
      final postingId = EntityId.random();
      EntityId postCredit() => w.database.postInvoiceCredit(
        businessId: w.identity.businessId,
        actorId: w.identity.ownerId,
        requestId: postingId,
        draftId: creditId,
        expectedRevision: 4,
        expectedPaidMinor: 8000,
        expectedPriorCreditMinor: 0,
        approvedAt: DateTime.utc(2026, 1, 7),
        customerCreditAccount: creditAccount,
      );
      raw.execute(
        "CREATE TRIGGER fail_credit_lines BEFORE INSERT ON invoice_credit_lines BEGIN SELECT RAISE(ABORT,'injected credit failure'); END",
      );
      expect(postCredit, throwsA(isA<SqliteException>()));
      expect(await w.journals(), hasLength(2));
      expect(raw.select('SELECT * FROM invoice_credit_postings'), isEmpty);
      raw.execute('DROP TRIGGER fail_credit_lines');
      expect(postCredit(), postingId);
      expect(
        w.database
            .invoiceCreditPosting(w.identity.businessId, creditId)!
            .customerCredit
            .minorUnits,
        1500,
      );
      expect(
        w.database.invoiceCreditPosting(EntityId.random(), creditId),
        isNull,
      );
      expect(postCredit(), postingId);
      expect(await w.journals(), hasLength(3));
      expect(w.postedInvoices().single.paidMinor, 8000);
      expect(w.postedInvoices().single.creditedMinor, 2000);
      expect(
        w.database
            .customerStatement(
              w.identity.businessId,
              c.id,
              DateTime.utc(2026, 1, 8),
            )
            .last
            .balance
            .minorUnits,
        -1500,
      );
      expect(
        w.database
            .customerStatement(
              w.identity.businessId,
              c.id,
              DateTime.utc(2026, 1, 3),
            )
            .last
            .balance
            .minorUnits,
        10000,
      );
      expect(
        w.database.receivablesAsOf(
          w.identity.businessId,
          DateTime.utc(2026, 1, 8),
        ),
        isEmpty,
      );
      expect(
        w.database
            .receivablesAsOf(w.identity.businessId, DateTime.utc(2026, 1, 3))
            .single
            .remaining
            .minorUnits,
        10000,
      );
      expect(
        w.database
            .invoicePriorCreditLines(w.identity.businessId, invoice.id)[second]!
            .minorUnits,
        3500,
      );
      expect(
        raw
            .select('SELECT customer_credit_minor FROM invoice_credit_postings')
            .single['customer_credit_minor'],
        1500,
      );
      expect(
        () => w.restoreCreditDraftRevision(
          draftId: creditId,
          sourceRevision: 1,
          expectedRevision: 4,
          restoredAt: DateTime.utc(2026, 1, 8),
        ),
        throwsStateError,
      );
      expect(
        () => saveCredit(revision: 4, reason: 'Alter posted credit'),
        throwsStateError,
      );
      expect(
        () => raw.execute('DELETE FROM invoice_credit_lines'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => raw.execute('UPDATE invoice_credit_postings SET revision=99'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => w.receiveInvoicePayment(
          requestId: EntityId.random(),
          customerId: c.id,
          bankAccountId: bank,
          allocations: {invoice.id: Money.fromMinor(1, 'MYR')},
          reference: 'Already credited',
          receivedAt: DateTime.utc(2026, 1, 8),
        ),
        throwsStateError,
      );
      expect(await w.journals(), hasLength(3));
      expect(w.postedInvoices().single.paidMinor, 8000);
      expect(w.postedInvoices().single.creditedMinor, 2000);
      expect(
        w.database
            .customerStatement(
              w.identity.businessId,
              c.id,
              DateTime.utc(2026, 1, 8),
            )
            .last
            .balance
            .minorUnits,
        -1500,
      );
      expect(
        w.database
            .customerStatement(
              w.identity.businessId,
              c.id,
              DateTime.utc(2026, 1, 3),
            )
            .last
            .balance
            .minorUnits,
        10000,
      );
      expect(
        w.database.receivablesAsOf(
          w.identity.businessId,
          DateTime.utc(2026, 1, 8),
        ),
        isEmpty,
      );
      expect(
        w.database
            .receivablesAsOf(w.identity.businessId, DateTime.utc(2026, 1, 3))
            .single
            .remaining
            .minorUnits,
        10000,
      );

      w.dispose();
    },
  );
}
