import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/app/accounting_description_field.dart';

import '../support/accounting_text_input.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/asset_purchase_fields.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/naming_setup.dart' show namingSettingsChannel;
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/purchases/domain/vendor.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/purchases/presentation/bill_form.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../features/accounting/data/bill_posting_test.dart' show payableAccount;
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AccountingRecordPageSizes.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null);
  });
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'restored Bills page saves, revises and posts exact purchases with actual Settings at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = Directory.systemTemp.createTempSync('audyt-bills-ui-');
        addTearDown(() => root.deleteSync(recursive: true));
        final source = await AccountingWorkspace.open(
          '${root.path}/source.sqlite',
        );
        final (vendor, account) = await setupBill(source);
        final payable = await payableAccount(source);
        final legacy = billFixture(
          source,
          vendor,
          account.account.id,
          at: DateTime.utc(2026, 9, 1),
          attachments: const [],
        );
        source.saveBillDraft(legacy, expectedRevision: 0);
        final beforeRestore = tables(source);
        final archive = source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.now(),
        );
        source.dispose();
        final sourceHash = sha256
            .convert(File('${root.path}/source.sqlite').readAsBytesSync())
            .toString();
        var w = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          archive,
        );
        w.dispose();
        w = await AccountingWorkspace.open('${root.path}/restored.sqlite');
        addTearDown(() => w.dispose());
        expect(tables(w), beforeRestore);
        await w.createAccount(
          code: '2299',
          name: 'Fictional Tax Payable',
          type: AccountType.liability,
        );
        final taxAccount = (await w.accounts())
            .singleWhere((a) => a.account.code == '2299')
            .account;
        w.saveTaxRate(
          CompanyTaxRate(
            id: EntityId.random(),
            name: 'Service Tax',
            percent: '6',
            effectiveFrom: DateTime(2026, 1, 1),
            application: TaxApplication.purchases,
            accountId: taxAccount.id,
          ),
        );

        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: w, initialPath: '/expenses-vendors'),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        Future<void> text(String label, String value) async {
          final f = find.byKey(ValueKey('design-field-$label'));
          await tester.ensureVisible(f);
          await enterAccountingText(tester, f, value);
          await tester.pumpAndSettle();
        }

        Future<void> choice(String label, String value) async {
          await tap(find.byKey(ValueKey('design-field-$label')));
          await tap(find.widgetWithText(MenuItemButton, value).last);
        }

        Future<void> close() => tap(accountingCloseIcon().last);
        Future<void> closeBillForm({bool discard = false}) async {
          await tap(find.byKey(const ValueKey('design-close')));
          final warning = find.byKey(const ValueKey('design-discard-changes'));
          expect(warning, discard ? findsOneWidget : findsNothing);
          if (discard) await tap(warning);
          expect(find.byType(FrontendFormDialog), findsNothing);
        }

        Future<void> line(String label, String value) async {
          final f = find.byWidgetPredicate(
            (widget) =>
                (widget is TextFormField ||
                    widget is AccountingDescriptionField) &&
                widget.key is ValueKey &&
                (widget.key as ValueKey).value.toString().endsWith('-$label'),
          );
          await tester.ensureVisible(f);
          await enterAccountingText(tester, f, value);
          await tester.pumpAndSettle();
        }

        Future<void> tab(String label) async {
          final tabs = tester.widget<AccountingTabs>(
            find.byKey(const ValueKey('area-tabs-expenses-vendors')),
          );
          await tap(
            find.byKey(
              ValueKey(
                'preview-tab-expenses-vendors-${tabs.labels.indexOf(label)}',
              ),
            ),
          );
        }

        await tab('Bills');
        expect(find.byType(BillsPage), findsOneWidget);
        final view = find.byKey(ValueKey('view-bill-${legacy.id}'));
        expect(tester.widget(view), isA<IconButton>());
        expect(tester.getSize(view), const Size(32, 32));
        await captureUi(tester, 'Bill Records ${width.toInt()}');
        var before = tables(w);
        await tap(view);
        expect(find.byType(AccountingInformationRows), findsWidgets);
        expect(find.text('Per Line (Legacy)'), findsOneWidget);
        await captureUi(tester, 'Bill Saved Facts ${width.toInt()}');
        await close();
        expect(tables(w), before);
        await tap(find.byKey(ValueKey('edit-bill-${legacy.id}')));
        expect(find.byType(AssetPurchaseFields), findsNothing);
        expect(
          find.byKey(const ValueKey('design-field-Location')),
          findsOneWidget,
        );
        await text('Memo', 'Cancelled Bill edit');
        await closeBillForm(discard: true);
        expect(tables(w), before);

        // Cancel may leave a reserved number, but never a saved bill or journal.
        await tap(find.byKey(const ValueKey('new-bill')));
        before = tables(w);
        await closeBillForm();
        expect(tables(w), before);
        expect(await w.journals(), isEmpty);
        Future<void> create({bool foreign = false}) async {
          await tap(find.byKey(const ValueKey('new-bill')));
          expect(find.byType(AssetPurchaseFields), findsNothing);
          expect(
            find.byKey(const ValueKey('design-field-Location')),
            findsNothing,
          );
          // The approved basic grid omits optional fields until enabled through
          // the actual company Settings shortcut. Exercise the advanced path.
          await tap(
            find.byKey(const ValueKey('transaction-settings-shortcut')),
          );
          await tap(find.text('Purchase Preferences').last);
          for (final label in ['Show Rate', 'Enable Discounts', 'Show Class']) {
            final toggle = find.byKey(ValueKey('design-field-$label'));
            if (!tester.widget<AccountingSwitchListTile>(toggle).value) {
              await tap(toggle);
            }
          }
          await tap(find.byKey(const ValueKey('design-save-settings')).last);
          await close();
          await choice('Counterparty', vendor.name);
          await text('Date', '01-09-2026');
          if (!foreign) {
            await choice('Currency', 'RM');
            await choice('Payment Terms', 'Net 30');
          }
          await choice('Tax Mode', 'Tax Exclusive');
          await text('Reference', foreign ? 'SUP-FX-UI' : 'SUP-MYR-UI');
          await text('Class', 'Fictional Procurement');
          await text('Memo', 'Saved UI purchase');
          await line('Description', 'Fictional supplied materials');
          await line('Quantity', '3');
          await line('Rate', '50');
          await line('Discount', '5');
          final taxSelector = find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.triggerKey is ValueKey &&
                (widget.triggerKey as ValueKey).value.toString().endsWith(
                  '-Tax Rate (%)',
                ),
          );
          await tap(taxSelector);
          await tap(
            find.widgetWithText(MenuItemButton, 'Service Tax · 6%').last,
          );
          final selector = find.byWidgetPredicate(
            (widget) =>
                widget is AccountingSelector<String> &&
                widget.triggerKey is ValueKey &&
                (widget.triggerKey as ValueKey).value.toString().endsWith(
                  '-Account',
                ),
          );
          await tap(selector);
          await tap(
            find.widgetWithText(MenuItemButton, 'Fictional Purchase').last,
          );
          await captureUi(
            tester,
            'Bill Editor ${foreign ? 'Foreign' : 'MYR'} ${width.toInt()}',
          );
          await tap(find.byKey(const ValueKey('design-review')));
          expect(
            find.text(foreign ? '30-09-2026' : '01-10-2026'),
            findsOneWidget,
          );
          expect(find.text(foreign ? r'S$153.70' : 'RM 153.70'), findsWidgets);
          expect(find.text('Fictional supplied materials'), findsOneWidget);
          await captureUi(
            tester,
            'Bill Save Review ${foreign ? 'Foreign' : 'MYR'} ${width.toInt()}',
          );
          await tap(find.byKey(const ValueKey('design-review')));
          expect(find.byType(FrontendFormDialog), findsNothing);
        }

        await create(foreign: true);
        final foreign = w.database
            .billDraftPage(businessId: w.identity.businessId, posted: null)
            .records
            .singleWhere((b) => b.supplierReference == 'SUP-FX-UI');
        expect(foreign.total.currency, 'SGD');
        expect(foreign.total.minorUnits, 15370);
        expect(foreign.bill.dueDate, DateTime.utc(2026, 9, 30));
        expect(foreign.bill.terms.dayOfMonth, 31);
        await create();
        final bill = w.database
            .billDraftPage(businessId: w.identity.businessId, posted: null)
            .records
            .singleWhere((b) => b.supplierReference == 'SUP-MYR-UI');
        expect(bill.total.currency, 'MYR');
        expect(bill.total.minorUnits, 15370);
        expect(bill.taxMode, 'Exclusive');
        expect(bill.bill.dueDate, DateTime.utc(2026, 10, 1));
        expect(bill.vendorSnapshot.payeeId, 'legacy-supplier-string');
        expect(await w.journals(), isEmpty);

        // Save the actual Payables setting, then consume it in Post Bill.
        await tap(find.byKey(const ValueKey('accounting-settings')));
        await tap(find.text('Default Accounts').last);
        await choice('Payables Account', '2100 · Fictional Payables');
        await captureUi(
          tester,
          'Bill Payables Setting Selected ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('design-save-settings')));
        expect(
          w.preferences.text('Default Accounts', 'Payables Account'),
          payable.account.id.value,
        );
        await captureUi(tester, 'Bill Payables Setting ${width.toInt()}');
        await close();
        await tap(find.byKey(ValueKey('edit-bill-${bill.id}')));
        await text('Memo', 'Revised UI purchase');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        final revised = w.database.readBillDraft(
          w.identity.businessId,
          bill.id,
        )!;
        expect(revised.metadata.revision, 2);
        expect(revised.lines.single.id, bill.lines.single.id);
        expect(revised.taxMode, 'Exclusive');

        // Master edits cannot rewrite the saved supplier/terms/currency snapshot.
        final renamed = Vendor(
          metadata: vendor.metadata.nextRevision(
            updatedAt: DateTime.now().toUtc(),
          ),
          payeeId: vendor.payeeId,
          name: 'Renamed Vendor',
          type: vendor.type,
          details: vendor.details,
          currency: Currency.parse('MYR'),
          terms: PaymentTerms.netDays(7),
        );
        w.saveVendor(renamed, expectedRevision: vendor.metadata.revision);
        await tap(find.byKey(ValueKey('edit-bill-${foreign.id}')));
        await text('Memo', 'Retain foreign supplier snapshot');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        final retained = w.database.readBillDraft(
          w.identity.businessId,
          foreign.id,
        )!;
        expect(retained.vendorSnapshot.toJson(), vendor.toJson());
        expect(retained.total.currency, 'SGD');
        expect(retained.bill.terms.toJson(), vendor.terms.toJson());

        Future<void> postDialog(dynamic id) async {
          await tap(find.byKey(ValueKey('bill-more-$id')));
          await tap(find.byKey(ValueKey('post-bill-$id')));
        }

        before = tables(w);
        await postDialog(foreign.id);
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        expect(tables(w), before);
        await captureUi(
          tester,
          'Bill Foreign Posting Rejected ${width.toInt()}',
        );
        await closeBillForm();
        before = tables(w);
        await postDialog(bill.id);
        await closeBillForm();
        expect(tables(w), before);

        // A concurrent saved revision invalidates the exact revision shown in
        // an open posting review. The losing UI command must change no table.
        await postDialog(bill.id);
        w.saveBillDraft(
          billFromForm(
            billFormValues(revised),
            metadata: revised.metadata.nextRevision(
              updatedAt: DateTime.now().toUtc(),
            ),
            vendor: revised.vendorSnapshot,
            purchaseAccountIds: {account.account.id.value},
            taxCodes: w.taxRates,
            existing: revised,
          ),
          expectedRevision: revised.metadata.revision,
        );
        before = tables(w);
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        expect(find.textContaining('reviewed bill changed'), findsOneWidget);
        expect(tables(w), before);
        await captureUi(tester, 'Bill Stale Posting Rejected ${width.toInt()}');
        await closeBillForm();

        await postDialog(bill.id);
        await captureUi(tester, 'Bill Posting Review ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(find.byKey(ValueKey('edit-bill-${bill.id}')), findsNothing);
        final posting = w.database.readBillPosting(
          w.identity.businessId,
          bill.id,
        )!;
        expect(posting.payableAccountId, payable.account.id);
        expect(posting.source.metadata.revision, 3);
        expect((await w.journals()).length, 1);
        final report = await w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(report.expenses, BigInt.from(15370));
        expect(report.periodProfit, BigInt.from(-15370));
        expect(report.liabilities, BigInt.from(15370));
        expect(report.assets, BigInt.zero);
        expect(report.isBalanced, isTrue);
        await captureUi(tester, 'Bill Posted Records ${width.toInt()}');
        before = tables(w);
        // The posted Bill has correction and history actions.
        await tap(find.byKey(ValueKey('bill-more-${bill.id}')));
        await tap(find.byKey(ValueKey('bill-history-${bill.id}')));
        await captureUi(tester, 'Bill History ${width.toInt()}');
        await tap(find.byKey(ValueKey('view-bill-revision-${bill.id}-1')));
        expect(find.text('Saved UI purchase'), findsOneWidget);
        await close();
        await close();
        expect(tables(w), before);
        expect(find.byKey(const ValueKey('bill-search')), findsNothing);
        expect(find.byKey(const ValueKey('bill-status-filter')), findsNothing);
        expect(find.byType(AccountingRecordPagination), findsNothing);
        expect(tables(w), before);

        // Reach every saved row through the real SQL-backed page controls.
        // More unposted drafts must not change the recognized purchase.
        for (var i = 0; i < 12; i++) {
          w.saveBillDraft(
            billFixture(
              w,
              renamed,
              account.account.id,
              memo: 'Fictional bounded page $i',
              at: DateTime.now().toUtc(),
              attachments: const [],
            ),
            expectedRevision: 0,
          );
        }
        await tester.pumpAndSettle();
        before = tables(w);
        void expectPage(int offset, int limit) {
          final page = w.database.billDraftPage(
            businessId: w.identity.businessId,
            posted: null,
            offset: offset,
            limit: limit,
          );
          expect(page.total, 15);
          for (final row in page.records) {
            expect(find.byKey(ValueKey('bill-row-${row.id}')), findsOneWidget);
          }
          expect(
            find.byType(AccountingRecordRow),
            findsNWidgets(page.records.length),
          );
        }

        expectPage(0, 5);
        await tap(find.byKey(const ValueKey('bill-page-next')));
        expectPage(5, 5);
        await tap(find.byKey(const ValueKey('bill-page-previous')));
        expectPage(0, 5);
        await tap(find.byKey(const ValueKey('bill-page-size')));
        await tap(find.widgetWithText(MenuItemButton, '20').last);
        expectPage(0, 20);
        expect(tables(w), before);
        expect((await w.journals()).length, 1);
        await tap(find.byKey(ValueKey('bill-more-${bill.id}')));
        await tap(find.byKey(ValueKey('reverse-bill-${bill.id}')));
        await closeBillForm();
        expect(tables(w), before);
        await tap(find.byKey(ValueKey('bill-more-${bill.id}')));
        await tap(find.byKey(ValueKey('reverse-bill-${bill.id}')));
        await text('Reason', 'Duplicated supplier Bill');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.text('Duplicated supplier Bill'), findsWidgets);
        await captureUi(tester, 'Bill Reversal Review ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(
          w.database.readBillReversal(w.identity.businessId, bill.id)?.reason,
          'Duplicated supplier Bill',
        );
        expect((await w.journals()).length, 2);
        await captureUi(tester, 'Bill Reversed Records ${width.toInt()}');
        await tap(find.byKey(ValueKey('view-bill-${bill.id}')));
        expect(find.text('Reversed'), findsWidgets);
        expect(find.text('Duplicated supplier Bill'), findsOneWidget);
        await close();
        await tap(find.byKey(const ValueKey('bill-status-filter')));
        await tap(find.widgetWithText(MenuItemButton, 'Reversed').last);
        expect(find.byKey(ValueKey('bill-row-${bill.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('bill-row-${foreign.id}')), findsNothing);
        await tap(find.byKey(const ValueKey('clear-bill-filter')));
        final finalTables = tables(w);
        final finalArchive = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.now(),
        );
        await tester.pumpWidget(const SizedBox());
        w.dispose();
        w = await AccountingWorkspace.open('${root.path}/restored.sqlite');
        expect(tables(w), finalTables);
        expect(
          w.database.readBillDraft(w.identity.businessId, bill.id)!.taxMode,
          'Exclusive',
        );
        final copy = await AccountingWorkspace.emptyRestore(
          '${root.path}/copy.sqlite',
          finalArchive,
        );
        expect(tables(copy), finalTables);
        expect(
          copy.database
              .readBillPosting(copy.identity.businessId, bill.id)!
              .journalId,
          posting.journalId,
        );
        copy.dispose();
        expect(
          sha256
              .convert(File('${root.path}/source.sqlite').readAsBytesSync())
              .toString(),
          sourceHash,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
