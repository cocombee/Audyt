import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/account_repository.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/customer.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'saved invoice choices remain visible after master changes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final captureDir = Platform.environment['AUDYT_INVOICE_CAPTURE_DIR'];
        if (captureDir != null) {
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        final boundaryKey = GlobalKey();
        Future<void> capture(String label) async {
          if (captureDir == null) return;
          await tester.pumpAndSettle();
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final frame = await boundary.toImage(pixelRatio: 1);
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$captureDir/Invoice $label ${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            frame.dispose();
          });
        }

        Future<void> discardInvoiceChanges() async {
          await tester.ensureVisible(
            find.byKey(const ValueKey('design-close')),
          );
          await tester.tap(find.byKey(const ValueKey('design-close')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('design-discard-changes')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('design-field-Counterparty')),
            findsNothing,
          );
        }

        final root = Directory.systemTemp.createTempSync(
          'audyt-invoice-choices-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/ledger.sqlite';
        var workspace = await AccountingWorkspace.open(path);
        addTearDown(() => workspace.dispose());
        for (final spec in [
          ('4100', 'Saved Income'),
          ('4200', 'Active Income'),
        ]) {
          await workspace.createAccount(
            code: spec.$1,
            name: spec.$2,
            type: AccountType.income,
          );
        }
        final income = (await workspace.accounts()).firstWhere(
          (a) => a.account.code == '4100',
        );
        final customers = [
          for (final name in ['Saved Customer', 'Active Customer'])
            Customer.create(
              metadata: RecordMetadata.initial(
                recordId: EntityId.random(),
                businessId: workspace.identity.businessId,
                originDeviceId: workspace.identity.deviceId,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              displayName: name,
              contact: const CustomerContact(),
              taxProfile: const CustomerTaxProfile(),
              currency: Currency.parse('MYR'),
              paymentTerms: PaymentTerms.netDays(30),
            ),
        ];
        for (final customer in customers) {
          workspace.saveCustomer(customer);
        }
        final draft = invoiceFromForm(
          {
            'Counterparty': customers.first.id.value,
            'Date': '01-01-2026',
            'Document Number': 'INV-SAVED-CHOICES',
            'Currency': 'MYR',
            'Payment Terms': 'Use Customer Default',
            'Tax Mode': 'Exclusive',
            '_lines': [
              {
                '_lineId': EntityId.random().value,
                'Description': 'Saved service',
                'Quantity': '1',
                'Rate': '90',
                'Discount': '0',
                'Tax Rate (%)': '0',
                'Account': income.account.id.value,
              },
            ],
          },
          id: EntityId.random(),
          customer: customers.first,
          incomeAccountIds: {income.account.id.value},
        );
        workspace.saveInvoiceDraft(
          draft,
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 1, 2),
        );
        workspace.saveCustomer(
          customers.first.deactivate(updatedAt: DateTime.utc(2026, 2, 1)),
        );
        await workspace.database.saveAccount(
          StoredAccount(
            account: Account.create(
              id: income.account.id,
              code: income.account.code,
              name: income.account.name,
              type: income.account.type,
              status: AccountStatus.locked,
            ),
            metadata: income.metadata.nextRevision(
              updatedAt: income.metadata.updatedAt.add(
                const Duration(seconds: 1),
              ),
            ),
          ),
        );
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(body: InvoicePage(workspace: workspace)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('edit-invoice-${draft.id.value}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Saved Customer · Inactive'), findsOneWidget);
        expect(find.text('4100 · Saved Income · Locked'), findsOneWidget);
        expect(find.text('Unavailable Selection'), findsNothing);
        await capture('Saved Choices');
        final accountTrigger = find.byKey(
          ValueKey('${draft.lines.single.id.value}-Account'),
        );
        await tester.ensureVisible(accountTrigger);
        await tester.pumpAndSettle();
        await capture('Saved Account');
        await tester.tap(accountTrigger);
        await tester.pumpAndSettle();
        await capture('Account Choices');
        await tester.tap(find.text('4100 · Saved Income · Locked').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Choose an active customer.'),
          findsOneWidget,
        );
        await capture('Inactive Customer');
        expect(workspace.invoiceDrafts().single.revision, 1);
        expect(
          workspace.invoiceDrafts().single.invoice.draftSnapshot(),
          draft.draftSnapshot(),
        );
        // Invalid master selections keep the editor open; no review commits.
        expect(find.byKey(const ValueKey('design-back')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('design-field-Counterparty')),
        );
        await tester.tap(
          find.byKey(const ValueKey('design-field-Counterparty')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Active Customer'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Choose an active income account for each line.'),
          findsOneWidget,
        );
        await capture('Locked Account');
        expect(workspace.invoiceDrafts().single.revision, 1);
        expect(
          workspace.invoiceDrafts().single.invoice.draftSnapshot(),
          draft.draftSnapshot(),
        );
        await discardInvoiceChanges();
        await tester.tap(find.byKey(const ValueKey('new-invoice')));
        await tester.pumpAndSettle();
        expect(find.text('Saved Customer · Inactive'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('design-field-Counterparty')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Active Customer'), findsOneWidget);
        expect(find.textContaining('Saved Customer'), findsNothing);
        await tester.tap(find.text('Active Customer'));
        await tester.pumpAndSettle();
        await discardInvoiceChanges();
        // Simulate a master-data update after this editor has loaded its choices.
        await tester.tap(
          find.byKey(ValueKey('edit-invoice-${draft.id.value}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('design-field-Counterparty')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Active Customer'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(accountTrigger);
        await tester.tap(accountTrigger);
        await tester.pumpAndSettle();
        await tester.tap(find.text('4200 · Active Income'));
        await tester.pumpAndSettle();
        final currentIncome = (await workspace.accounts()).singleWhere(
          (stored) => stored.account.code == '4200',
        );
        await workspace.database.saveAccount(
          StoredAccount(
            account: Account.create(
              id: currentIncome.account.id,
              code: currentIncome.account.code,
              name: currentIncome.account.name,
              type: currentIncome.account.type,
              status: AccountStatus.locked,
            ),
            metadata: currentIncome.metadata.nextRevision(
              updatedAt: currentIncome.metadata.updatedAt.add(
                const Duration(seconds: 1),
              ),
            ),
          ),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(
          workspace.invoiceDrafts().single.revision,
          1,
          reason: 'Locking the selected account while editing must reject Save',
        );
        expect(
          find.textContaining('Choose an active income account for each line.'),
          findsOneWidget,
        );
        await capture('Changed While Open');
        expect(workspace.invoiceDrafts().single.revision, 1);
        expect(
          workspace.invoiceDrafts().single.invoice.draftSnapshot(),
          draft.draftSnapshot(),
        );
        // Invalid master selections keep the editor open; no review commits.
        expect(find.byKey(const ValueKey('design-back')), findsNothing);
        workspace.saveCustomer(
          customers.last.deactivate(updatedAt: DateTime.utc(2026, 3, 1)),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('design-review')));
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Choose an active customer.'),
          findsOneWidget,
        );
        await capture('Customer Changed While Open');
        expect(workspace.invoiceDrafts().single.revision, 1);
        expect(
          workspace.invoiceDrafts().single.invoice.draftSnapshot(),
          draft.draftSnapshot(),
        );
        await discardInvoiceChanges();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        expect(workspace.invoiceDrafts().single.revision, 1);
        expect(
          workspace.invoiceDrafts().single.invoice.draftSnapshot(),
          draft.draftSnapshot(),
        );
        expect(
          workspace.customers().every((customer) => !customer.isActive),
          isTrue,
        );
        expect(
          (await workspace.accounts()).every(
            (stored) => stored.account.status == AccountStatus.locked,
          ),
          isTrue,
        );
      },
    );
  }
}
