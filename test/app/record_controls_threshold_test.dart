import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

void main() {
  setUp(AccountingRecordPageSizes.reset);
  tearDown(AccountingRecordPageSizes.reset);
  Widget host(int count, {int? total, String identity = 'test-list'}) =>
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                AccountingRecordControls(
                  recordCount: total ?? count,
                  child: const TextField(key: ValueKey('top-search')),
                ),
                AccountingRecordList(
                  paginationKey: identity,
                  totalCount: total,
                  children: [
                    for (var i = 0; i < count; i++)
                      AccountingRecordRow(
                        key: ValueKey('row-$i'),
                        title: 'Record $i',
                        details: const Text('Details'),
                        trailing: const SizedBox.shrink(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  for (final count in [0, 1, 2, 5]) {
    testWidgets(
      '$count records hide top and bottom controls without losing rows',
      (tester) async {
        await tester.pumpWidget(host(count));
        expect(find.byKey(const ValueKey('top-search')), findsNothing);
        expect(find.text('Rows'), findsNothing);
        expect(find.text('Previous'), findsNothing);
        expect(find.text('Next'), findsNothing);
        expect(find.byType(AccountingRecordRow), findsNWidgets(count));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'six records reveal filters and five-row paging; return remembers only this view',
    (tester) async {
      await tester.pumpWidget(host(6));
      expect(find.byKey(const ValueKey('top-search')), findsOneWidget);
      expect(find.text('1–5 of 6'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-5')), findsNothing);
      final footer = tester.widget<AccountingRecordPagination>(
        find.byType(AccountingRecordPagination),
      );
      expect(footer.pageSize, 5);
      await tester.tap(find.byKey(const ValueKey('test-list-page-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('row-5')), findsOneWidget);
      expect(find.text('6–6 of 6'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('test-list-page-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, '10').last);
      await tester.pumpAndSettle();
      expect(find.text('1–6 of 6'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host(6));
      expect(
        tester
            .widget<AccountingRecordPagination>(
              find.byType(AccountingRecordPagination),
            )
            .pageSize,
        10,
      );
      await tester.pumpWidget(host(6, identity: 'another-tab'));
      expect(
        tester
            .widget<AccountingRecordPagination>(
              find.byType(AccountingRecordPagination),
            )
            .pageSize,
        5,
      );
      await tester.pumpWidget(host(1, total: 6, identity: 'another-tab'));
      expect(find.byKey(const ValueKey('top-search')), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
    },
  );
  for (final count in [1, 2, 5, 6]) {
    testWidgets('$count attachments use one surface and threshold paging', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountingAttachmentList(
                paginationKey: 'test-attachments',
                children: [
                  for (var i = 0; i < count; i++)
                    AccountingAttachmentRecordRow(
                      attachment: ReceiptAttachment.queued(
                        ReceiptAttachmentInput(
                          originalId: 'receipt-$i',
                          batchId: 'test-batch',
                          filename: 'Receipt $i.pdf',
                          mimeType: 'application/pdf',
                          bytes: Uint8List.fromList([1, 2, 3]),
                        ),
                      ),
                      actions: const [],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(AccountingRecordList),
        count == 1 ? findsNothing : findsOneWidget,
      );
      expect(find.text('Rows'), count >= 6 ? findsOneWidget : findsNothing);
      expect(
        find.byType(AccountingAttachmentRecordRow),
        findsNWidgets(count.clamp(0, 5)),
      );
      if (count > 1) {
        for (final box in tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        )) {
          if (box.key is ValueKey<String> &&
              (box.key as ValueKey<String>).value.startsWith(
                'attachment-card-',
              )) {
            expect((box.decoration as BoxDecoration).border, isNull);
          }
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
