import 'dart:io';
import 'dart:math' as math;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/transaction_removal.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/transaction_removal_controls.dart';
import 'package:audyt/features/purchases/presentation/pay_bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/account_reconciliation_test.dart'
    show Fixture;
import '../features/accounting/data/bill_settlement_test.dart'
    show settlementFixture, allocation;
import '../features/accounting/data/transaction_removal_test.dart'
    show fixture, visible;
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;
import 'restored_page_routes_test.dart' show tables;
import 'transaction_removal_journey_test.dart' show openPage;

Finder keyed(String key) => find.byKey(ValueKey(key));

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> host(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder historyFrame() => find
    .descendant(
      of: find.byType(AlertDialog).last,
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.card,
      ),
    )
    .first;

void checkWidth(WidgetTester tester, double width, {required bool empty}) {
  final preferred =
      (empty
          ? AccountingPopoutTokens.dialogContentWidth
          : AccountingPopoutTokens.widerContentWidth) +
      AccountingPopoutTokens.contentInset * 2;
  expect(
    tester.getSize(historyFrame()).width,
    closeTo(
      math.min(
        preferred,
        width - AccountingPopoutTokens.windowInsets.horizontal,
      ),
      .01,
    ),
  );
  expect(tester.takeException(), isNull);
}

Future<void> statementHistory(WidgetTester tester, String statement) async {
  await tap(tester, keyed('document-more-$statement'));
  await tap(tester, find.text('Reconciliation History'));
}

void main() {
  setUp(AccountingRecordPageSizes.reset);
  tearDown(AccountingRecordPageSizes.reset);
  for (final width in [720.0, 1162.0, 1224.0]) {
    Future<void> prepare(WidgetTester tester) async {
      tester.view.physicalSize = Size(width, 809);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadJournalLayoutFonts();
    }

    testWidgets(
      'empty account/statement/match histories fit without writes at $width',
      (tester) async {
        await prepare(tester);
        final w = await createDemoWorkspace(asOf: DateTime(2026, 10, 9));
        addTearDown(w.dispose);
        final before = tables(w);
        final statement = w.database
            .bankStatements(w.identity.businessId, 'demo-bank')
            .singleWhere((item) => item.filename == 'Demo Bank.csv');
        await host(tester, BankingPage(workspace: w, compact: true));
        await tap(tester, keyed('imported-account-more'));
        await tap(tester, find.text('Reconciliation History'));
        expect(find.text('No reconciliation approvals yet.'), findsOneWidget);
        checkWidth(tester, width, empty: true);
        await captureUi(
          tester,
          'Empty Account Reconciliation History ${width.toInt()}',
        );
        await tap(tester, accountingCloseIcon().last);
        await statementHistory(tester, statement.id.value);
        expect(find.text('No reconciliation approvals yet.'), findsOneWidget);
        checkWidth(tester, width, empty: true);
        await captureUi(
          tester,
          'Empty Statement Reconciliation History ${width.toInt()}',
        );
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, keyed('statement-history-${statement.id.value}'));
        expect(find.text('No matches accepted yet.'), findsOneWidget);
        checkWidth(tester, width, empty: true);
        await captureUi(tester, 'Empty Match History ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        expect(tables(w), before);
        expect(keyed('document-more-${statement.id.value}'), findsOneWidget);
      },
    );

    testWidgets(
      'populated histories retain evidence and Custom width at $width',
      (tester) async {
        await prepare(tester);
        final f = Fixture();
        await f.open();
        await f.post(8, 31, 10000);
        final journal = await f.post(9, 2, -1000);
        final completion = await f.approveImportedSeptember(journal);
        final statement = f.w.database
            .bankStatements(f.business, 'bank')
            .single;
        final before = tables(f.w);
        await host(tester, BankingPage(workspace: f.w, compact: true));
        await tap(tester, keyed('imported-account-more'));
        await tap(tester, find.text('Reconciliation History'));
        expect(keyed('reconciliation-evidence-$completion'), findsOneWidget);
        expect(keyed('reopen-reconciliation-$completion'), findsOneWidget);
        checkWidth(tester, width, empty: false);
        await captureUi(
          tester,
          'Populated Account Reconciliation History ${width.toInt()}',
        );
        await tap(tester, accountingCloseIcon().last);
        await statementHistory(tester, statement.id.value);
        expect(keyed('reconciliation-evidence-$completion'), findsOneWidget);
        checkWidth(tester, width, empty: false);
        await captureUi(
          tester,
          'Populated Statement Reconciliation History ${width.toInt()}',
        );
        await tap(tester, accountingCloseIcon().last);
        await tap(tester, keyed('statement-history-${statement.id.value}'));
        expect(find.textContaining('Statement Row 2'), findsOneWidget);
        expect(find.textContaining(journal.value), findsOneWidget);
        checkWidth(tester, width, empty: false);
        await captureUi(tester, 'Populated Match History ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        expect(tables(f.w), before);
      },
    );

    testWidgets(
      'Bill Payments empty/populated callers retain amounts at $width',
      (tester) async {
        await prepare(tester);
        final root = Directory.systemTemp.createTempSync('empty-bill-history-');
        addTearDown(() => root.deleteSync(recursive: true));
        final (w, ids, _, _) = await settlementFixture(
          '${root.path}/ledger.sqlite',
        );
        addTearDown(w.dispose);
        await host(tester, PayBillsPage(workspace: w));
        final before = tables(w);
        await tap(tester, keyed('pay-bill-history-${ids.first}'));
        expect(
          find.text('No payments recorded for this bill.'),
          findsOneWidget,
        );
        checkWidth(tester, width, empty: true);
        await captureUi(tester, 'Empty Bill Payments ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        expect(tables(w), before);
        // Seed an isolated existing payment command, then inspect its real caller.
        w.settleRecognizedBills(
          requestId: EntityId.random(),
          allocations: [allocation(ids.first, 15120, 120)],
          paymentAccountId: 'fictional-bank',
          paymentReference: 'Fictional history payment',
          paidOn: DateTime.utc(2026, 9, 28),
          approvedAt: DateTime.utc(2026, 9, 28, 2),
        );
        await tester.pumpAndSettle();
        final paid = tables(w);
        await tap(tester, keyed('pay-bill-history-${ids.first}'));
        expect(find.text('Fictional history payment'), findsOneWidget);
        expect(find.text('RM 1.20'), findsOneWidget);
        checkWidth(tester, width, empty: false);
        await captureUi(tester, 'Populated Bill Payments ${width.toInt()}');
        await tap(tester, accountingCloseIcon().last);
        expect(tables(w), paid);
      },
    );

    for (final kind in TransactionRecordKind.values) {
      testWidgets(
        '${kind.name} final restore shrinks only its empty list at $width',
        (tester) async {
          await prepare(tester);
          final f = await fixture(kind, pending: true);
          final reviewed = f.w.reviewTransactionRemoval(kind, f.id);
          f.w.setTransactionRemoved(
            reviewed: reviewed,
            removed: true,
            changedAt: DateTime.utc(2026, 10, 9),
          );
          await openPage(tester, f.w, kind);
          final removed = tables(f.w);
          await tap(tester, keyed('removed-${kind.name}-open'));
          checkWidth(tester, width, empty: false);
          expect(tables(f.w), removed);
          if (kind == TransactionRecordKind.invoiceCredit) {
            await captureUi(
              tester,
              'Populated Removed Credits ${width.toInt()}',
            );
          }
          await tap(tester, keyed('removed-restore-${f.id}'));
          await tap(tester, keyed('transaction-confirm-removal'));
          expect(visible(f.w, kind, f.id), isTrue);
          expect(f.w.removedTransactionPage(kind).total, 0);
          expect(
            find.text('No Removed ${removalFamilyLabel(kind, plural: true)}'),
            findsOneWidget,
          );
          checkWidth(tester, width, empty: true);
          if (kind == TransactionRecordKind.invoiceCredit) {
            await captureUi(tester, 'Empty Removed Credits ${width.toInt()}');
          }
          final restored = tables(f.w);
          for (final table in removed.keys.where(
            (t) => !{
              'transaction_record_removals',
              'ledger_audit',
              'sqlite_sequence',
            }.contains(t),
          )) {
            expect(
              restored[table],
              removed[table],
              reason: '${kind.name}: $table',
            );
          }
          await tap(tester, accountingCloseIcon().last);
          expect(keyed('removed-${kind.name}-open'), findsNothing);
          expect(tables(f.w), restored);
        },
      );
    }
  }
}
