import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'filed_document_version_relocation_test.dart' show receiptImage;
import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/attachment_preview_pump.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'uploaded transaction rows view, convert and retain exact evidence at $width',
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
        final root = Directory.systemTemp.createTempSync('audyt-upload-row-');
        addTearDown(() => root.deleteSync(recursive: true));
        final bytes = receiptImage(26, 175, 135);
        final file = File('${root.path}/Fictional Evidence.png')
          ..writeAsBytesSync(bytes);
        Map<String, Object?>? saved;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => FrontendFormDialog(
                        form: const DesignForm('Transaction', [
                          DesignField('Date'),
                        ], evidence: true),
                        onCommit: (values) async {
                          saved = values;
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
        final drop = tester.widget<DropTarget>(find.byType(DropTarget));
        await tester.runAsync(() async {
          drop.onDragDone!(
            DropDoneDetails(
              files: [DropItemFile(file.path)],
              localPosition: Offset.zero,
              globalPosition: Offset.zero,
            ),
          );
        });
        final importDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (find.byType(AccountingAttachmentRecordRow).evaluate().isEmpty &&
            DateTime.now().isBefore(importDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final row = tester.widget<AccountingAttachmentRecordRow>(
          find.byType(AccountingAttachmentRecordRow),
        );
        final original = row.attachment;
        expect(original.originalBytes, bytes);
        expect(
          find.text(accountingAttachmentFileSummary(original)),
          findsOneWidget,
        );
        for (final action in ['preview', 'edit', 'remove']) {
          final button = find.byKey(ValueKey('$action-supporting-file-0'));
          expect(tester.widget(button), isA<IconButton>());
          expect(tester.getSize(button), const Size(32, 32));
        }
        await tester.ensureVisible(find.byType(AccountingAttachmentRecordRow));
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Uploaded Transaction Image Row ${width.toInt()}',
        );
        await tester.tap(
          find.byKey(const ValueKey('preview-supporting-file-0')),
        );
        await pumpDecodedAttachment(tester);
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        final preview = tester.widget<Image>(find.byType(Image));
        expect((preview.image as MemoryImage).bytes, bytes);
        await tester.tap(
          find
              .descendant(
                of: find.byType(AttachmentPreviewDialog),
                matching: find.byType(IconButton),
              )
              .last,
        );
        await tester.pumpAndSettle();
        final convert = find.byKey(const ValueKey('convert-supporting-file-0'));
        await tester.ensureVisible(convert);
        await tester.runAsync(() => tester.tap(convert));
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (convert.evaluate().isNotEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(convert, findsNothing);
        final converted = tester
            .widget<AccountingAttachmentRecordRow>(
              find.byType(AccountingAttachmentRecordRow),
            )
            .attachment;
        expect(converted.pdfBytes, isNotNull);
        expect(String.fromCharCodes(converted.pdfBytes!.take(4)), '%PDF');
        expect(converted.originalId, original.originalId);
        expect(converted.originalBytes, bytes);
        expect(converted.originalSha256, original.originalSha256);
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        final committed =
            (saved!['_attachments'] as List).single as ReceiptAttachment;
        expect(committed.originalId, original.originalId);
        expect(committed.originalBytes, bytes);
        expect(committed.pdfSha256, converted.pdfSha256);
        expect(file.readAsBytesSync(), bytes);
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
