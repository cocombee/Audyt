import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/documents/receipt_edit_files.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets(
    'opening editor previews exact temporary bytes and does not delete on disposal',
    (tester) async {
      final bytes = image.encodePng(image.Image(width: 40, height: 60));
      final attachment = await ReceiptDocumentPipeline().process(
        ReceiptAttachmentInput(
          originalId: 'a',
          batchId: 'b',
          filename: 'a.png',
          mimeType: 'image/png',
          bytes: bytes,
        ),
      );
      final queue = ReceiptReviewQueue([attachment]);
      final files = ReceiptEditFiles();
      addTearDown(queue.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: ReceiptReviewDialog(queue: queue, editFiles: files),
          ),
        );
        for (var attempt = 0; attempt < 250; attempt++) {
          try {
            if ((await files.read('a')).length == bytes.length) break;
          } on StateError {
            // The editor has not registered its temporary file yet.
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      final temporary = File(files.temporaryPath('a'));
      await tester.runAsync(() async {
        expect(await files.read('a'), orderedEquals(bytes));
      });
      expect(find.text('PNG · ${bytes.length} B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        expect(await temporary.exists(), true);
        await files.discardAll();
      });
    },
  );
}
