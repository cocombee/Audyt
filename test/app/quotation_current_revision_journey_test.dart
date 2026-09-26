import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/quotation_current_revision_test.dart'
    show CurrentQuotationFixture;
import '../support/accounting_test_finders.dart';
import '../support/accounting_text_input.dart';
import '../support/generated_document_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'current converted quotation uses original add/remove and save without changing original invoice at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await installGeneratedDocumentHost(tester);
        final f = CurrentQuotationFixture();
        await f.open(converted: true);
        addTearDown(f.close);
        f.w.savePreferences(
          f.w.preferences.change('Default Accounts', {
            'Income Account': f.account.account.id.value,
          }),
        );
        f.w.savePreferences(
          f.w.preferences.change('Sales Preferences', {
            'Show Quantity': width == 1224,
            'Show Rate': width == 1224,
          }),
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
            child: AudytApp(workspace: f.w, initialPath: '/sales-customers'),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await pumpGeneratedDocumentWork(tester);
        }

        final tabs = tester.widget<AccountingTabs>(
          find.byKey(const ValueKey('area-tabs-sales-customers')),
        );
        await tap(
          find.byKey(
            ValueKey(
              'preview-tab-sales-customers-${tabs.labels.indexOf('Quotations')}',
            ),
          ),
        );
        final original = tables(f.w);
        final originalRecord = f.current;
        final edit = find.byKey(ValueKey('edit-quotation-${f.id}'));
        await tap(edit);
        expect(find.byKey(const ValueKey('design-add-line')), findsOneWidget);
        await tap(find.byKey(const ValueKey('design-add-line')));
        expect(
          find.byKey(const ValueKey('design-remove-line-1')),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-remove-line-1')));
        await tap(accountingCloseIcon().last);
        expect(tables(f.w), original);
        await tap(edit);
        await tap(find.byKey(const ValueKey('design-add-line')));
        Future<void> line(String label, String value) async {
          final field = find
              .byWidgetPredicate(
                (widget) =>
                    (widget is TextFormField ||
                        widget is AccountingDescriptionField) &&
                    widget.key is ValueKey &&
                    (widget.key as ValueKey).value.toString().endsWith(
                      '-$label',
                    ),
              )
              .last;
          await tester.ensureVisible(field);
          await enterAccountingText(tester, field, value);
          await tester.pumpAndSettle();
        }

        await line('Description', 'Added current quotation line');
        await line(width == 1224 ? 'Rate' : 'Amount', '25.00');
        final memo = find.byKey(const ValueKey('design-field-Memo'));
        await tester.ensureVisible(memo);
        await enterAccountingText(tester, memo, 'Current quotation correction');
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('design-add-line')),
        );
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Quotation Current Original Actions ${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.text('Save Changes'), findsOneWidget);
        await tap(find.byKey(const ValueKey('design-review')));
        expect(f.current.revision, originalRecord.revision + 1);
        expect(f.current.quotation.status, originalRecord.quotation.status);
        expect(
          f.current.quotation.convertedInvoiceId,
          originalRecord.quotation.convertedInvoiceId,
        );
        expect(f.current.quotation.lines.length, 2);
        expect(
          f.current.quotation.lines.last.description,
          'Added current quotation line',
        );
        expect(f.current.quotation.memo, 'Current quotation correction');
        final saved = tables(f.w);
        for (final name in [
          'quotation_drafts',
          'quotation_history',
          'invoice_drafts',
          'invoice_draft_history',
          'journal_entries',
        ]) {
          expect(saved[name], original[name], reason: name);
        }
        await tap(edit);
        expect(
          find.byKey(const ValueKey('design-remove-line-1')),
          findsOneWidget,
        );
        await captureUi(tester, 'Quotation Current Saved ${width.toInt()}');
        await tap(accountingCloseIcon().last);
        await tester.pumpWidget(const SizedBox());
        final path = '${f.dir.path}/source.sqlite';
        f.w.dispose();
        f.w = (await tester.runAsync(() => AccountingWorkspace.open(path)))!;
        expect(f.current.quotation.memo, 'Current quotation correction');
        expect(f.current.quotation.lines.length, 2);
        expect(
          f.current.quotation.convertedInvoiceId,
          originalRecord.quotation.convertedInvoiceId,
        );
      },
    );
  }
}
