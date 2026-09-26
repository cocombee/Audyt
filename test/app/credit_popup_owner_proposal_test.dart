import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/sales/invoice_credit_editor.dart';
import 'package:audyt/features/sales/invoice_credit_page.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/credit_posting_fixture.dart';
import '../support/accounting_test_finders.dart';
import 'restored_page_routes_test.dart' show tables;

void main() {
  final inventory = <Map<String, Object?>>[];
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Credit owners keep ordinary fields, original facts and evidence at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        for (final f in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(f.$1)..addFont(rootBundle.load(f.$2))).load();
        }
        final fixture = await creditPostingFixture(paidMinor: 8000);
        final w = fixture.w;
        final original = w.creditDrafts().single;
        w.saveInvoiceCreditDraft(
          draftId: fixture.creditId,
          invoiceId: fixture.invoice.id,
          lineCredits: original.lineCredits,
          reason: 'Reviewed returned goods',
          creditDate: original.date,
          expectedRevision: original.revision,
          savedAt: DateTime.utc(2026, 9, 7),
          attachments: original.attachments,
        );
        var baseline = tables(w);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('credit-owner-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: InvoiceCreditPage(workspace: w)),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder target) async {
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.tap(target);
          await t.pump();
          final loading = find.descendant(
            of: find.byType(AttachmentPreviewDialog),
            matching: find.byType(CircularProgressIndicator),
          );
          for (
            var attempt = 0;
            attempt < 250 && loading.evaluate().isNotEmpty;
            attempt++
          ) {
            await t.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await t.pump();
          }
          await t.pumpAndSettle();
        }

        Future<void> capture(String title) async {
          final path = Platform.environment['AUDYT_CREDIT_OWNER_DIR'];
          if (path == null) return;
          Directory(path).createSync(recursive: true);
          final dialog = find.byType(AlertDialog).last;
          final rect = t.getRect(
            find.descendant(of: dialog, matching: find.byType(Material)).first,
          );
          final filename =
              'Credit Owner ${title.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '')} ${width.toInt()}.png';
          await t.runAsync(() async {
            final image = await t
                .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('credit-owner-capture')),
                )
                .toImage();
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawImageRect(
              image,
              rect,
              Rect.fromLTWH(0, 0, rect.width, rect.height),
              Paint(),
            );
            final picture = recorder.endRecording();
            final cropped = await picture.toImage(
              rect.width.ceil(),
              rect.height.ceil(),
            );
            final data = await cropped.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$path/$filename')
                .writeAsBytesSync(data!.buffer.asUint8List());
            cropped.dispose();
            picture.dispose();
            image.dispose();
          });
          inventory.add({
            'category': 'Accounting popouts',
            'title': title,
            'width': width.toInt(),
            'file': filename,
            'note': 'Actual Credit Notes opener with isolated records; all UI workflows cancelled. Customer/source invoice facts are read-only. Credit Date and free-entry Reason reuse shared ordinary popup fitting; original line amounts, frozen tax splitting and uploaded evidence remain custom. Posting/history/view use approved attachment cards and original View callbacks. Formal credit-note numbering, messages, filename setup and e-invoice submission remain separate pending proposals; this is not full QuickBooks parity.',
            'fields': [],
            'renderedTextLabels': find
                .descendant(of: dialog, matching: find.byType(Text))
                .evaluate()
                .map((e) => (e.widget as Text).data ?? '')
                .where((s) => s.isNotEmpty)
                .toList(),
            'fieldMetadata': 'Actual business-page opener, with no posting or saving during captured UI interaction.',
          });
        }

        await tap(find.byKey(ValueKey(fixture.creditId)));
        expect(find.byType(InvoiceCreditEditor), findsOneWidget);
        expect(find.byType(AccountingOrdinaryFields), findsOneWidget);
        expect(find.text('Fictional Credit Customer'), findsOneWidget);
        final date = t.getRect(find.byKey(const ValueKey('credit-date')));
        final reason = t.getRect(find.byKey(const ValueKey('credit-reason')));
        expect(date.top, closeTo(reason.top, .01));
        expect(date.width, closeTo(reason.width, .01));
        final amount = find.byKey(
          ValueKey('credit-amount-${fixture.invoice.lines.single.id}'),
        );
        expect(t.getSize(amount).width, lessThan(date.width));
        expect(t.widget<TextField>(amount).decoration!.prefixIcon, isNull);
        expect(find.text('Amount (RM)'), findsOneWidget);
        await t.enterText(
          find.byKey(const ValueKey('credit-reason')),
          'Unsaved return explanation',
        );
        await t.pumpAndSettle();
        await capture('Credit Draft · Actual Editor');
        await tap(find.byKey(const ValueKey('cancel-credit')));
        expect(tables(w), baseline);
        await tap(
          find.byKey(ValueKey('post-credit-${fixture.creditId.value}')),
        );
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        expect(find.byType(AccountingAttachmentList), findsOneWidget);
        final form = t.widget<FrontendFormDialog>(
          find.byType(FrontendFormDialog),
        );
        expect(form.form.fields.single.label, 'Customer Credit Account');
        expect(
          form.form.fields.single.choiceLabels!.values.any(
            (s) => s.contains('Tax Payable'),
          ),
          isFalse,
        );
        await capture('Post Credit · Original Accounts');
        await tap(
          find.byKey(
            const ValueKey('credit-posting-evidence-demo-CREDIT-SUPPORT'),
          ),
        );
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        await tap(accountingCloseIcon().last);
        expect(find.byType(AttachmentPreviewDialog), findsNothing);
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsNothing,
        );
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tables(w), baseline);
        await tap(find.byKey(ValueKey('history-${fixture.creditId}')));
        expect(find.byType(AccountingAttachmentRecordRow), findsNWidgets(2));
        expect(find.byKey(const ValueKey('restore-credit-1')), findsOneWidget);
        final restoreHelp = t.widget<Tooltip>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('restore-credit-1')),
                matching: find.byType(Tooltip),
              )
              .first,
        );
        expect(restoreHelp.message, 'Restore As New Revision');
        expect(
          t.getSize(find.byKey(const ValueKey('restore-credit-1'))),
          const Size(32, 32),
        );
        expect(find.text('Restore As New Revision'), findsNothing);
        expect(find.text('Revision 1'), findsOneWidget);
        expect(find.text('Revision 2'), findsOneWidget);
        expect(find.byType(AccountingRecordList), findsWidgets);
        await capture('Credit History · Original Evidence');
        await tap(find.byKey(const ValueKey('history-1-demo-CREDIT-SUPPORT')));
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        await tap(accountingCloseIcon().last);
        await tap(accountingCloseIcon().last);
        expect(tables(w), baseline);
        // Isolated setup for the immutable posted-view state, outside UI actions.
        w.postInvoiceCredit(
          requestId: EntityId.random(),
          draftId: fixture.creditId,
          expectedRevision: 2,
          expectedPaidMinor: 8000,
          expectedPriorCreditMinor: 0,
          approvedAt: DateTime.utc(2026, 9, 8),
          customerCreditAccount: fixture.liability,
        );
        baseline = tables(w);
        await t.pumpAndSettle();
        await tap(find.byKey(ValueKey(fixture.creditId)));
        expect(find.text('Posted Credit'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        await capture('Posted Credit · Facts And Evidence');
        await tap(
          find.byKey(
            ValueKey(
              'credit-view-file-${fixture.creditId.value}-demo-CREDIT-SUPPORT',
            ),
          ),
        );
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        await tap(accountingCloseIcon().last);
        await tap(accountingCloseIcon().last);
        expect(tables(w), baseline);
        await tap(find.byKey(ValueKey('history-${fixture.creditId}')));
        expect(find.byKey(const ValueKey('restore-credit-1')), findsNothing);
        await capture('Posted Credit History · Read Only');
        await tap(accountingCloseIcon().last);
        expect(tables(w), baseline);
        expect(t.takeException(), isNull);
        final path = Platform.environment['AUDYT_CREDIT_OWNER_DIR'];
        if (path != null) {
          File('$path/Credit Owner Inventory.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(inventory),
          );
        }
      },
    );
  }
}
