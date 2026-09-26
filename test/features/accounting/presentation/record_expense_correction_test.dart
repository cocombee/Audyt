import 'dart:typed_data';

import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/domain/expense_category.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets(
    'defaults to MYR, the full catalog, and truthful empty accounts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      expect(find.text('RM'), findsOneWidget);
      expect(find.text('RM · Malaysian Ringgit'), findsNothing);
      expect(find.text('No payment accounts yet'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-add-account')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense-field-payee')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-add-payee')), findsOneWidget);
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('expense-field-category')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a category'), findsNothing);
      for (final category in ExpenseCategoryCatalog.seeded) {
        expect(
          find.byKey(
            ValueKey('expense-category-option-${category.code}'),
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: 'Missing ${category.displayName}',
        );
      }
    },
  );

  testWidgets(
    'mounted desktop Record Expense scroll reaches the receipt dropzone',
    (tester) async {
      const viewport = Size(1366, 768);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const AudytApp(initialPath: '/record-expense'));
      await tester.pumpAndSettle();

      final scroll = find.byKey(const ValueKey('accounting-main-scroll'));
      final dropzone = find.byKey(const ValueKey('expense-receipt-dropzone'));
      expect(scroll, findsOneWidget);
      expect(dropzone, findsOneWidget);

      final initialRect = tester.getRect(dropzone);
      expect(
        initialRect.top,
        greaterThanOrEqualTo(viewport.height),
        reason: 'Receipt should begin below the initial desktop viewport.',
      );

      await tester.drag(scroll, const Offset(0, -1000));
      await tester.pumpAndSettle();

      final scrolledRect = tester.getRect(dropzone);
      expect(scrolledRect.top, lessThan(viewport.height));
      expect(scrolledRect.bottom, greaterThan(0));
      expect(scrolledRect.top, lessThan(initialRect.top));
    },
  );

  testWidgets('filters payees, supports selection, and adds a local payee', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          payees: const <Payee>[
            Payee(id: '1', name: 'Aina Supplies', type: PayeeType.supplier),
            Payee(id: '2', name: 'Badrul Studio', type: PayeeType.other),
          ],
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('expense-field-payee')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('expense-field-payee')),
      'aina',
    );
    await tester.pump();
    expect(find.text('Aina Supplies'), findsWidgets);
    expect(find.text('Badrul Studio'), findsNothing);
    await tester.tap(find.text('Aina Supplies'));
    expect(find.text('Aina Supplies'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('expense-field-payee')),
      'New Vendor',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-add-payee')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payee-name-field')),
      'New Vendor',
    );
    await tester.tap(find.byKey(const ValueKey('payee-create-action')));
    await tester.pumpAndSettle();
    expect(find.text('New Vendor'), findsWidgets);
  });

  testWidgets('uses a real batch row model and exposes local actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 2200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final jpg = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 40, height: 30)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          onAttachmentsPick: (_) async => <PickedExpenseAttachment>[
            PickedExpenseAttachment(
              name: 'receipt.jpg',
              mimeType: 'image/jpeg',
              bytes: jpg,
            ),
            PickedExpenseAttachment(
              name: 'invoice.pdf',
              mimeType: 'application/pdf',
              bytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
            ),
          ],
        ),
      ),
    );

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -1100));
    await tester.pumpAndSettle();
    final dropzone = find
        .byKey(const ValueKey('expense-receipt-dropzone'))
        .first;
    await tester.tap(dropzone);
    await tester.pumpAndSettle();
    expect(find.text('Drop receipts here or choose files'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('receipt-review-filename')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('receipt-review-filename')))
          .data,
      'receipt.jpg',
    );
    expect(find.text('invoice.pdf'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    expect(
      find.byKey(const ValueKey('receipt-review-apply-crop')),
      findsOneWidget,
    );
    expect(find.text('Convert to PDF'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'expense-attachment-remove-',
            ),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('creates an account locally and allows it to be selected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));
    await tester.tap(
      find.byKey(const ValueKey('expense-field-payment-account')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-add-account')));
    await tester.pumpAndSettle();
    await _chooseDropdown(
      tester,
      const ValueKey('payment-account-bank'),
      'Maybank',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment-account-name')),
      'Maybank',
    );
    await tester.tap(find.byKey(const ValueKey('payment-account-create')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Maybank'), findsWidgets);
    expect(find.text('No payment accounts yet'), findsNothing);
  });

  testWidgets(
    'keeps currency in the payment-account workflow and rejects invalid settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      expect(
        find.byKey(const ValueKey('expense-currency-selector')),
        findsNothing,
      );
      expect(find.text('RM'), findsOneWidget);
      expect(find.text('RM · Malaysian Ringgit'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: RecordExpensePage(defaultCurrencyCode: 'US')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid currency'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('record-expense-save')),
            )
            .onPressed,
        isNull,
      );
    },
  );
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  Key fieldKey,
  String option,
) async {
  await tester.tap(find.byKey(fieldKey));
  await tester.pumpAndSettle();
  final optionFinder = find.textContaining(option).last;
  await tester.tap(optionFinder);
  await tester.pumpAndSettle();
}
