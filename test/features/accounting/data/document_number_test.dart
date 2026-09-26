import 'package:sqlite3/sqlite3.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/core/money/money.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';

void main() {
  test(
    'numbers retain identity across reopen and independent connections',
    () async {
      final dir = Directory.systemTemp.createTempSync('document-numbers-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/books.sqlite';
      var w = await AccountingWorkspace.open(path);
      String allocate(
        EntityId id, {
        String type = 'invoice',
        EntityId? actor,
      }) => w.database.allocateDocumentNumber(
        businessId: w.identity.businessId,
        actorId: actor ?? w.identity.ownerId,
        recordId: id,
        documentType: type,
        allocatedAt: DateTime.utc(2026, 9, 14),
      );
      final id = EntityId.random();
      expect(allocate(id), 'INV-000001');
      expect(allocate(id), 'INV-000001');
      expect(allocate(EntityId.random(), type: 'claim'), 'CL-000001');
      expect(
        () => allocate(EntityId.random(), actor: EntityId.random()),
        throwsStateError,
      );
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(allocate(id), 'INV-000001');
      final other = await AccountingWorkspace.open(path);
      expect(
        other.database.allocateDocumentNumber(
          businessId: other.identity.businessId,
          actorId: other.identity.ownerId,
          recordId: EntityId.random(),
          documentType: 'invoice',
          allocatedAt: DateTime.utc(2026, 9, 14),
        ),
        'INV-000002',
      );
      expect(allocate(EntityId.random()), 'INV-000003');
      final customer = Customer.create(
        metadata: RecordMetadata.initial(
          recordId: EntityId.random(),
          businessId: w.identity.businessId,
          originDeviceId: w.identity.deviceId,
          createdAt: DateTime.utc(2026, 9, 14),
        ),
        displayName: 'Numbering Customer',
        contact: const CustomerContact(),
        taxProfile: const CustomerTaxProfile(),
        currency: Currency.parse('MYR'),
        paymentTerms: PaymentTerms.netDays(30),
      );
      w.saveCustomer(customer);
      expect(
        () => w.saveInvoiceDraft(
          Invoice.draft(
            id: EntityId.random(),
            customerId: customer.id,
            total: Money.fromMinor(100, 'MYR'),
            issueDate: DateTime.utc(2026, 9, 14),
            documentNumber: 'INV-000001',
          ),
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 14),
        ),
        throwsStateError,
      );
      expect(w.invoiceDrafts(), isEmpty);

      w.saveInvoiceDraft(
        Invoice.draft(
          id: EntityId.random(),
          customerId: customer.id,
          total: Money.fromMinor(100, 'MYR'),
          issueDate: DateTime.utc(2026, 9, 14),
          documentNumber: 'INV-000004',
        ),
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 9, 14),
      );
      expect(allocate(EntityId.random()), 'INV-000005');

      final raw = sqlite3.open(path);
      expect(
        () => raw.execute("UPDATE document_numbers SET number='changed'"),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => raw.execute('DELETE FROM document_numbers'),
        throwsA(isA<SqliteException>()),
      );
      final retainedCount = raw
          .select('SELECT COUNT(*) AS n FROM document_numbers')
          .single['n'];
      expect(retainedCount, 5);
      expect(
        () => w.database.allocateDocumentNumber(
          businessId: EntityId.random(),
          actorId: w.identity.ownerId,
          recordId: EntityId.random(),
          documentType: 'invoice',
          allocatedAt: DateTime.utc(2026, 9, 14),
        ),
        throwsStateError,
      );
      expect(
        raw.select('SELECT COUNT(*) AS n FROM document_numbers').single['n'],
        retainedCount,
      );
      raw.dispose();
      other.dispose();
      w.dispose();
    },
  );
}
