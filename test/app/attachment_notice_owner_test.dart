import 'dart:async';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture;

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final pdf in [false, true]) {
      testWidgets(
        'actual attachment notice shares Close and header at $width / $pdf',
        (tester) async {
          await prepare(tester, width);
          final pending = Completer<Map<String, dynamic>>();
          const channel = MethodChannel('audyt/document-preview');
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (_) => pending.future,
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          final filename =
              'Fictional September Expense Receipt With Supporting Information.${pdf ? 'pdf' : 'docx'}';
          final attachment = ReceiptAttachment.queued(
            ReceiptAttachmentInput(
              originalId: 'original-1790985708123456-0',
              batchId: 'fictional',
              filename: filename,
              mimeType: pdf ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              bytes: Uint8List.fromList([1, 2, 3, 4]),
            ),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => AccountingButton.primary(
                      context,
                      key: const ValueKey('view-original'),
                      onPressed: () =>
                          showAttachmentPreview(context, attachment),
                      child: const Text('View Original'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('View Original'));
          await tester.pump(const Duration(milliseconds: 400));
          if (pdf) {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(
              find.byKey(const ValueKey('attachment-preview-notice-close')),
              findsOneWidget,
            );
            pending.completeError(
              PlatformException(
                code: 'password_protected',
                message: 'This PDF requires its original password before it can be previewed.',
              ),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          final surface = tester.getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('attachment-preview-notice')),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Material && widget.type == MaterialType.card,
                  ),
                )
                .first,
          );
          final close = tester.getRect(
            find.byKey(const ValueKey('attachment-preview-notice-close')),
          );
          expect(
            close.top - surface.top,
            closeTo(AccountingPopoutTokens.closeInset, .01),
          );
          expect(
            surface.right - close.right,
            closeTo(AccountingPopoutTokens.closeInset, .01),
          );
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text(filename), findsOneWidget);
          expect(
            tester.widget<Text>(find.text(filename)).style,
            AccountingTypography.sectionTitle(
              tester.element(find.text(filename)),
            ),
          );
          expect(
            find.byKey(const ValueKey('accounting-form-dialog-footer')),
            findsNothing,
          );
          expect(find.text('Cancel'), findsNothing);
          expect(find.text('Close'), findsNothing);
          if (pdf) {
            expect(
              find.text(
                'This PDF requires its original password before it can be previewed.',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'Attachment ${pdf ? 'Protected PDF' : 'Unsupported Document'} Notice ${width.toInt()}',
          );
          await tester.tap(
            find.byKey(const ValueKey('attachment-preview-notice-close')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AttachmentPreviewDialog), findsNothing);
          expect(find.text('View Original'), findsOneWidget);
        },
      );
    }
  }
}
