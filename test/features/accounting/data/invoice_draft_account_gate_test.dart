import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final change in [
    'locked',
    'archived',
    'parent',
    'wrong type',
    'missing',
  ]) {
    test('draft save atomically rejects a $change income reference', () async {
      final root = Directory.systemTemp.createTempSync('audyt-draft-account-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      addTearDown(() => workspace.dispose());
      await workspace.createAccount(
        code: '4100',
        name: 'Saved Income',
        type: AccountType.income,
      );
      final stored = (await workspace.accounts()).single;
      final customer = Customer.create(
        metadata: RecordMetadata.initial(
          recordId: EntityId.random(),
          businessId: workspace.identity.businessId,
          originDeviceId: workspace.identity.deviceId,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        displayName: 'Saved Customer',
        contact: const CustomerContact(),
        taxProfile: const CustomerTaxProfile(),
        currency: Currency.parse('MYR'),
        paymentTerms: PaymentTerms.netDays(30),
      );
      workspace.saveCustomer(customer);
      final id = EntityId.random(), lineId = EntityId.random();
      Invoice draft({String memo = '', EntityId? accountId}) => Invoice.draft(
        id: id,
        customerId: customer.id,
        documentNumber: 'INV-CURRENT-MASTERS',
        issueDate: DateTime.utc(2026, 1, 1),
        terms: customer.paymentTerms,
        memo: memo,
        taxMode: 'Exclusive',
        classification: 'Retained Class',
        location: 'Retained Branch',
        lines: [
          SalesLineItem.category(
            id: lineId,
            categoryId: accountId ?? stored.account.id,
            description: 'Saved service',
            quantity: SalesQuantity.fromInt(1),
            rate: Money.fromMinor(9000, 'MYR'),
          ),
        ],
      );
      final saved = draft();
      workspace.saveInvoiceDraft(
        saved,
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 1, 2),
      );
      if (change != 'missing') {
        await workspace.database.saveAccount(
          StoredAccount(
            account: Account.create(
              id: stored.account.id,
              code: stored.account.code,
              name: stored.account.name,
              type: change == 'wrong type'
                  ? AccountType.expense
                  : AccountType.income,
              isParent: change == 'parent',
              status: change == 'locked'
                  ? AccountStatus.locked
                  : change == 'archived'
                  ? AccountStatus.archived
                  : AccountStatus.active,
            ),
            metadata: stored.metadata.nextRevision(
              updatedAt: stored.metadata.updatedAt.add(
                const Duration(seconds: 1),
              ),
            ),
          ),
        );
      }
      Map<String, dynamic> tables() {
        final envelope = jsonDecode(
          workspace.database.exportDataArchive(
            workspace.identity.businessId,
            DateTime.utc(2026, 9, 27),
          ),
        ) as Map<String, dynamic>;
        return (jsonDecode(envelope['data'] as String)
                as Map<String, dynamic>)['tables']
            as Map<String, dynamic>;
      }

      final before = tables();
      final stale = draft(
        memo: 'Attempt after master changed',
        accountId: change == 'missing' ? EntityId.random() : null,
      );
      expect(
        () => workspace.saveInvoiceDraft(
          stale,
          expectedRevision: 1,
          savedAt: DateTime.utc(2026, 1, 3),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('active income account'),
          ),
        ),
      );
      expect(tables(), before);
      expect(workspace.invoiceDrafts().single.revision, 1);
      expect(
        workspace.invoiceDrafts().single.invoice.draftSnapshot(),
        saved.draftSnapshot(),
      );
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(tables(), before);
      expect(
        workspace.invoiceDrafts().single.invoice.draftSnapshot(),
        saved.draftSnapshot(),
      );
    });
  }
}
