import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show capture;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String text) async {
  await _tap(tester, find.byKey(ValueKey(key)));
  await _tap(tester, find.text(text).last);
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'Home opens the live Expense layout, saves lines and reopens at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        for (final font in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
        }
        final directory = Directory.systemTemp.createTempSync(
          'live-expense-owner-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final path = '${directory.path}/ledger.sqlite';
        var workspace = await createDemoWorkspace(
          databasePath: path,
          asOf: DateTime(2026, 9, 30),
        );
        workspace.savePreferences(
          workspace.preferences.change('Purchase Preferences', {
            'Show Rate': true,
          }),
        );
        final journals = (await workspace.journals()).length;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: workspace, showInitialSetup: false),
          ),
        );
        await tester.pumpAndSettle();
        final record = find.byKey(const ValueKey('record-expense-primary'));
        final fallback = find.byKey(
          const ValueKey('home-record-expense-action'),
        );
        await _tap(tester, record.evaluate().isNotEmpty ? record : fallback);
        expect(
          find.byKey(const ValueKey('expense-live-dialog')),
          findsOneWidget,
        );
        expect(find.text('Expense Details'), findsNothing);
        expect(
          tester
              .widget<AccountingMemoSummary>(find.byType(AccountingMemoSummary))
              .rows,
          [('Subtotal', '0.00'), ('Tax', '0.00'), ('Total (RM)', '0.00')],
        );
        expect(find.text('—'), findsNothing);
        final method = find.byKey(
          const ValueKey('expense-field-payment-method'),
        );
        expect(method, findsOneWidget);
        final methodSelector = tester.widget<AccountingSelector<String>>(
          find.ancestor(
            of: method,
            matching: find.byType(AccountingSelector<String>),
          ),
        );
        expect(methodSelector.value, isNull);
        expect(methodSelector.options.single.label, 'Add Payment Method');
        await capture(tester, 'Expense Payment Method Header ${width.toInt()}');
        await _tap(tester, method);
        await capture(tester, 'Expense Payment Method Menu ${width.toInt()}');
        await _tap(
          tester,
          find.byKey(const ValueKey('expense-add-payment-method')),
        );
        expect(find.text('New Payment Method'), findsOneWidget);
        expect(
          tester
              .widget<Checkbox>(
                find.byKey(
                  const ValueKey('design-field-This Is A Credit Card'),
                ),
              )
              .value,
          isFalse,
        );
        await capture(tester, 'Expense Inline Payment Method ${width.toInt()}');
        await _tap(tester, accountingCloseIcon().last);
        expect(find.text('New Payment Method'), findsNothing);
        expect(
          find.byKey(const ValueKey('expense-live-dialog')),
          findsOneWidget,
        );
        final taxHeader = find.byKey(const ValueKey('expense-tax-treatment'));
        final taxContext = tester.element(taxHeader);
        expect(
          tester.getSize(taxHeader).width,
          greaterThanOrEqualTo(
            accountingSelectorMinimumWidth(taxContext, [
              'Tax Exclusive',
              'Tax Inclusive',
            ]),
          ),
          reason: 'Ordinary tax header keeps its full one-line label.',
        );
        expect(
          find.text('Record the payment details and supporting receipt.'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('expense-transaction-lines')),
          findsOneWidget,
        );
        final payee = tester.getRect(
          find.byKey(const ValueKey('expense-field-payee')),
        );
        final number = tester.getRect(
          find.byKey(const ValueKey('expense-document-number')),
        );
        final date = tester.getRect(
          find.byKey(const ValueKey('expense-field-date')),
        );
        final account = tester.getRect(
          find.byKey(const ValueKey('expense-field-payment-account')),
        );
        expect(payee.top, closeTo(number.top, .1));
        expect(date.top, closeTo(account.top, .1));
        expect(payee.top, lessThan(date.top));
        expect(
          tester.getRect(find.text('Quantity')).right,
          lessThan(tester.getRect(find.text('Rate (RM)')).left),
          reason: 'Compact numeric headings must not collide.',
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('expense-transaction-lines')))
              .top,
          greaterThan(date.bottom),
        );
        await capture(tester, 'Expense Live Popout ${width.toInt()}');
        final longDescription =
            '1. ${List.filled(18, 'A long retained description with wrapped details').join(' ')}\n2. Delivery';
        await tester.enterText(
          find.byKey(const ValueKey('expense-field-payee')),
          'Layout Review Supplier',
        );
        await tester.enterText(
          find.byKey(const ValueKey('expense-document-number')),
          'EXP-LIVE-REVIEW',
        );
        await _choose(
          tester,
          'expense-field-payment-account',
          workspace.paymentAccounts.first.displayLabel,
        );
        await _choose(tester, 'expense-field-category', 'Office Operations');
        await _choose(tester, 'expense-tax-treatment', 'Tax Exclusive');
        final description = find.byKey(
          const ValueKey('expense-field-item-or-split'),
        );
        final firstHeight = tester.getSize(description).height;
        await enterAccountingText(tester, description, longDescription);
        await tester.pumpAndSettle();
        expect(tester.getSize(description).height, greaterThan(firstHeight));
        expect(
          tester.widget<AccountingDescriptionField>(description).fixedLines,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('expense-line-0-quantity')),
          '4',
        );
        await tester.enterText(
          find.byKey(const ValueKey('expense-line-0-rate')),
          '2',
        );
        await tester.pumpAndSettle();
        TextEditingController amount() => tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-amount')),
            )
            .controller!;
        expect(amount().text, '8.00');
        await tester.enterText(
          find.byKey(const ValueKey('expense-line-0-quantity')),
          '3',
        );
        await tester.enterText(
          find.byKey(const ValueKey('expense-field-amount')),
          '10',
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('expense-line-0-rate')),
              )
              .controller!
              .text,
          '3.34',
        );
        expect(amount().text, '10');
        await tester.enterText(
          find.byKey(const ValueKey('expense-line-0-rate')),
          '3.3',
        );
        await tester.pumpAndSettle();
        expect(amount().text, '9.90');
        await _tap(tester, find.byKey(const ValueKey('expense-add-line')));
        await _choose(tester, 'expense-line-1-category', 'Business Travel');
        await tester.enterText(
          find.byKey(const ValueKey('expense-line-1-rate')),
          '2',
        );
        await tester.pumpAndSettle();
        // Every vertically corresponding numeric box uses one measured width.
        expect(
          tester
              .getSize(find.byKey(const ValueKey('expense-field-amount')))
              .width,
          closeTo(
            tester
                .getSize(find.byKey(const ValueKey('expense-line-1-amount')))
                .width,
            .1,
          ),
        );
        final memo = find.byKey(const ValueKey('expense-field-notes'));
        final memoHeight = tester.getSize(memo).height;
        await enterAccountingText(
          tester,
          memo,
          List.filled(20, 'a. Retained memo').join('\n'),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(memo).height, memoHeight);
        await capture(tester, 'Expense Live Form ${width.toInt()}');
        await _tap(tester, find.text('Advanced Accounting Details'));
        final treatment = find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSelector<String> &&
              widget.hintText == 'Select Purchase Treatment',
        );
        await tester.ensureVisible(treatment);
        await tester.pumpAndSettle();
        final assetFields = find.ancestor(
          of: treatment,
          matching: find.byType(AccountingOrdinaryFields),
        );
        expect(assetFields, findsOneWidget);
        expect(
          tester.getSize(treatment).width,
          greaterThanOrEqualTo((tester.getSize(assetFields).width - 20) / 2),
        );
        expect(tester.takeException(), isNull);
        await capture(tester, 'Expense Advanced Forced ${width.toInt()}');
        await _tap(tester, find.text('Advanced Accounting Details'));
        await _tap(tester, find.byKey(const ValueKey('record-expense-save')));
        final saved = (await workspace.expenses()).singleWhere(
          (record) => record.payee == 'Layout Review Supplier',
        );
        final draft = (await workspace.expense(saved.id))!.draft;
        expect(draft.documentNumber, 'EXP-LIVE-REVIEW');
        expect(draft.lines, hasLength(2));
        expect(draft.lines.first.description, longDescription);
        expect(draft.amount, '11.90');
        expect((await workspace.journals()).length, journals);
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        workspace = await AccountingWorkspace.open(path);
        addTearDown(workspace.dispose);
        final reopened = (await workspace.expense(saved.id))!.draft;
        expect(reopened.toJson(), draft.toJson());
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: RecordExpensePage(
              savedDraft: reopened,
              accounts: workspace.paymentAccounts,
              settingsWorkspace: workspace,
              includeTopSafeArea: false,
              onCancel: () {},
              onSave: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('expense-live-dialog')),
          findsOneWidget,
        );
        expect(find.byType(AccountingDescriptionField), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final (currency, zero) in [
    ('MYR', '0.00'),
    ('JPY', '0'),
    ('KWD', '0.000'),
  ]) {
    testWidgets(
      'empty transaction money hints retain blank values for $currency',
      (tester) async {
        tester.view.physicalSize = const Size(1224, 1700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        installFixedPopoutHost(tester);
        var cancelled = false;
        for (final font in [
          ('Inter', 'assets/fonts/Inter-Variable.woff2'),
          ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
        ]) {
          await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
        }
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: RecordExpensePage(
                currencyCode: currency,
                preferences: CompanyPreferences.defaults().change(
                  'Purchase Preferences',
                  {'Show Rate': true},
                ),
                includeTopSafeArea: false,
                onCancel: () => cancelled = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        TextFormField input(String key) =>
            tester.widget<TextFormField>(find.byKey(ValueKey(key)));
        InputDecoration decoration(String key) => tester
            .widget<InputDecorator>(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(InputDecorator),
              ),
            )
            .decoration;
        for (final key in ['expense-field-amount', 'expense-line-0-rate']) {
          expect(decoration(key).hintText, zero);
          expect(input(key).controller!.text, isEmpty);
          final hint = find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text(zero),
          );
          expect(hint, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(hint).didExceedMaxLines,
            isFalse,
          );
        }
        expect(decoration('expense-line-0-quantity').hintText, isNull);
        expect(input('expense-line-0-quantity').controller!.text, '1');
        await _tap(tester, find.byKey(const ValueKey('expense-add-line')));
        for (final key in ['expense-line-1-amount', 'expense-line-1-rate']) {
          expect(decoration(key).hintText, zero);
          expect(input(key).controller!.text, isEmpty);
          final hint = find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text(zero),
          );
          expect(hint, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(hint).didExceedMaxLines,
            isFalse,
          );
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('expense-line-1-amount')),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'Expense Money Zero Hints $currency 1224');
        await _tap(tester, find.byKey(const ValueKey('expense-remove-line-1')));
        tester.state<FormState>(find.byType(Form).first).validate();
        await tester.pumpAndSettle();
        expect(find.text('Amount is required.'), findsOneWidget);
        expect(input('expense-field-amount').controller!.text, isEmpty);
        await _tap(tester, find.bySemanticsLabel('Close').last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(cancelled, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: RecordExpensePage(
              key: ValueKey('historical-view-$currency'),
              currencyCode: currency,
              preferences: CompanyPreferences.defaults().change(
                'Purchase Preferences',
                {'Show Rate': true},
              ),
              includeTopSafeArea: false,
              readOnly: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in ['expense-field-amount', 'expense-line-0-rate']) {
          expect(input(key).enabled, isFalse);
          expect(decoration(key).hintText, isNull);
          expect(input(key).controller!.text, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
