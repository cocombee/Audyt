import '../support/accounting_text_input.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/core/money/currency_presentation.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/purchases/presentation/vendors_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../features/accounting/data/vendor_persistence_test.dart'
    show vendorFixture;

void assertSidewaysDetails(WidgetTester tester) {
  final facts = find.byType(AccountingInformationRows);
  final rows = tester.widget<AccountingInformationRows>(facts).rows;
  final texts = find.descendant(of: facts, matching: find.byType(Text));
  expect(texts, findsNWidgets(rows.length * 3));
  final colonLeft = tester.getRect(texts.at(1)).left;
  final valueLeft = tester.getRect(texts.at(2)).left;
  for (var index = 0; index < rows.length; index++) {
    final labelStyle = tester.widget<Text>(texts.at(index * 3)).style!;
    final colonStyle = tester.widget<Text>(texts.at(index * 3 + 1)).style!;
    final valueStyle = tester.widget<Text>(texts.at(index * 3 + 2)).style!;
    final regular = AccountingTypography.value(tester.element(facts));
    final emphasized = AccountingTypography.sidewaysDetailsLabel(
      tester.element(facts),
    );
    expect(labelStyle, emphasized);
    expect(colonStyle, regular);
    expect(valueStyle, regular);
    expect(labelStyle.fontFamily, valueStyle.fontFamily);
    expect(labelStyle.fontSize, valueStyle.fontSize);
    expect(
      labelStyle.fontWeight,
      AccountingTypography.tableHeader(tester.element(facts)).fontWeight,
    );
    expect(valueStyle.fontWeight, FontWeight.w400);
    final label = tester.getRect(texts.at(index * 3));
    final colon = tester.getRect(texts.at(index * 3 + 1));
    final value = tester.getRect(texts.at(index * 3 + 2));
    expect(tester.widget<Text>(texts.at(index * 3 + 1)).data, ':');
    expect(colon.left, closeTo(colonLeft, .01));
    expect(value.left, closeTo(valueLeft, .01));
    expect(
      colon.left - label.right,
      closeTo(AccountingSidewaysDetailsTokens.columnGap, .01),
    );
    expect(
      value.left - colon.right,
      closeTo(AccountingSidewaysDetailsTokens.columnGap, .01),
    );
    expect(
      tester.widget<Text>(texts.at(index * 3 + 2)).textAlign,
      TextAlign.left,
    );
  }
}

void main() {
  testWidgets(
    'supplier View and revision resolve saved accounts without changing facts',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final root = Directory.systemTemp.createTempSync('audyt-vendor-facts-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/source.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      addTearDown(() => workspace.dispose());
      await workspace.createAccount(
        code: '5000',
        name: 'Fictional Services',
        type: AccountType.expense,
      );
      final stored = (await workspace.accounts()).single;
      final account = stored.account;
      final first = vendorFixture(
        workspace,
        additionalValues: {'defaultExpenseAccountId': account.id.value},
      );
      workspace.saveVendor(first, expectedRevision: 0);

      Future<void> mount() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: workspace,
              initialPath: '/expenses-vendors',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tabs = tester.widget<AccountingTabs>(find.byType(AccountingTabs));
        await tester.tap(
          find.byKey(
            ValueKey(
              'preview-tab-expenses-vendors-${tabs.labels.indexOf('Vendors')}',
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder.last);
        await tester.tap(finder.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      void expectDefault(String label) {
        final rows = tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows;
        expect(rows, contains(('Default Expense Category', label)));
      }

      await mount();
      final before = tables(workspace);
      await tap(find.byKey(ValueKey('view-vendor-${first.payeeId}')));
      expectDefault(account.displayName);
      assertSidewaysDetails(tester);
      await tester.ensureVisible(find.text('Default Expense Category'));
      await tester.pumpAndSettle();
      await captureUi(tester, 'Vendor Default Expense Account Facts 1224');
      expect(tables(workspace), before);
      await tap(accountingCloseIcon().last);
      await workspace.database.saveAccount(
        StoredAccount(
          account: Account.create(
            id: account.id,
            code: account.code,
            name: account.name,
            type: account.type,
            status: AccountStatus.archived,
          ),
          metadata: stored.metadata.nextRevision(
            updatedAt: stored.metadata.updatedAt.add(
              const Duration(seconds: 1),
            ),
          ),
        ),
      );
      final second = vendorFixture(
        workspace,
        original: first,
        additionalValues: {'companyName': 'Fictional Company'},
      );
      workspace.saveVendor(second, expectedRevision: 1);
      await tester.pumpAndSettle();
      await tap(find.byKey(ValueKey('history-vendor-${first.payeeId}')));
      await tap(find.byKey(const ValueKey('vendor-history-view-1')));
      expectDefault(account.displayName);
      await tester.ensureVisible(find.text('Default Expense Category'));
      await tester.pumpAndSettle();
      await captureUi(tester, 'Vendor Archived Expense Account Revision 1224');
      expect(
        workspace.database
            .vendorHistory(workspace.identity.businessId, first.id)
            .first
            .additionalValues['defaultExpenseAccountId'],
        account.id.value,
      );
      await tap(accountingCloseIcon().last);
      await tap(accountingCloseIcon().last);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      // Isolated restored-record fixture: retain the historical supplier ID even
      // when its referenced account is no longer available in the catalogue.
      final database = sqlite3.open(path);
      database.execute('DELETE FROM accounts WHERE id=?', [account.id.value]);
      database.dispose();
      workspace = await AccountingWorkspace.open(path);
      await mount();
      final missingBefore = tables(workspace);
      await tap(find.byKey(ValueKey('history-vendor-${first.payeeId}')));
      await tap(find.byKey(const ValueKey('vendor-history-view-1')));
      expectDefault('Unavailable Saved Expense Account (${account.id.value})');
      await tester.ensureVisible(find.text('Default Expense Category'));
      await tester.pumpAndSettle();
      await captureUi(tester, 'Vendor Missing Expense Account Revision 1224');
      expect(tables(workspace), missingBefore);
      expect(await workspace.journals(), isEmpty);
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'restored Vendors create, review, edit, history and paging at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final root = Directory.systemTemp.createTempSync('audyt-vendor-ui-');
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/source.sqlite';
        final source = await AccountingWorkspace.open(path);
        for (var i = 0; i < 23; i++) {
          source.payees.add(
            id: 'old-supplier-$i',
            name: 'Old Supplier ${i.toString().padLeft(2, '0')}',
            type: PayeeType.supplier,
          );
        }
        source.payees.add(
          id: 'worker',
          name: 'Fictional worker',
          type: PayeeType.staff,
        );
        final before = tables(source);
        final archive = source.database.exportDataArchive(
          source.identity.businessId,
          DateTime.now(),
        );
        source.dispose();
        final sourceHash = sha256
            .convert(File(path).readAsBytesSync())
            .toString();
        var workspace = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          archive,
        );
        workspace.dispose();
        workspace = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        addTearDown(() => workspace.dispose());
        expect(tables(workspace), before);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: workspace,
              initialPath: '/expenses-vendors',
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder.last);
          await tester.tap(finder.last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        Future<void> tapAndEnter(Finder finder, String value) async {
          await tester.ensureVisible(finder);
          await enterAccountingText(tester, finder, value);
          await tester.pumpAndSettle();
        }

        Future<void> text(String label, String value) async =>
            tapAndEnter(find.byKey(ValueKey('design-field-$label')), value);
        Future<void> choice(String label, String value) async {
          await tap(find.byKey(ValueKey('design-field-$label')));
          await tap(
            find.widgetWithText(
              MenuItemButton,
              label.contains('Currency')
                  ? CurrencyPresentation.fromCode(value).label
                  : value,
            ),
          );
        }

        Future<void> close() async => tap(accountingCloseIcon().last);
        // Use the production connected tab, not a standalone page harness.
        final tabs = tester.widget<AccountingTabs>(find.byType(AccountingTabs));
        await tap(
          find.byKey(
            ValueKey(
              'preview-tab-expenses-vendors-${tabs.labels.indexOf('Vendors')}',
            ),
          ),
        );
        expect(find.byType(VendorsPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vendor-row-old-supplier-0')),
          findsOneWidget,
        );
        expect(find.text('Fictional worker'), findsNothing);
        await captureUi(tester, 'Vendor Records ${width.toInt()}');
        await tap(find.byKey(const ValueKey('new-vendor')));
        await text('Name', 'Cancelled contact');
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-keep-editing')));
        expect(find.text('Cancelled contact'), findsWidgets);
        expect(tables(workspace), before);
        await tap(find.byKey(const ValueKey('design-close')));
        await tap(find.byKey(const ValueKey('design-discard-changes')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tables(workspace), before);
        await tap(find.byKey(const ValueKey('new-vendor')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        expect(tables(workspace), before);
        await text('Name', 'Fictional Vendor');
        await text('Company Name', 'Fictional Vendor Company');
        await text('Mobile Number', '+60 000 222');
        await text('Account Number', '0007 AB');
        await choice('Supplier Category', 'Foreign Business');
        await text('Billing Rate Per Hour', '125.50');
        await choice('Vendor Type', 'Small Provider');
        await choice('Party Type', 'Business');
        await text('Email', 'contact@example.invalid');
        await text('Telephone', '+60 000 111');
        await text('Address Line 1', 'Fictional address one');
        await text('Address Line 2', 'Unit 002');
        await text('City', 'Fictional City');
        await text('Postcode', '00123 AB');
        await choice('Country', 'Other Country');
        await text('State / Region', 'Fictional Region');
        await text('Country Name', 'Fictional Country');
        await text('Country ISO Code', 'zz');
        await choice('Preferred Billing Currency', 'SGD');
        expect(find.text('Billing Rate Per Hour (S\$)'), findsOneWidget);
        expect(find.text('Opening Balance (S\$)'), findsOneWidget);
        await choice('Payment Terms', 'Day Of Month');
        await choice('Monthly Due Day', '31');
        await text('Rollover Within Days', '5');
        await tap(
          find.descendant(
            of: find.byKey(const ValueKey('design-field-Tax Details Needed')),
            matching: find.byType(Switch),
          ),
        );
        await choice('Identification Type', 'Business Registration');
        await text('Identification Number', 'FICT-ID');
        await text('TIN', 'FICT-TIN');
        await text('SST Registration Number', 'FICT-SST');
        await text('Notes', 'Fictional contact notes');
        await tester.ensureVisible(
          find.byKey(const ValueKey('design-field-Payment Terms')),
        );
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Vendor Current Accounting Fields ${width.toInt()}',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('design-field-Notes')),
        );
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Vendor Current Supporting Documents ${width.toInt()}',
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('design-field-Name')),
        );
        await tester.pumpAndSettle();
        final nameRect = tester.getRect(
          find.byKey(const ValueKey('design-field-Name')),
        );
        final typeRect = tester.getRect(
          find.byKey(const ValueKey('design-field-Company Name')),
        );
        expect(nameRect.top, closeTo(typeRect.top, 0.1));
        expect(nameRect.width, greaterThanOrEqualTo(typeRect.width));
        expect(typeRect.left - nameRect.right, closeTo(20, 0.1));
        await tester.drag(
          find
              .descendant(
                of: find.byType(FrontendFormDialog),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
          const Offset(0, 1000),
        );
        await tester.pumpAndSettle();
        await captureUi(tester, 'Vendor Fields ${width.toInt()}');
        await tap(
          find.descendant(
            of: find.byKey(const ValueKey('design-field-Tax Details Needed')),
            matching: find.byType(Switch),
          ),
        );
        expect(find.byKey(const ValueKey('design-field-TIN')), findsNothing);
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(AccountingInformationRows), findsWidgets);
        assertSidewaysDetails(tester);
        expect(find.text('Name').hitTestable(), findsOneWidget);
        expect(
          tester
              .widget<AccountingInformationRows>(
                find.byType(AccountingInformationRows),
              )
              .rows,
          contains(('Tax Details Needed', 'No')),
        );
        expect(find.text('false'), findsNothing);
        await captureUi(tester, 'Vendor Save Review ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        final created = workspace.database
            .vendorDirectory(
              businessId: workspace.identity.businessId,
              search: 'Fictional Vendor',
            )
            .entries
            .single
            .vendor!;
        final id = created.payeeId;
        expect(created.details['postcode'], '00123 AB');
        expect(created.details['countryCode'], 'ZZ');
        expect(created.details['tin'], 'FICT-TIN');
        expect(created.details.taxDetailsNeeded, false);
        expect(created.terms.dayOfMonth, 31);
        expect(created.terms.rolloverWithinDays, 5);
        expect(created.currency.code, 'SGD');
        expect(created.additionalValues, {
          'companyName': 'Fictional Vendor Company',
          'mobileNumber': '+60 000 222',
          'accountNumber': '0007 AB',
          'supplierCategory': 'Foreign Business',
          'billingRate': '125.50',
        });
        expect(workspace.payees.byId(id)!.name, 'Fictional Vendor');
        await tap(find.byKey(ValueKey('view-vendor-$id')));
        expect(find.byType(AccountingInformationRows), findsOneWidget);
        assertSidewaysDetails(tester);
        await captureUi(tester, 'Vendor Details ${width.toInt()}');
        await tester.ensureVisible(find.text('Tax Details Needed'));
        await tester.pumpAndSettle();
        expect(find.text('Tax Details Needed').hitTestable(), findsOneWidget);
        expect(find.text('No').hitTestable(), findsOneWidget);
        await captureUi(tester, 'Vendor Details Bottom ${width.toInt()}');
        await close();
        var saved = tables(workspace);
        await tap(find.byKey(ValueKey('edit-vendor-$id')));
        await text('Name', 'Cancelled rename');
        await tap(find.byKey(const ValueKey('design-close')));
        await tap(find.byKey(const ValueKey('design-discard-changes')));
        expect(tables(workspace), saved);
        await tap(find.byKey(ValueKey('edit-vendor-$id')));
        await text('Name', 'Fictional Vendor Edited');
        await choice('Vendor Type', 'Vendor');
        await choice('Payment Terms', 'Days After Issue');
        await text('Number Of Days', '45');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(
          find.byType(FrontendFormDialog),
          findsNothing,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .whereType<String>()
              .join(' | '),
        );
        final edited = workspace.database.readVendor(
          workspace.identity.businessId,
          created.id,
        )!;
        expect(edited.metadata.revision, 2);
        expect(edited.details['tin'], 'FICT-TIN');
        expect(edited.terms.days, 45);
        expect(edited.additionalValues, created.additionalValues);
        expect(workspace.payees.byId(id)!.type, PayeeType.vendor);
        await tap(find.byKey(ValueKey('history-vendor-$id')));
        await captureUi(tester, 'Vendor History ${width.toInt()}');
        await tap(find.byKey(const ValueKey('vendor-history-view-1')));
        expect(find.text('Vendor Revision 1'), findsOneWidget);
        await captureUi(tester, 'Vendor Earlier Revision ${width.toInt()}');
        await close();
        await close();
        saved = tables(workspace);
        final search = find.byKey(const ValueKey('vendor-search'));
        await tapAndEnter(search, 'Old Supplier 00');
        await tap(find.byKey(const ValueKey('edit-vendor-old-supplier-0')));
        await text('Name', 'Old Supplier 00 Profiled');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        final legacy = workspace.database
            .vendorDirectory(
              businessId: workspace.identity.businessId,
              search: '00 Profiled',
            )
            .entries
            .single;
        expect(legacy.payee.id, 'old-supplier-0');
        expect(legacy.vendor!.payeeId, 'old-supplier-0');
        expect(legacy.vendor!.id.value, isNot('old-supplier-0'));
        saved = tables(workspace);
        await tap(find.byKey(const ValueKey('clear-vendor-filter')));
        await tap(find.byKey(const ValueKey('vendor-page-next')));
        await captureUi(tester, 'Vendor Next Page ${width.toInt()}');
        await tap(find.byKey(const ValueKey('vendor-page-previous')));
        await tap(find.byKey(const ValueKey('vendor-page-size')));
        await tap(find.widgetWithText(MenuItemButton, '5'));
        expect(find.byType(AccountingRecordRow), findsNWidgets(5));
        await tapAndEnter(search, 'example.invalid');
        expect(find.byType(AccountingRecordRow), findsOneWidget);
        await tap(find.byKey(const ValueKey('vendor-type-filter')));
        await tap(find.widgetWithText(MenuItemButton, 'Supplier'));
        expect(find.byType(AccountingRecordRow), findsNothing);
        await tap(find.byKey(const ValueKey('clear-vendor-filter')));
        expect(tables(workspace), saved);
        expect(await workspace.journals(), isEmpty);
        final finalArchive = workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.now(),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        expect(tables(workspace), saved);
        final again = await AccountingWorkspace.emptyRestore(
          '${root.path}/again.sqlite',
          finalArchive,
        );
        expect(tables(again), saved);
        expect(again.payees.byId(id)!.name, 'Fictional Vendor Edited');
        again.dispose();
        expect(
          sha256.convert(File(path).readAsBytesSync()).toString(),
          sourceHash,
        );
      },
    );
  }
}
