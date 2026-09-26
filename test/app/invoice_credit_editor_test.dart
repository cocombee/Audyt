import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';

import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'dart:io';

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

import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/sales/invoice_credit_editor.dart';
import 'package:audyt/features/sales/invoice_credit_page.dart';

void main() {
  testWidgets('credit editor rejects excess and saves a restorable revision', (
    tester,
  ) async {
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
    final ar = accounts.firstWhere((a) => a.account.code == '1100').account.id;
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

    await (FontLoader('Arial')..addFont(
          Future.value(
            ByteData.sublistView(
              File('/System/Library/Fonts/Supplemental/Arial.ttf')
                  .readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (context) => InvoiceCreditEditor(
                    workspace: w,
                    invoice: invoice,
                    attachmentPicker: (_) async {
                      return [
                        PickedExpenseAttachment(
                          name: 'credit-evidence.png',
                          mimeType: 'image/png',
                          bytes: Uint8List.fromList(
                            img.encodePng(img.Image(width: 100, height: 100)),
                          ),
                        ),
                      ];
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final creditLabel = tester.getRect(
      find.byKey(const ValueKey('credit-date-label')),
    );
    final creditField = tester.getRect(
      find.byKey(const ValueKey('credit-date')),
    );
    expect(creditField.top - creditLabel.bottom, closeTo(8, 0.1));
    expect(find.text('Credit Date'), findsOneWidget);
    final reasonField = find.byKey(const ValueKey('credit-reason'));
    expect(tester.getRect(reasonField).top, closeTo(creditField.top, .1));
    expect(creditLabel.left, closeTo(creditField.left, .1));
    expect(find.text('Amount (RM)'), findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.decoration?.prefixText, isNull);
      expect(field.decoration?.labelText, isNull);
    }
    final amountField = find.byKey(
      ValueKey('credit-amount-${invoice.lines.last.id}'),
    );
    final initialAmountWidth = tester.getSize(amountField).width;
    await tester.enterText(amountField, '1234567890123.00');
    await tester.pumpAndSettle();
    expect(tester.getSize(amountField).width, greaterThan(initialAmountWidth));
    await tester.enterText(amountField, '');
    await tester.pumpAndSettle();
    expect(tester.getSize(amountField).width, closeTo(initialAmountWidth, .1));

    await tester.tap(find.byKey(const ValueKey('credit-attachments')));
    await tester.pumpAndSettle();
    await captureUi(tester, 'Credit Editor Wide');
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureUi(tester, 'Credit Editor Narrow');
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Returned work');
    await tester.enterText(find.byType(TextField).at(3), '999.00');
    await tester.tap(find.byKey(const ValueKey('save-credit')));
    await tester.pumpAndSettle();
    expect(w.creditDrafts(), isEmpty);
    await tester.enterText(find.byType(TextField).at(3), '35.00');
    await tester.tap(find.byKey(const ValueKey('save-credit')));
    await tester.pumpAndSettle();
    expect(find.byType(InvoiceCreditEditor), findsNothing);
    expect(w.creditDrafts().single.total.minorUnits, 3500);
    expect(w.creditDrafts().single.attachments, hasLength(1));
    expect(
      w.creditDrafts().single.attachments.single.status,
      AttachmentProcessingStatus.ready,
    );
    final attachmentHash = w
        .creditDrafts()
        .single
        .attachments
        .single
        .originalSha256;
    expect(await w.journals(), hasLength(1));
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('workspace-capture'),
        child: MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: InvoiceCreditPage(workspace: w)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('View'), findsNothing);
    expect(find.byTooltip('Edit'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    final savedAttachment = w.creditDrafts().single.attachments.single;
    final removeAttachment = find.byKey(
      ValueKey('remove-${savedAttachment.originalId}'),
    );
    await tester.ensureVisible(removeAttachment);
    await tester.pumpAndSettle();
    await tester.tap(removeAttachment);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('preview-${savedAttachment.originalId}')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('cancel-credit')));
    await tester.pumpAndSettle();
    expect(
      w.creditDrafts().single.attachments.single.originalSha256,
      attachmentHash,
    );
    expect(w.creditDrafts().single.revision, 1);
    final previous = w.creditDrafts().single;
    w.saveInvoiceCreditDraft(
      draftId: previous.id,
      invoiceId: previous.invoiceId,
      lineCredits: previous.lineCredits,
      reason: 'Updated reason',
      creditDate: previous.date,
      expectedRevision: 1,
      savedAt: DateTime.now(),
      attachments: previous.attachments,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('history-${previous.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Credit Draft History'), findsOneWidget);
    expect(find.text('Revision 1'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('credit-history-revision-1')),
        matching: find.text('RM 35.00'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('restore-credit-1')));
    await tester.pumpAndSettle();
    expect(w.creditDrafts().single.revision, 3);
    expect(w.creditDrafts().single.reason, 'Returned work');
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    w.dispose();
    w = await AccountingWorkspace.open(path);
    expect(w.creditDrafts().single.reason, 'Returned work');
    expect(
      w.creditDrafts().single.attachments.single.originalSha256,
      attachmentHash,
    );
    w.dispose();
  });
}
