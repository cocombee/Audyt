import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
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
    'invoice posting is atomic, immutable, revision-bound and restart-safe',
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
      final accounts = await w.accounts();
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
      Invoice draft() => Invoice.draft(
        id: EntityId.random(),
        customerId: c.id,
        total: Money.fromMinor(10000, 'MYR'),
        issueDate: DateTime.utc(2026, 1, 1),
        terms: c.paymentTerms,
        reference: 'PO-001',
        memo: 'Retain the reviewed delivery note.',
        attachments: ClaimStore.demo().all.first.attachments,
      );
      final invoice = draft();
      final legacy = Map<String, dynamic>.from(invoice.draftSnapshot())
        ..remove('reference')
        ..remove('memo')
        ..remove('attachments');
      expect(Invoice.fromDraftSnapshot(legacy).draftSnapshot(), legacy);
      expect(
        () => Invoice.draft(
          id: EntityId.random(),
          customerId: c.id,
          total: invoice.total,
          issueDate: invoice.issueDate,
          attachments: [invoice.attachments.first, invoice.attachments.first],
        ),
        throwsArgumentError,
      );
      w.saveInvoiceDraft(
        invoice,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      final request = EntityId.random();
      EntityId post(
        Invoice i, {
        EntityId? requestId,
        String number = 'INV-001',
        int revision = 1,
        EntityId? income,
      }) => w.postInvoice(
        requestId: requestId ?? request,
        invoiceId: i.id,
        expectedRevision: revision,
        expectedCustomerRevision: 1,
        documentNumber: number,
        receivableAccountId: ar,
        incomeAccountId: income ?? sales,
        approvedAt: DateTime.utc(2026, 1, 3),
      );
      expect(() => post(invoice, revision: 2), throwsStateError);
      expect(() => post(invoice, income: ar), throwsStateError);
      expect(await w.journals(), isEmpty);
      expect(post(invoice), request);
      expect(post(invoice), request);
      expect(await w.journals(), hasLength(1));
      expect(w.invoiceDrafts(), isEmpty);
      final postedRecord = w.postedInvoices().single;
      expect(postedRecord.documentNumber, 'INV-001');
      expect(postedRecord.journalId, request);
      expect(postedRecord.sourceDraft.id, invoice.id);
      expect(postedRecord.sourceDraft.total, invoice.total);
      expect(postedRecord.customerSnapshot.displayName, c.displayName);
      expect(w.database.readPostedInvoices(EntityId.random()), isEmpty);

      expect(
        () => w.saveInvoiceDraft(
          invoice,
          expectedRevision: 1,
          savedAt: DateTime.utc(2026, 1, 4),
        ),
        throwsStateError,
      );
      final duplicate = draft();
      w.saveInvoiceDraft(
        duplicate,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      expect(
        () => post(duplicate, requestId: EntityId.random()),
        throwsA(isA<SqliteException>()),
      );
      expect(
        await w.journals(),
        hasLength(1),
      ); // Unique number failure rolls back posting.
      final reservedNumber = w.database.allocateDocumentNumber(
        businessId: w.identity.businessId,
        actorId: w.identity.ownerId,
        recordId: EntityId.random(),
        documentType: 'invoice',
        allocatedAt: DateTime.utc(2026, 1, 3),
      );
      expect(
        () => post(
          duplicate,
          requestId: EntityId.random(),
          number: reservedNumber,
        ),
        throwsStateError,
      );
      expect(await w.journals(), hasLength(1));
      final report = await w.report(
        from: DateTime.utc(2026),
        through: DateTime.utc(2026, 12, 31),
      );
      expect(report.assets, BigInt.from(10000));
      expect(report.revenue, BigInt.from(10000));
      expect(report.isBalanced, isTrue);
      await w.database.closeThrough(
        businessId: w.identity.businessId,
        date: DateTime.utc(2026, 1, 31),
        actorId: w.identity.ownerId,
        changedAt: DateTime.utc(2026, 2, 1),
        reason: 'Test close',
      );
      expect(
        () => post(duplicate, requestId: EntityId.random(), number: 'INV-002'),
        throwsStateError,
      );
      expect(await w.journals(), hasLength(1));
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(post(invoice), request);
      expect(await w.journals(), hasLength(1));
      expect(w.invoiceDrafts().single.invoice.id, duplicate.id);
      expect(w.postedInvoices().single.documentNumber, 'INV-001');
      expect(w.postedInvoices().single.customerSnapshot.id, c.id);
      final retained = w.postedInvoices().single.sourceDraft;
      expect(retained.reference, invoice.reference);
      expect(retained.memo, invoice.memo);
      expect(
        retained.attachments.single.originalSha256,
        invoice.attachments.single.originalSha256,
      );
      expect(
        retained.attachments.single.originalBytes,
        invoice.attachments.single.originalBytes,
      );

      w.dispose();
      final db = sqlite3.open(path);
      expect(
        () => db.execute('DELETE FROM invoice_postings'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => db.execute('UPDATE invoice_drafts SET revision=99'),
        throwsA(isA<SqliteException>()),
      );
      db.dispose();
    },
  );
}
