import 'dart:typed_data';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets(
    'selector menus have no redundant heading and keep selection distinct from hover',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: const <AccountingSelectorOption<String>>[
                AccountingSelectorOption<String>(
                  value: 'alpha',
                  label: 'Alpha',
                  key: ValueKey<String>('correction-alpha'),
                ),
                AccountingSelectorOption<String>(
                  value: 'beta',
                  label: 'Beta',
                  key: ValueKey<String>('correction-beta'),
                ),
              ],
              value: 'alpha',
              onChanged: (_) {},
              hintText: 'Select value',
              triggerKey: const ValueKey<String>('correction-trigger'),
              menuKey: const ValueKey<String>('correction-menu'),
              menuTitle: 'Choose a value',
              menuTitleKey: const ValueKey<String>('correction-heading'),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('correction-trigger')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('correction-heading')),
        findsNothing,
      );
      final selected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey<String>('correction-alpha')),
      );
      final unselected = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey<String>('correction-beta')),
      );
      expect(
        selected.style!.backgroundColor!.resolve(<WidgetState>{}),
        AccountingTokens.light.primary.withValues(alpha: 0.10),
      );
      expect(
        unselected.style!.backgroundColor!.resolve(<WidgetState>{}),
        Colors.transparent,
      );
      expect(selected.leadingIcon, isNull);
    },
  );

  testWidgets('receipt dropzone paints the shared thin foreground dash', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final surface = find.byKey(const ValueKey('expense-receipt-surface'));
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: surface, matching: find.byType(CustomPaint)).first,
    );
    final painter = paint.foregroundPainter as dynamic;
    expect(painter.strokeWidth, closeTo(0.56, 0.01));
  });

  test('date formatter filters input, inserts separators, caps digits, and preserves cursor editing', () {
    const formatter = DateInputFormatter();
    final formatted = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '01022026abc',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    expect(formatted.text, '01-02-2026');
    expect(formatted.selection.isCollapsed, isTrue);
    expect(formatted.selection.baseOffset, formatted.text.length);

    final capped = formatter.formatEditUpdate(
      formatted,
      TextEditingValue(
        text: '010220261234',
        selection: const TextSelection.collapsed(offset: 12),
      ),
    );
    expect(capped.text, '01-02-2026');

    final afterBackspace = formatter.formatEditUpdate(
      formatted,
      const TextEditingValue(
        text: '01-02-202',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    expect(afterBackspace.text, '01-02-202');
    expect(afterBackspace.selection.baseOffset, afterBackspace.text.length);
  });

  testWidgets(
    'Record Expense owns no currency selector and follows the selected account currency',
    (tester) async {
      final usdAccount = PaymentAccount.create(
        id: 'usd-account',
        name: 'USD Account',
        type: PaymentAccountType.bank,
        currencyCode: 'USD',
      );
      RecordExpenseDraft? saved;

      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecordExpensePage(
            accounts: <PaymentAccount>[usdAccount],
            onSave: (draft) async => saved = draft,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('expense-currency-selector')),
        findsNothing,
      );
      expect(find.text('RM · Malaysian Ringgit'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('USD Account').last);
      await tester.tap(find.textContaining('USD Account').last);
      await tester.pumpAndSettle();

      expect(find.text(r'$'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('expense-field-amount')),
        '12.50',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-field-category')),
      );
      await tester.tap(find.byKey(const ValueKey('expense-field-category')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Office Operations').last);
      await tester.tap(find.text('Office Operations').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('record-expense-save')),
      );
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pumpAndSettle();

      expect(saved?.currencyCode, 'USD');
    },
  );

  testWidgets(
    'date field uses dd-mm-yyyy and rejects alphabetic or impossible dates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: RecordExpensePage(paymentAccounts: <String>['Cash']),
        ),
      );

      final date = find.byKey(const ValueKey('expense-field-date'));
      final initial = tester.widget<TextFormField>(date).controller!.text;
      expect(RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(initial), isTrue);

      await tester.enterText(date, '31ab022026');
      expect(tester.widget<TextFormField>(date).controller!.text, '31-02-2026');
      await tester.enterText(date, '31022026');
      await tester.ensureVisible(
        find.byKey(const ValueKey('record-expense-save')),
      );
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pump();
      expect(find.text('Enter a valid local date.'), findsOneWidget);
    },
  );

  test(
    'normalizes the first ordinary lowercase letter without changing the rest',
    () {
      expect(normalizeAccountName('  123 mYBank'), '123 MYBank');
      expect(normalizeAccountName('MYBank'), 'MYBank');
    },
  );

  test('each receipt review item owns independent crop history', () {
    ReceiptAttachment attachment(String id) => ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: id,
        batchId: 'crop-batch',
        filename: '$id.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );
    final queue = ReceiptReviewQueue(<ReceiptAttachment>[
      attachment('one'),
      attachment('two'),
    ]);
    const edit = NormalizedCropRect(
      left: 0.1,
      top: 0.1,
      right: 0.8,
      bottom: 0.8,
    );

    queue.current.cropHistory.apply(edit);
    expect(queue.current.cropHistory.present, edit);
    queue.moveNext();
    expect(queue.current.cropHistory.present, NormalizedCropRect.full);
    queue.movePrevious();
    expect(queue.current.cropHistory.present, edit);
  });

  test('pipeline applies the exact normalized crop to a derivative and preserves original bytes', () async {
    final original = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 100, height: 80)),
    );
    final processed = await const ReceiptDocumentPipeline().process(
      ReceiptAttachmentInput(
        originalId: 'exact-crop',
        batchId: 'exact-crop-batch',
        filename: 'receipt.jpg',
        mimeType: 'image/jpeg',
        bytes: original,
      ),
    );
    const crop = NormalizedCropRect(
      left: 0.1,
      top: 0.2,
      right: 0.8,
      bottom: 0.9,
    );

    final result = await const ReceiptDocumentPipeline().crop(processed, crop);

    expect(result.originalBytes, orderedEquals(processed.originalBytes));
    expect(result.originalSha256, processed.originalSha256);
    expect(
      result.derivativeId,
      matches(RegExp(r'^exact-crop-derivative-crop-[0-9a-f]{64}$')),
    );
    expect(result.derivativeWidth, 70);
    expect(result.derivativeHeight, 56);
    expect(result.derivativeBytes, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
