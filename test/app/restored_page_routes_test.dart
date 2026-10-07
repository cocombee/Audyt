import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/feature_registry.dart';
import 'package:audyt/app/user_directory.dart';
import 'package:audyt/app/users_page.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/sales/product_catalogue_page.dart';
import 'package:audyt/features/accounting/presentation/expense_intake_page.dart';
import 'package:audyt/features/accounting/presentation/journal_workspace_page.dart';
import 'package:audyt/features/accounting/presentation/ledger_reports_page.dart';
import 'package:audyt/features/accounting/presentation/payables_ageing_page.dart';
import 'package:audyt/features/accounting/presentation/reminders_page.dart';
import 'package:audyt/features/accounting/presentation/tax_rates_page.dart';
import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/vendors_page.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/purchases/presentation/pay_bills_page.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:audyt/features/sales/customer_receipts_page.dart';
import 'package:audyt/features/sales/customer_statement_page.dart';
import 'package:audyt/features/sales/invoice_credit_page.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:audyt/features/sales/receivable_ageing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> tables(AccountingWorkspace workspace) {
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

void main() {
  for (final width in [720.0, 1162.0, 1224.0, 2056.0]) {
    testWidgets('every reachable tab uses restored company data at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 809);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureDir = Platform.environment['AUDYT_ROUTE_CAPTURE_DIR'];
      if (captureDir != null) {
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      final root = Directory.systemTemp.createTempSync('audyt-route-recovery-');
      addTearDown(() => root.deleteSync(recursive: true));
      final original = await createDemoWorkspace(
        databasePath: '${root.path}/original.sqlite',
      );
      original.savePreferences(
        original.preferences.change('Business Profile', {
          'Business Name': 'Saved Audit Company',
        }),
      );
      original.savePreferences(
        original.preferences.change('Sales Preferences', {
          'Customer Message': 'Saved customer message',
          'Enable Discounts': false,
        }),
      );
      final identity = original.identity;
      final before = tables(original);
      final archive = original.database.exportDataArchive(
        identity.businessId,
        DateTime.now(),
      );
      original.dispose();
      final originalBytes = File('${root.path}/original.sqlite')
          .readAsBytesSync();
      final restored = await AccountingWorkspace.emptyRestore(
        '${root.path}/restored.sqlite',
        archive,
      );
      restored.dispose();
      var workspace = await AccountingWorkspace.open(
        '${root.path}/restored.sqlite',
      );
      addTearDown(() => workspace.dispose());
      expect(workspace.identity.businessId, identity.businessId);
      expect(workspace.identity.ownerId, identity.ownerId);
      expect(tables(workspace), before);
      final directory = PreviewUserDirectory(); // Fictional users are separate from live service authority.
      addTearDown(directory.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: AudytApp(workspace: workspace, userDirectory: directory),
        ),
      );
      await tester.pumpAndSettle();
      if (width == 720) {
        expect(find.byTooltip('Company: Saved Audit Company'), findsOneWidget);
      } else {
        expect(find.text('Saved Audit Company'), findsOneWidget);
      }
      final liveOwners = <String, Type>{
        'Products & Services': ProductCataloguePage,
        'Expenses': ExpenseIntakePage,
        'Claims': ClaimsPage,
        'Payment Vouchers': PaymentVouchersPage,
        'Vendors': VendorsPage,
        'Bills': BillsPage,
        'Pay Bills': PayBillsPage,
        'Invoices': InvoicePage,
        'Quotations': QuotationPage,
        'Customers': CustomerPage,
        'Credit Notes': InvoiceCreditPage,
        'Receive Payment': CustomerReceiptsPage,
        'Customer Statements': CustomerStatementPage,
        'Bank Activity': BankingPage,
        'Ledger Reports': LedgerReportsPage,
        'Receivables Ageing': ReceivableAgeingPage,
        'Payables Ageing': PayablesAgeingPage,
        'Deadlines': RemindersPage,
        'Tax Codes': TaxRatesPage,
        'Tax Overview': TaxOverviewPage,
        'Chart Of Accounts': ChartOfAccountsPage,
        'Journal Review': JournalReviewPage,
      };
      final visited = <String>[];
      Future<void> capture(String label) async {
        if (captureDir == null) return;
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
        Future<void> save(String suffix) async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final frame = await boundary.toImage(pixelRatio: 1);
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$captureDir/Route $label$suffix ${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            frame.dispose();
          });
        }

        await save('');
        final mainScroll = find.byKey(const ValueKey('accounting-main-scroll'));
        if (mainScroll.evaluate().isEmpty) return;
        final scrollable = find.descendant(
          of: mainScroll,
          matching: find.byType(Scrollable),
        );
        if (scrollable.evaluate().isEmpty) return;
        final position = tester
            .state<ScrollableState>(scrollable.first)
            .position;
        if (position.maxScrollExtent <= 1) return;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        await save(' Bottom');
        position.jumpTo(0);
        await tester.pumpAndSettle();
      }

      for (final feature in FeatureRegistry.navigationGroups.expand(
        (g) => g.features,
      )) {
        final navigationItem = find.byKey(
          ValueKey('navigation-item-${feature.id}'),
        );
        await tester.ensureVisible(navigationItem);
        await tester.tap(navigationItem);
        await tester.pumpAndSettle();
        if (feature.id == 'home') {
          expect(
            tester
                .widget<WorkspaceAccountingHome>(
                  find.byType(WorkspaceAccountingHome),
                )
                .workspace,
            same(workspace),
          );
          await capture('Home');
        } else if (feature.id == 'users') {
          expect(
            tester.widget<UsersPage>(find.byType(UsersPage)).directory,
            same(directory),
          );
          await capture('Employees');
        } else {
          final tabs = tester.widget<AccountingTabs>(
            find.byKey(ValueKey('area-tabs-${feature.id}')),
          );
          for (var i = 0; i < tabs.labels.length; i++) {
            final label = tabs.labels[i];
            final tab = find.byKey(ValueKey('preview-tab-${feature.id}-$i'));
            await tester.ensureVisible(tab);
            await tester.tap(tab);
            await tester.pumpAndSettle();
            visited.add('${feature.id}/$label');
            if (liveOwners[label] case final owner?) {
              final page = find.byType(owner);
              expect(
                page,
                findsOneWidget,
                reason:
                    '$label must reach its durable page, not its catalogue form',
              );
              expect(
                find.byKey(const ValueKey('design-open-form')),
                findsNothing,
              );
              if (owner == ClaimsPage) {
                expect(
                  tester.widget<ClaimsPage>(page).store,
                  same(workspace.claims),
                );
              } else if (owner == PaymentVouchersPage) {
                expect(
                  tester.widget<PaymentVouchersPage>(page).store,
                  same(workspace.vouchers),
                );
              } else {
                expect(
                  (tester.widget(page) as dynamic).workspace,
                  same(workspace),
                );
              }
              await capture(label);
            } else if (label == 'Accounting Review Queue') {
              expect(
                find.byKey(const ValueKey('review-queue-expenses')),
                findsOneWidget,
              );
              await capture(label);
            } else {
              expect(
                find.byKey(const ValueKey('design-open-form')),
                findsOneWidget,
                reason: label,
              );
              expect(
                find.text(
                  'Preview records last only while this screen is open. Existing accounting records are unaffected.',
                ),
                findsOneWidget,
              );
              if (i == 0) await capture(label);
            }
            expect(tester.takeException(), isNull, reason: '$label at $width');
          }
        }
      }
      expect(
        visited.map((path) => path.split('/').last).toSet(),
        containsAll(liveOwners.keys),
      );
      expect(
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        'Saved customer message',
      );
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Enable Discounts'),
        false,
      );
      expect(
        tables(workspace),
        before,
        reason: 'Visiting every tab must preserve all restored table rows',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(
        '${root.path}/restored.sqlite',
      );
      expect(
        tables(workspace),
        before,
        reason:
            'All rows and links must remain unchanged after a second restart',
      );
      expect(
        File('${root.path}/original.sqlite').readAsBytesSync(),
        orderedEquals(originalBytes),
      );
      if (captureDir != null) {
        File('$captureDir/Page Route Coverage ${width.toInt()}.json')
            .writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert({
                'viewport': width,
                'visitedTabs': visited,
                'livePages': liveOwners.keys.toList(),
                'unchangedRestoredTables': before.keys.toList(),
                'originalFileBytesUnchanged': true,
                'limits': 'Fictional disposable company; Users is a separate preview fixture. Navigation/read evidence, not proof of all mutation commands or hosted authority.',
              }),
            );
      }
    });
  }

  testWidgets('sidebar company name follows saved preferences and reopening', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('audyt-company-name-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/company.sqlite';
    var workspace = await AccountingWorkspace.open(path);
    tester.view.physicalSize = const Size(1224, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AudytApp(workspace: workspace));
    await tester.pumpAndSettle();
    expect(find.text('Current Company'), findsOneWidget);

    workspace.savePreferences(
      workspace.preferences.change('Business Profile', {
        'Business Name': 'Saved Audit Company',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved Audit Company'), findsOneWidget);
    expect(find.text('Current Company'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('company-switcher')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('company-option-current')),
        matching: find.text('Saved Audit Company'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(720, 900);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Company: Saved Audit Company'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    workspace.dispose();
    workspace = await AccountingWorkspace.open(path);
    addTearDown(workspace.dispose);
    tester.view.physicalSize = const Size(1224, 900);
    await tester.pumpWidget(AudytApp(workspace: workspace));
    await tester.pumpAndSettle();
    expect(find.text('Saved Audit Company'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
