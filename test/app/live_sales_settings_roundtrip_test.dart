import 'package:audyt/app/accounting_description_field.dart';

import '../support/accounting_text_input.dart';

import '../support/generated_document_host.dart';

import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';

import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('saved Sales settings reach invoice workflows at $width', (
      tester,
    ) async {
      installFixedPopoutHost(tester);
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      await installGeneratedDocumentHost(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final root = Directory.systemTemp.createTempSync('audyt-sales-settings-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sourcePath = '${root.path}/source.sqlite';
      final original = await createDemoWorkspace(databasePath: sourcePath);
      final account = (await original.accounts()).singleWhere(
        (entry) => entry.account.code == '4000',
      );
      final customer = original.customers().last;
      final now = DateTime.now();
      final invoice = Invoice.draft(
        id: EntityId.random(),
        customerId: customer.id,
        documentNumber: 'SETTINGS-ROUNDTRIP',
        issueDate: DateTime(now.year, now.month, now.day),
        terms: customer.paymentTerms,
        taxMode: 'Exclusive',
        classification: 'Saved Class',
        location: 'Saved Branch',
        lines: [
          SalesLineItem.category(
            id: EntityId.random(),
            categoryId: account.account.id,
            description: 'Saved service',
            quantity: SalesQuantity.fromInt(3),
            rate: Money.fromMinor(10000, 'MYR'),
            discount: Money.fromMinor(1000, 'MYR'),
            taxRatePercent: '6',
          ),
        ],
      );
      original.saveInvoiceDraft(
        invoice,
        expectedRevision: 0,
        savedAt: now.toUtc(),
      );
      final originalTables = tables(original);
      final archive = original.database.exportDataArchive(
        original.identity.businessId,
        now,
      );
      original.dispose();
      final sourceBytes = File(sourcePath).readAsBytesSync();
      final path = '${root.path}/restored.sqlite';
      var workspace = await AccountingWorkspace.emptyRestore(path, archive);
      addTearDown(() => workspace.dispose());
      expect(tables(workspace), originalTables);
      var revision = workspace.preferences.revision;

      Future<void> pumpApp() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: workspace, showInitialSetup: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tapVisible(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await pumpGeneratedDocumentWork(tester);
      }

      Future<void> settings(bool enabled, String message) async {
        await tapVisible(find.byKey(const ValueKey('accounting-settings')));
        await tapVisible(find.text('Sales Preferences').first);
        for (final field in ['Show Rate', 'Enable Discounts']) {
          final toggle = find.byKey(ValueKey('design-field-$field'));
          if (tester.widget<AccountingSwitchListTile>(toggle).value !=
              enabled) {
            await tapVisible(toggle);
          }
        }
        final messageField = find.byKey(
          const ValueKey('design-field-Customer Message'),
        );
        await tester.ensureVisible(messageField);
        await enterAccountingText(tester, messageField, message);
        await tapVisible(find.byKey(const ValueKey('design-save-settings')));
        expect(workspace.preferences.revision, ++revision);
        for (final field in ['Show Rate', 'Enable Discounts']) {
          expect(
            workspace.preferences.enabled('Sales Preferences', field),
            enabled,
          );
        }
        expect(
          workspace.preferences.text('Sales Preferences', 'Customer Message'),
          message,
        );
        expect(
          find.byKey(const ValueKey('design-save-settings')),
          findsOneWidget,
        );
        await captureUi(
          tester,
          'Settings Sales Saved $enabled ${width.toInt()}',
        );
        await tapVisible(find.byKey(const ValueKey('design-preview')));
        final page = find.byKey(const ValueKey('invoice-document-page'));
        expect(page, findsOneWidget);
        final text = tester
            .widgetList<Text>(
              find.descendant(of: page, matching: find.byType(Text)),
            )
            .map((widget) => widget.data ?? '')
            .join('\n');
        expect(text, contains(message));
        // Existing invoice facts stay visible when entry switches are off.
        expect(text, contains('Quantity'));
        expect(text, contains('Discount'));
        expect(text, contains('Tax Rate'));
        await captureUi(
          tester,
          'Settings Sales Preview $enabled ${width.toInt()}',
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('invoice-document-dialog')),
            matching: find.byType(IconButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.label == 'Close',
              )
              .last,
        );
        await tester.pumpAndSettle();
      }

      Future<void> newInvoice(bool enabled) async {
        await tapVisible(
          find.byKey(const ValueKey('navigation-item-sales-customers')),
        );
        await tapVisible(find.byKey(const ValueKey('new-invoice')));
        final dialog = tester.widget<FrontendFormDialog>(
          find.byType(FrontendFormDialog),
        );
        expect(dialog.form.lineFields!.contains('Quantity'), enabled);
        expect(dialog.form.lineFields!.contains('Rate'), enabled);
        expect(dialog.form.lineFields!.contains('Amount'), !enabled);
        expect(dialog.form.lineFields!.contains('Discount'), enabled);
        final visibleLineValue = find.byWidgetPredicate(
          (widget) =>
              (widget is TextFormField ||
                  widget is AccountingDescriptionField) &&
              widget.key is ValueKey &&
              (widget.key as ValueKey).value.toString().endsWith(
                enabled ? '-Quantity' : '-Amount',
              ),
        );
        expect(visibleLineValue, findsOneWidget);
        await tester.ensureVisible(visibleLineValue);
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Settings New Invoice $enabled ${width.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('design-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsNothing,
        );
        expect(find.byType(FrontendFormDialog), findsNothing);
      }

      await pumpApp();
      await settings(false, 'Saved message while switches are off');
      await newInvoice(false);
      await tapVisible(
        find.byKey(ValueKey('edit-invoice-${invoice.id.value}')),
      );
      final form = tester.widget<FrontendFormDialog>(
        find.byType(FrontendFormDialog),
      );
      expect(
        form.form.lineFields,
        containsAll(['Quantity', 'Rate', 'Discount']),
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('design-field-Memo')),
        'Edited after switches were disabled',
      );
      await tapVisible(find.byKey(const ValueKey('design-review')));
      expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
      await tapVisible(find.byKey(const ValueKey('design-review')));
      final saved = workspace.invoiceDrafts().singleWhere(
        (r) => r.invoice.id == invoice.id,
      );
      expect(saved.revision, 2);
      expect(
        saved.invoice.lines.map((line) => line.toJson()),
        invoice.lines.map((line) => line.toJson()),
      );
      expect(saved.invoice.total, invoice.total);
      expect(saved.invoice.classification, invoice.classification);
      expect(saved.invoice.location, invoice.location);
      expect(saved.invoice.memo, 'Edited after switches were disabled');
      final savedTables = tables(workspace);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(tables(workspace), savedTables);
      expect(File(sourcePath).readAsBytesSync(), sourceBytes);
      await pumpApp();
      await newInvoice(false);
      await settings(true, 'Saved message after re-enabling');
      await newInvoice(true);
      expect(
        workspace
            .invoiceDrafts()
            .singleWhere((r) => r.invoice.id == invoice.id)
            .invoice
            .draftSnapshot(),
        saved.invoice.draftSnapshot(),
      );
      final enabledTables = tables(workspace);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      expect(tables(workspace), enabledTables);
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Enable Discounts'),
        isTrue,
      );
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Show Rate'),
        isTrue,
      );
      expect(File(sourcePath).readAsBytesSync(), sourceBytes);
      expect(tester.takeException(), isNull);
    });
  }
}
