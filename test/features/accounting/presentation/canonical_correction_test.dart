import 'dart:async';
import 'dart:typed_data';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fixed_popout_host.dart';

void main() {
  testWidgets(
    'Home Record Expense action reaches the real Record Expense page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 900));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      installFixedPopoutHost(tester);
      await tester.pumpWidget(const AudytApp());
      await tester.tap(
        find.byKey(const ValueKey('home-record-expense-action')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byType(AccountingCloseIcon), findsOneWidget);
      expect(find.text('Expense'), findsWidgets);
    },
  );

  testWidgets('mounted side-menu callbacks switch Home and Record Expense', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    installFixedPopoutHost(tester);
    await tester.pumpWidget(const AudytApp(initialPath: '/record-expense'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('navigation-item-home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-title-home')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-record-expense-action')));
    await tester.pumpAndSettle();
    expect(find.byType(RecordExpensePage), findsOneWidget);
    expect(find.byType(AccountingCloseIcon), findsOneWidget);
  });

  testWidgets('Cancel returns to Accounting Home from the mounted route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    installFixedPopoutHost(tester);
    await tester.pumpWidget(const AudytApp(initialPath: '/record-expense'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('record-expense-cancel')),
    );
    await tester.tap(find.byKey(const ValueKey('record-expense-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-title-home')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('page-title-record-expense')),
      findsNothing,
    );
  });

  testWidgets('the dropzone updates visible attachment state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1224, 1500));
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
  });

  testWidgets('payment account and category are real selectable controls', (
    tester,
  ) async {
    RecordExpenseDraft? savedDraft;

    await tester.binding.setSurfaceSize(const Size(1224, 1500));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          paymentAccounts: const <String>['Cash'],
          onSave: (draft) async => savedDraft = draft,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('expense-field-amount')),
      '25.50',
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

    expect(savedDraft?.paymentAccount, 'Cash');
    expect(savedDraft?.category, 'Office Operations');
  });

  testWidgets(
    'renders the current Expense card and required date/account labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      expect(
        find.byKey(const ValueKey('record-expense-form-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-transaction-lines')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('record-expense-card-footer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-required-date')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-required-payment-account')),
        findsOneWidget,
      );
      expect(find.text('Drop receipts here or choose files'), findsOneWidget);

      final amountDecoration = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const ValueKey('expense-field-amount')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(amountDecoration.decoration.labelText, isNull);
      expect(amountDecoration.decoration.border, isA<OutlineInputBorder>());
    },
  );

  testWidgets(
    'ready references keep Save enabled and valid save cannot duplicate',
    (tester) async {
      final writeCompleted = Completer<void>();
      var saveCount = 0;

      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: RecordExpensePage(
            paymentAccounts: const <String>['Cash'],
            onSave: (_) {
              saveCount += 1;
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

      final readySave = tester.widget<FilledButton>(
        find.byKey(const ValueKey('record-expense-save')),
      );
      expect(readySave.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('record-expense-save')));
      await tester.pump();

      expect(saveCount, 1);
      expect(find.text('Saving…'), findsOneWidget);

      writeCompleted.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'disables Save when reference data makes a valid record impossible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1500));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: RecordExpensePage(
            categories: <String>[],
            referenceStatus: AccountingReferenceStatus.unavailable,
          ),
        ),
      );

      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('record-expense-save')),
      );
      expect(save.onPressed, isNull);
      expect(find.text('No categories are available.'), findsOneWidget);
    },
  );
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
