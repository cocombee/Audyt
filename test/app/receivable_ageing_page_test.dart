import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/accounting_test_finders.dart' show expectHeaderPrimaryAction;

import 'package:flutter/material.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/sales/receivable_ageing_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/domain/invoice.dart';

void main() {
  testWidgets('ageing report respects date and retains last valid report', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
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
    }
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

    post(invoice);
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: ReceivableAgeingPage(workspace: w),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Choose As Of'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-button-as-of')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('audyt-year-selector')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('audyt-date-close')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ageing-date')),
      '31-12-2025',
    );
    await tester.tap(find.byKey(const ValueKey('run-ageing')));
    await tester.pumpAndSettle();
    expect(
      find.text('No outstanding posted invoices for this date.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('ageing-date')),
      '01-02-2026',
    );
    await tester.tap(find.byKey(const ValueKey('run-ageing')));
    await tester.pumpAndSettle();
    expect(find.text('Total Outstanding'), findsOneWidget);
    expect(find.text('1–30 Days'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('RM 100.00'), findsWidgets);
    final summaryAxis = tester.getRect(find.text('As of 01-02-2026')).left;
    expect(tester.getRect(find.text('Current')).left, summaryAxis);
    expect(tester.getRect(find.text('Total Outstanding')).left, summaryAxis);
    expect(find.text('Ageing bucket'), findsOneWidget);
    expect(find.text('Outstanding'), findsOneWidget);
    await captureUi(tester, 'Ageing Wide');
    for (final width in [720.0, 1224.0]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpAndSettle();
      expectHeaderPrimaryAction(tester, 'run-ageing');
      await captureUi(
        tester,
        'Receivables Ageing Title Action ${width.toInt()}',
      );
    }
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureUi(tester, 'Ageing Narrow');
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ageing-date')),
      'invalid',
    );
    await tester.tap(find.byKey(const ValueKey('run-ageing')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid date.'), findsOneWidget);
    expect(find.text('As of 01-02-2026'), findsOneWidget);
    expect(find.text('Total Outstanding'), findsOneWidget);
    expect(find.byKey(const ValueKey('ageing-error-notice')), findsOneWidget);
    for (final width in [720.0, 1224.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('ageing-error-notice')),
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Ageing Invalid Date ${width.toInt()}');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    w.dispose();
  });
}
