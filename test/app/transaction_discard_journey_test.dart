import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/transaction_form_layout.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_text_input.dart';
import '../features/accounting/data/quotation_current_revision_test.dart'
    show CurrentQuotationFixture;
import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../support/fixed_popout_host.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

Future<void> prepare(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
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
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> host(
  WidgetTester tester,
  Widget Function(BuildContext) builder,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: builder),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tap(tester, find.text('Open'));
}

void main() {
  for (final width in [720.0, 1224.0]) {
    for (final forced in [false, true]) {
      for (final existing in [false, true]) {
        testWidgets(
          'actual ${existing ? 'saved' : 'new'} Quotation guards edits but accepts opening validity at $width forced=$forced',
          (t) async {
            await prepare(t, width);
            final fixture = CurrentQuotationFixture();
            await fixture.open(converted: existing);
            addTearDown(fixture.close);
            fixture.w.savePreferences(
              fixture.w.preferences.change('Sales Preferences', {
                'Show Quantity': forced,
                'Show Rate': forced,
              }),
            );
            final preferences = fixture.w.preferences.toJson();
            await t.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('workspace-capture'),
                child: MaterialApp(
                  theme: AccountingTheme.light(),
                  home: Scaffold(body: QuotationPage(workspace: fixture.w)),
                ),
              ),
            );
            await t.pumpAndSettle();
            final open = existing
                ? find.byKey(ValueKey('edit-quotation-${fixture.id}'))
                : find.text('Create Quotation');
            final close = find.byKey(const ValueKey('design-close'));
            await tap(t, open);
            await tap(t, close);
            expect(find.text('Discard Unsaved Changes?'), findsNothing);
            expect(find.byType(FrontendFormDialog), findsNothing);
            await tap(t, open);
            await tap(t, find.byKey(const ValueKey('design-add-line')));
            await tap(t, find.byKey(const ValueKey('design-remove-line-1')));
            await tap(t, close);
            expect(find.text('Discard Unsaved Changes?'), findsNothing);
            expect(find.byType(FrontendFormDialog), findsNothing);
            await tap(t, open);
            // Opening a new document reserves its number. Compare all stored
            // rows after that intended allocation, before any user edits.
            final original = tables(fixture.w);
            final memo = find.byKey(const ValueKey('design-field-Memo'));
            await t.ensureVisible(memo);
            await enterAccountingText(t, memo, 'Keep quotation working Memo.');
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pumpAndSettle();
            expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
            await captureUi(
              t,
              'Quotation ${existing ? 'Saved' : 'New'} ${forced ? 'Forced' : 'Default'} Discard Warning ${width.toInt()}',
            );
            await tap(t, find.byKey(const ValueKey('design-keep-editing')));
            expect(
              accountingDescriptionText('Keep quotation working Memo.'),
              findsOneWidget,
            );
            await tap(t, close);
            await tap(t, find.byKey(const ValueKey('design-discard-close')));
            expect(
              accountingDescriptionText('Keep quotation working Memo.'),
              findsOneWidget,
            );
            await tap(t, close);
            await tap(t, find.byKey(const ValueKey('design-discard-changes')));
            expect(find.byType(FrontendFormDialog), findsNothing);
            expect(tables(fixture.w), original);
            expect(fixture.w.preferences.toJson(), preferences);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final width in [720.0, 1224.0]) {
    for (final forced in [false, true]) {
      for (final claim in [false, true]) {
        final name =
            '${claim ? 'Claim' : 'Expense'} ${forced ? 'Forced' : 'Default'}';
        testWidgets('$name preserves unsaved popup work at $width', (t) async {
          await prepare(t, width);
          var saves = 0;
          final preferences = CompanyPreferences.defaults().change(
            'Purchase Preferences',
            {'Show Quantity': forced, 'Show Rate': forced},
          );
          await host(
            t,
            (context) => RecordExpensePage(
              includeTopSafeArea: false,
              preferences: preferences,
              onCancel: () => Navigator.pop(context),
              onSave: claim
                  ? null
                  : (_) async {
                      saves++;
                    },
              claimContext: claim
                  ? RecordExpenseClaimContext(
                      claimantField: const Text('Registered fixture claimant'),
                      saveDraft: (_) async {
                        saves++;
                      },
                      submitForReview: (_) async {
                        saves++;
                      },
                      submissionErrors: (_) => [],
                    )
                  : null,
            ),
          );
          final close = find.byKey(const ValueKey('record-expense-cancel'));
          await tap(t, close);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          expect(find.byType(RecordExpensePage), findsNothing);
          await tap(t, find.text('Open'));
          final memo = find.byKey(const ValueKey('expense-field-notes'));
          await t.ensureVisible(memo);
          await enterAccountingText(t, memo, 'Keep this working Memo.');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('expense-discard-changes')),
            findsOneWidget,
          );
          await captureUi(t, '$name Discard Warning ${width.toInt()}');
          await tap(t, find.byKey(const ValueKey('expense-keep-editing')));
          expect(
            accountingDescriptionText('Keep this working Memo.'),
            findsOneWidget,
          );
          await tap(t, close);
          await tap(t, find.byKey(const ValueKey('expense-discard-close')));
          expect(
            accountingDescriptionText('Keep this working Memo.'),
            findsOneWidget,
          );
          await tap(t, close);
          final size = t.view.physicalSize;
          t.view.physicalSize = Size(size.width, 613);
          await t.pumpAndSettle();
          await captureUi(t, '$name Discard Short Height ${width.toInt()}');
          await tap(t, find.byKey(const ValueKey('expense-keep-editing')));
          expect(
            accountingDescriptionText('Keep this working Memo.'),
            findsOneWidget,
          );
          t.view.physicalSize = size;
          await t.pumpAndSettle();
          await t.tapAt(const Offset(2, 500));
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('expense-discard-changes')),
            findsOneWidget,
          );
          await tap(t, find.byKey(const ValueKey('expense-discard-changes')));
          expect(find.byType(RecordExpensePage), findsNothing);
          expect(saves, 0);
          await tap(t, find.text('Open'));
          expect(
            accountingDescriptionText('Keep this working Memo.'),
            findsNothing,
          );
          await tap(t, close);
          expect(find.byType(RecordExpensePage), findsNothing);
          expect(t.takeException(), isNull);
        });
      }

      testWidgets(
        'actual Bill form guards ordinary and rich edits at $width forced=$forced',
        (t) async {
          await prepare(t, width);
          final fixture = CurrentQuotationFixture();
          await fixture.open();
          addTearDown(fixture.close);
          final preferences = CompanyPreferences.defaults().change(
            'Purchase Preferences',
            {'Show Quantity': forced, 'Show Rate': forced},
          );
          fixture.w.savePreferences(preferences);
          final (vendor, account) = await setupBill(fixture.w);
          final bill = billFixture(
            fixture.w,
            vendor,
            account.account.id,
            attachments: [],
          );
          fixture.w.saveBillDraft(bill, expectedRevision: 0);
          final original = tables(fixture.w);
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(body: BillsPage(workspace: fixture.w)),
              ),
            ),
          );
          await t.pumpAndSettle();
          Future<void> open() =>
              tap(t, find.byKey(ValueKey('edit-bill-${bill.id}')));
          await open();
          expect(find.byType(AccountingTransactionGrid), findsOneWidget);
          expect(
            t.getRect(find.byKey(const ValueKey('design-add-line'))).right,
            lessThanOrEqualTo(t.view.physicalSize.width),
          );
          final close = find.byKey(const ValueKey('design-close'));
          await tap(t, close);
          expect(find.byType(FrontendFormDialog), findsNothing);
          await open();
          final number = find.byKey(
            const ValueKey('design-field-Document Number'),
          );
          await t.ensureVisible(number);
          await enterAccountingText(t, number, 'B-UNSAVED');
          await tap(t, close);
          await tap(t, find.byKey(const ValueKey('design-keep-editing')));
          expect(find.text('B-UNSAVED'), findsOneWidget);
          final memo = find.byKey(const ValueKey('design-field-Memo'));
          await t.ensureVisible(memo);
          await enterAccountingText(t, memo, 'Keep Bill Memo.');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsOneWidget,
          );
          final name = 'Bill ${forced ? 'Forced' : 'Default'}';
          await captureUi(t, '$name Discard Warning ${width.toInt()}');
          await tap(t, find.byKey(const ValueKey('design-discard-close')));
          expect(accountingDescriptionText('Keep Bill Memo.'), findsOneWidget);
          await t.tapAt(const Offset(2, 500));
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsOneWidget,
          );
          await tap(t, find.byKey(const ValueKey('design-discard-changes')));
          expect(tables(fixture.w), original);
          await open();
          expect(find.text(bill.documentNumber), findsOneWidget);
          await tap(t, close);
          expect(find.byType(FrontendFormDialog), findsNothing);
          expect(tables(fixture.w), original);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
