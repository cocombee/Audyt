import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    testWidgets('restored voucher saved-source journey at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 809);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final root = Directory.systemTemp.createTempSync('audyt-voucher-source-');
      addTearDown(() => root.deleteSync(recursive: true));
      final originalPath = '${root.path}/original.sqlite';
      final original = await createDemoWorkspace(databasePath: originalPath);
      final expense = (await original.expenses()).singleWhere(
        (e) => e.payee == 'Studio Supplies',
      );
      final originalDraft = (await original.expense(expense.id))!.draft;
      // Ten actual saved sources exercise the shared searchable selector.
      for (var i = 0; i < 4; i++) {
        await original.saveExpenseIntake(
          RecordExpenseDraft.fromJson({
            ...originalDraft.toJson(),
            'submissionId': 'source-search-fixture-$i',
            'payee': 'Fictional Source $i',
            'attachments': <dynamic>[],
          }),
        );
      }
      // Simulate an older archive's legitimate historical unsupported source.
      final historical = PaymentVoucher.fromJson({
        ...PaymentVoucherStore.demo().all.last.toJson(),
        'id': 'retained-bill-reference',
      });
      final legacyDatabase = sqlite3.open(originalPath);
      legacyDatabase.execute(
        'INSERT INTO payment_vouchers(business_id,id,payload) VALUES(?,?,?)',
        [
          original.identity.businessId.value,
          historical.id,
          jsonEncode(historical.toJson()),
        ],
      );
      legacyDatabase.dispose();
      final initial = tables(original);
      final archive = original.database.exportDataArchive(
        original.identity.businessId,
        DateTime.now(),
      );
      original.dispose();
      final originalBytes = File(originalPath).readAsBytesSync();
      final path = '${root.path}/restored.sqlite';
      var w = await AccountingWorkspace.emptyRestore(path, archive);
      addTearDown(() => w.dispose());
      expect(tables(w), initial);
      final restoredDraft = (await w.expense(expense.id))!.draft;
      final originalVoucherIds = w.vouchers.all.map((v) => v.id).toSet();
      Future<void> tap(Finder f) async {
        if (f.hitTestable().evaluate().isEmpty) await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      Future<void> enter(String key, String value) async {
        final f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.enterText(f, value);
        await tester.pumpAndSettle();
      }

      Future<void> capture(String state) async {
        if (find.byType(PaymentVoucherEditorDialog).evaluate().isNotEmpty) {
          final frame = find
              .descendant(
                of: find.byKey(const ValueKey('payment-voucher-editor-dialog')),
                matching: find.byWidgetPredicate(
                  (v) => v is Material && v.type == MaterialType.card,
                ),
              )
              .first;
          final rect = tester.getRect(frame);
          expect(
            rect.width,
            closeTo(
              math.min(
                AccountingPopoutTokens.widerContentWidth +
                    AccountingPopoutTokens.contentInset * 2,
                width - AccountingPopoutTokens.windowInsets.horizontal,
              ),
              .01,
            ),
          );
          expect(
            rect.left,
            greaterThanOrEqualTo(AccountingPopoutTokens.windowInsets.left),
          );
          expect(
            rect.right,
            lessThanOrEqualTo(
              width - AccountingPopoutTokens.windowInsets.right,
            ),
          );
        }
        await captureUi(tester, 'Voucher Source $state ${width.toInt()}');
      }

      Future<void> page() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: w, showInitialSetup: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(
          find.byKey(const ValueKey('navigation-item-expenses-vendors')),
        );
        await tap(find.text('Payment Vouchers').first);
      }

      Future<void> choose() async {
        await tap(find.byKey(const ValueKey('voucher-source-selector')));
        final search = find.descendant(
          of: find.byKey(const ValueKey('voucher-source-control')),
          matching: find.byType(TextField),
        );
        expect(search, findsOneWidget);
        expect(
          find.byKey(const ValueKey('voucher-source-menu')),
          findsOneWidget,
        );
        await tester.enterText(search, 'Studio');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('voucher-source-menu')),
          findsOneWidget,
        );
        await capture('Search');
        expect(
          find.textContaining('Fictional Source').hitTestable(),
          findsNothing,
        );
        await tap(find.textContaining('Studio Supplies ·').hitTestable().first);
      }

      final save = find.byKey(const ValueKey('voucher-save-draft'));
      final cancel = find.bySemanticsLabel('Close').last;
      await page();
      await tap(find.byKey(const ValueKey('payment-voucher-first-filter')));
      await tap(find.text('Cerah Internet Sdn Bhd').hitTestable().last);
      await tap(find.byKey(ValueKey('voucher-view-${historical.id}')));
      expect(find.text('Bill Settlement'), findsOneWidget);
      expect(
        find.textContaining('Retained source: ${historical.sourceId}.'),
        findsOneWidget,
      );
      expect(save, findsNothing);
      expect(find.byKey(const ValueKey('voucher-submit')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('voucher-account')),
          matching: find.textContaining(historical.paymentAccount),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (v) =>
              v is ButtonStyleButton &&
              v.key == const ValueKey('voucher-save-current') &&
              v.onPressed == null,
        ),
        findsOneWidget,
      );
      await capture('Historical Unavailable Source');
      await tap(
        find
            .ancestor(
              of: accountingCloseIcon(),
              matching: find.byType(IconButton),
            )
            .last,
      );
      expect(tables(w), initial);
      await tap(find.byKey(const ValueKey('payment-voucher-clear-filters')));
      await tap(find.text('New Voucher'));
      final typeRect = tester.getRect(
        find.byKey(const ValueKey('voucher-source-type-control')),
      );
      final sourceRect = tester.getRect(
        find.byKey(const ValueKey('voucher-source-control')),
      );
      if (width >= 1162) {
        expect(typeRect.top, closeTo(sourceRect.top, .01));
      } else {
        expect(sourceRect.top, greaterThan(typeRect.top));
      }
      await capture('Wider Initial Fields');
      expect(find.byKey(const ValueKey('voucher-source-id')), findsNothing);
      await tap(find.byKey(const ValueKey('voucher-source-type')));
      expect(find.text('Bill Settlement').hitTestable(), findsNothing);
      await tap(find.text('Direct Expense').hitTestable().last);
      await choose();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('voucher-payee')))
            .controller!
            .text,
        expense.payee,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('voucher-amount')))
            .controller!
            .text,
        '320.00',
      );
      await capture('Selected');
      await tap(cancel);
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await capture('Discard Warning');
      await tap(find.byKey(const ValueKey('voucher-discard-changes')));
      expect(tables(w), initial);

      await tap(find.text('New Voucher'));
      await choose();
      await tap(find.byKey(const ValueKey('voucher-method')));
      await tap(find.text('Bank Transfer').hitTestable().last);
      await enter('voucher-reference', 'SOURCE JOURNEY');
      await enter('voucher-amount', '999.99');
      await tap(save);
      expect(
        find.byKey(const ValueKey('voucher-editor-error')),
        findsOneWidget,
      );
      expect(tables(w), initial);
      await capture('Mismatch Rejected');
      await enter('voucher-amount', '320.00');
      await tap(save);
      expect(find.byType(PaymentVoucherEditorDialog), findsNothing);
      final saved = w.vouchers.all.singleWhere(
        (v) => !originalVoucherIds.contains(v.id),
      );
      expect(saved.sourceId, expense.id.value);
      expect(saved.payee, expense.payee);
      expect(saved.amount, expense.amount);
      expect(saved.paymentAccountId, 'demo-bank');
      expect(
        (
          saved.paymentDate.year,
          saved.paymentDate.month,
          saved.paymentDate.day,
        ),
        (
          expense.occurredOn.year,
          expense.occurredOn.month,
          expense.occurredOn.day,
        ),
      );
      final savedTables = tables(w);
      for (final table in initial.keys.where(
        (key) => key != 'payment_vouchers',
      )) {
        expect(savedTables[table], initial[table], reason: table);
      }
      await capture('Saved');
      await tap(find.byKey(const ValueKey('payment-voucher-filter')));
      await tap(find.text('Draft').hitTestable().last);
      await tap(find.byKey(const ValueKey('payment-voucher-first-filter')));
      await tap(find.text('Studio Supplies').hitTestable().last);
      await tap(find.byKey(ValueKey('voucher-view-${saved.id}')));
      await w.updateExpenseIntake(
        id: expense.id,
        expected: restoredDraft,
        replacement: RecordExpenseDraft.fromJson({
          ...restoredDraft.toJson(),
          'amount': '325.00',
        }),
      );
      final updatedTables = tables(w);
      await enter('voucher-reference', 'STALE SOURCE ATTEMPT');
      await tap(save);
      expect(
        find.byKey(const ValueKey('voucher-editor-error')),
        findsOneWidget,
      );
      expect(tables(w), updatedTables);
      await capture('Stale Source Rejected');
      await tap(cancel);
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await capture('Saved Edit Discard Warning');
      await tap(find.byKey(const ValueKey('voucher-discard-changes')));
      await tap(find.byKey(ValueKey('voucher-view-${saved.id}')));
      await choose();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('voucher-amount')))
            .controller!
            .text,
        '325.00',
      );
      await capture('Refreshed Source');
      await tap(save);
      final finalTables = tables(w);
      await tap(find.byKey(const ValueKey('navigation-item-banking')));
      final statement = w.database
          .bankStatements(w.identity.businessId, 'demo-bank')
          .singleWhere((s) => s.filename == 'Demo Bank.csv');
      await tap(
        find.byKey(ValueKey('statement-matches-${statement.id.value}')),
      );
      await tap(find.byKey(const ValueKey('missing-payment-voucher-3')));
      final bankEditor = tester.widget<PaymentVoucherEditorDialog>(
        find.byType(PaymentVoucherEditorDialog),
      );
      expect(bankEditor.sources, isNotEmpty);
      expect(
        bankEditor.sources!.every(
          (s) =>
              s.paymentAccountId == 'demo-bank' &&
              s.amount.minorUnits == 18500 &&
              s.amount.currency == 'MYR',
        ),
        isTrue,
      );
      await tap(find.byKey(const ValueKey('voucher-source-selector')));
      await capture('Bank Source Choices');
      await tap(
        find.textContaining('Northwind Office Supplies ·').hitTestable().first,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('voucher-payee')))
            .controller!
            .text,
        'Northwind Office Supplies',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('voucher-amount')))
            .controller!
            .text,
        '185.00',
      );
      await capture('Bank Source Selected');
      await tap(cancel);
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await tap(find.byKey(const ValueKey('voucher-discard-changes')));
      expect(tables(w), finalTables);
      await tester.pumpWidget(const SizedBox.shrink());
      w.dispose();
      w = await AccountingWorkspace.open(path);
      expect(tables(w), finalTables);
      expect(w.vouchers.byId(saved.id)!.amount.minorUnits, 32500);
      expect(File(originalPath).readAsBytesSync(), originalBytes);
      expect(tester.takeException(), isNull);
    });
  }
}
