import 'dart:async';
import 'dart:typed_data';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retains the form and exposes retry after a save failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          paymentAccounts: const <String>['Cash'],
          onSave: (_) async => throw StateError('local write failed'),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('expense-field-amount')),
      '10.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('expense-field-payee')),
      'Retained payee',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-payment-account'),
      'Cash',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-category'),
      'Office Operations',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-save')));
    await tester.pumpAndSettle();

    expect(
      find.text("Expense couldn't be saved. Your entries are still here."),
      findsOneWidget,
    );
    expect(find.text('Retry Save'), findsOneWidget);
    expect(find.text('Retained payee'), findsOneWidget);
    expect(find.text('10.00'), findsWidgets);
  });

  testWidgets('review waits for current edits to save before opening', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final save = Completer<void>();
    RecordExpenseDraft? saved;
    var reviews = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          paymentAccounts: const ['Cash'],
          onSave: (draft) async {
            saved = draft;
            await save.future;
          },
          onSavedReview: () async {
            reviews++;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('expense-field-amount')),
      '42.00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('expense-field-payee')),
      'Updated Payee',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-payment-account'),
      'Cash',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-category'),
      'Office Operations',
    );
    final review = find.byKey(const ValueKey('expense-save-review'));
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pump();
    expect(saved?.amount, '42.00');
    expect(saved?.payee, 'Updated Payee');
    expect(reviews, 0);
    save.complete();
    await tester.pumpAndSettle();
    expect(reviews, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'posted view retains full fields without save or upload actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1600));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: RecordExpensePage(
            readOnly: true,
            savedDraft: RecordExpenseDraft(
              amount: '12.00',
              date: '13-09-2026',
              payee: 'Recorded Payee',
              paymentAccount: 'Cash',
              category: 'Workspace Rental (Retired)',
              tax: 'No tax',
              customer: '',
              billable: false,
              dimensions: 'Project A',
              itemOrSplitDetails: 'Stationery',
              notes: 'Retained evidence',
            ),
          ),
        ),
      );
      expect(find.text('Expense'), findsWidgets);
      expect(
        find.byKey(const ValueKey('expense-field-amount')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-amount')),
            )
            .controller!
            .text,
        '12.00',
      );
      expect(find.text('Workspace Rental (Retired)'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-expense-save')), findsNothing);
      expect(
        find.byKey(const ValueKey('expense-receipt-dropzone')),
        findsNothing,
      );
      final amount = find.byKey(const ValueKey('expense-field-amount'));
      final blocked = find.ancestor(
        of: amount,
        matching: find.byType(IgnorePointer),
      );
      expect(
        blocked.evaluate().any((e) => (e.widget as IgnorePointer).ignoring),
        isTrue,
      );
      expect(find.byKey(const ValueKey('view-expense-close')), findsNothing);
      expect(find.byKey(const ValueKey('expense-form-close')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows validation errors and focuses the first invalid field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-save')));
    await tester.pump();

    expect(
      find.text('Please correct the highlighted fields before saving.'),
      findsOneWidget,
    );
    expect(find.text('Amount is required.'), findsOneWidget);
    expect(find.text('Payment account is required.'), findsOneWidget);
    expect(find.text('Category is required.'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('expense-field-amount')),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('gates Save and explains unavailable categories', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: RecordExpensePage(
          categories: <String>[],
          referenceStatus: AccountingReferenceStatus.unavailable,
        ),
      ),
    );

    expect(find.text('No categories are available.'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('record-expense-save')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('explains an empty ready category list before submission', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: RecordExpensePage(categories: <String>[])),
    );

    expect(find.text('No categories are available.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('record-expense-save')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('keeps attachment selection visible and actions at 44px', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          onAttachmentsPick: (_) async => <PickedExpenseAttachment>[
            PickedExpenseAttachment(
              name: 'receipt.pdf',
              mimeType: 'application/pdf',
              bytes: Uint8List.fromList(<int>[37, 80, 68, 70]),
            ),
          ],
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('expense-receipt-dropzone')),
    );
    await tester.tap(find.byKey(const ValueKey('expense-receipt-dropzone')));
    await tester.pumpAndSettle();

    expect(find.text('receipt.pdf'), findsWidgets);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('expense-receipt-dropzone')))
          .height,
      greaterThanOrEqualTo(44),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('record-expense-save'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('record-expense-cancel')))
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('uses the shared neutral fill for receipt upload', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

    final surface = find.byKey(const ValueKey('expense-receipt-surface'));
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).height, greaterThanOrEqualTo(128));

    final tokens = AccountingTheme.of(tester.element(surface));
    final background = tester.widget<Container>(
      find.descendant(of: surface, matching: find.byType(Container)),
    );
    final decoration = background.decoration;
    expect(decoration, isA<BoxDecoration>());
    final color = (decoration! as BoxDecoration).color;
    expect(color, isNotNull);
    expect(color, tokens.muted);
  });

  testWidgets('validates amount precision from the selected currency', (
    tester,
  ) async {
    RecordExpenseDraft? savedDraft;

    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          currencyCode: 'JPY',
          paymentAccounts: const <String>['Cash'],
          onSave: (draft) async => savedDraft = draft,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('expense-field-amount')),
      '12.5',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-payment-account'),
      'Cash',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-category'),
      'Office Operations',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-save')));
    await tester.pumpAndSettle();

    expect(find.text('Amount is required.'), findsOneWidget);
    expect(savedDraft, isNull);
  });

  testWidgets('disables duplicate save while the local write is pending', (
    tester,
  ) async {
    final writeCompleted = Completer<void>();
    RecordExpenseDraft? savedDraft;

    await tester.binding.setSurfaceSize(const Size(1224, 1600));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          paymentAccounts: const <String>['Cash'],
          onSave: (draft) {
            savedDraft = draft;
            return writeCompleted.future;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('expense-field-amount')),
      '15.00',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-payment-account'),
      'Cash',
    );
    await _chooseDropdown(
      tester,
      const ValueKey('expense-field-category'),
      'Office Operations',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-save')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-save')));
    await tester.pump();

    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('record-expense-save')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('15.00'), findsWidgets);

    writeCompleted.complete();
    await tester.pumpAndSettle();
    expect(savedDraft?.amount, '15.00');
  });

  testWidgets('keeps category loading explicit and blocks save', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: RecordExpensePage(
          categories: <String>[],
          referenceStatus: AccountingReferenceStatus.loading,
        ),
      ),
    );

    expect(find.text('Loading categories…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('expense-category-loading')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('record-expense-save')),
          )
          .onPressed,
      isNull,
    );
  });
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  Key fieldKey,
  String option,
) async {
  await tester.ensureVisible(find.byKey(fieldKey));
  await tester.tap(find.byKey(fieldKey));
  await tester.pumpAndSettle();
  if (find.textContaining(option).evaluate().isEmpty &&
      find.byKey(fieldKey).evaluate().isNotEmpty) {
    tester.widget<OutlinedButton>(find.byKey(fieldKey)).onPressed?.call();
    await tester.pumpAndSettle();
  }
  final optionFinder = find.textContaining(option).last;
  await tester.ensureVisible(optionFinder);
  await tester.tap(optionFinder);
  await tester.pumpAndSettle();
}
