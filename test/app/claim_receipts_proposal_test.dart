import 'dart:io';
import 'dart:convert';

import 'package:audyt/app/naming_setup.dart';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_tax_rate.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:audyt/features/purchases/presentation/claim_receipts_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../support/receipt_editor_actions.dart';
import '../support/fixed_popout_host.dart';
import '../support/accounting_text_input.dart';

import '../features/accounting/data/claim_receipt_tax_test.dart' show Fixture;
import 'journal_workspace_integration_test.dart' show captureUi;

Future<Fixture> fixture({String path = ':memory:'}) async {
  final w = await AccountingWorkspace.open(path);
  final ids = <String, EntityId>{};
  for (final (code, name, type) in [
    ('1000', 'Cash', AccountType.asset),
    ('1500', 'Equipment', AccountType.asset),
    ('2100', 'Claims Payable', AccountType.liability),
    ('2200', 'Tax Payable', AccountType.liability),
    ('5000', 'Business Services', AccountType.expense),
    ('5100', 'Printing', AccountType.expense),
  ]) {
    await w.createAccount(code: code, name: name, type: type);
    ids[code] = (await w.accounts())
        .singleWhere((a) => a.account.code == code)
        .account
        .id;
  }
  final rate = w.saveTaxRate(
    CompanyTaxRate(
      id: EntityId.random(),
      name: 'Service Tax',
      percent: '8',
      application: TaxApplication.purchases,
      effectiveFrom: DateTime.utc(2026),
      accountId: ids['2200']!,
    ),
  );
  return Fixture(w, ids, rate);
}

Finder keyed(String key) => find.byKey(ValueKey(key));
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> prepare(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> host(WidgetTester tester, AccountingWorkspace w) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ClaimsPage(
            store: w.claims,
            workspace: w,
            receiptTaxProposal: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final shadows = debugDisableShadows;
  try {
    debugDisableShadows = false;
    for (final o in tester.allRenderObjects) {
      o.markNeedsPaint();
    }
    await tester.pump();
    await captureUi(tester, name);
  } finally {
    debugDisableShadows = shadows;
  }
}

void main() {
  testWidgets('read-only receipt Claim retains shared original View access', (
    tester,
  ) async {
    await prepare(tester, 720);
    final f = await fixture();
    addTearDown(f.w.dispose);
    final original = f.claim();
    final facts = original.toJson();
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ClaimEditorDialog(
            id: original.id,
            initial: original,
            readOnly: true,
            receiptTaxProposal: true,
            receiptAccounts: (await f.w.accounts())
                .map((a) => a.account)
                .toList(),
            receiptTaxCodes: f.w.taxRates,
            onSaveDraft: (_) => fail('Read-only Claim must not save'),
            onSubmit: (_) => fail('Read-only Claim must not submit'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(keyed('claim-save-draft'), findsNothing);
    expect(keyed('claim-submit'), findsNothing);
    for (final receipt in original.receipts) {
      for (final line in receipt.lines) {
        expect(keyed('receipt-action-${line.item.id}'), findsNothing);
      }
    }
    await tap(
      tester,
      keyed('claim-attachment-view-${original.attachments.single.originalId}'),
    );
    expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
    await tap(
      tester,
      find
          .byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Close',
          )
          .last,
    );
    expect(find.byType(AttachmentPreviewDialog), findsNothing);
    expect(original.toJson(), facts);
    expect(tester.takeException(), isNull);
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'current Expense-based Claim edits mixed bases and approval posts multiple accounts at $width',
      (tester) async {
        await prepare(tester, width);
        final dir = Directory.systemTemp.createTempSync(
          'audyt-receipt-proposal-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        final f = await fixture(path: path);
        var w = f.w;
        addTearDown(() => w.dispose());
        final original = f.claim();
        w.claims.saveDraft(original);
        installFixedPopoutHost(tester);
        await host(tester, w);
        await tap(tester, keyed('claim-edit-${original.id}'));
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(keyed('claim-amount'), findsNothing);
        final shown = tester
            .widget<RecordExpensePage>(find.byType(RecordExpensePage))
            .savedDraft!;
        expect(shown.taxTotals!.total, original.amount);
        expect(shown.lines.length, 3);
        expect(shown.receiptLineBases, {
          'receipt-a-taxed': 'Exclusive',
          'receipt-a-asset': 'Exclusive',
          'receipt-b-taxed': 'Inclusive',
        });
        final amount = keyed('expense-field-amount');
        final input = tester.widget<TextFormField>(amount);
        expect(
          Money.fromDecimal(input.controller!.text, 'MYR'),
          Money.fromDecimal('100', 'MYR'),
        );
        expect(input.enabled, isTrue);
        final decoration = tester
            .widget<TextField>(
              find.descendant(of: amount, matching: find.byType(TextField)),
            )
            .decoration!;
        expect(decoration.prefix, isNull);
        expect(decoration.prefixText, isNull);
        expect(decoration.prefixIcon, isNull);
        expect(keyed('expense-add-line'), findsOneWidget);
        expect(keyed('expense-remove-line-1'), findsOneWidget);
        expect(keyed('expense-remove-line-2'), findsOneWidget);
        expect(
          tester.getRect(keyed('expense-add-line')).left,
          greaterThan(tester.getRect(amount).right),
        );
        await capture(
          tester,
          'Claim Expense Mixed Tax Header ${width.toInt()}',
        );
        await tap(tester, keyed('expense-field-tax'));
        expect(find.text('Service Tax · 8%').last, findsOneWidget);
        await capture(tester, 'Claim Expense Tax Menu ${width.toInt()}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.ensureVisible(amount);
        await tester.enterText(amount, '120');
        await tester.pumpAndSettle();
        final uploader = keyed('expense-receipt-surface');
        await tester.ensureVisible(uploader);
        await tester.pumpAndSettle();
        final evidence = keyed(
          'expense-attachment-row-${original.attachments.single.originalId}',
        );
        expect(evidence, findsOneWidget);
        expect(
          tester.getRect(evidence).top,
          greaterThan(tester.getRect(uploader).bottom),
        );
        await capture(tester, 'Claim Expense Mixed Receipts ${width.toInt()}');
        await tap(tester, keyed('record-claim-save-draft'));
        expect(find.byType(RecordExpensePage), findsNothing);
        final saved = w.claims.byId(original.id)!;
        expect(saved.amount, Money.fromDecimal('203.60', 'MYR'));
        expect(saved.legacySource!.toJson(), original.toJson());
        expect(
          saved.expenseDraft!.taxTotals!.total,
          Money.fromDecimal('203.60', 'MYR'),
        );
        expect(saved.expenseDraft!.receiptLineBases, shown.receiptLineBases);
        expect(
          Money.fromDecimal(saved.expenseDraft!.lines.first.amount, 'MYR'),
          Money.fromDecimal('120', 'MYR'),
        );
        expect(
          saved.expenseDraft!.lines.first.taxSnapshot!.choice,
          f.code.choice,
        );
        expect(
          saved.attachments.map((a) => a.originalId).toList(),
          original.attachments.map((a) => a.originalId).toList(),
        );
        await tap(tester, keyed('claim-edit-${original.id}'));
        await tap(tester, keyed('record-claim-submit'));
        expect(w.claims.byId(original.id)!.status, ClaimStatus.draft);
        expect(
          find.text('Review Tax Inclusive or Tax Exclusive before submitting.'),
          findsOneWidget,
        );
        expect(await w.journals(), isEmpty);
        await capture(tester, 'Claim Expense Basis Review ${width.toInt()}');
        await tap(tester, keyed('expense-tax-treatment'));
        await tap(tester, find.text('Tax Exclusive').hitTestable());
        await tap(tester, keyed('record-claim-submit'));
        expect(w.claims.byId(original.id)!.status, ClaimStatus.submitted);
        await tap(tester, keyed('claim-more-${original.id}'));
        await tap(tester, keyed('claim-approve-${original.id}'));
        expect(keyed('claim-receipt-approval'), findsOneWidget);
        expect(find.text('Expense Account'), findsNothing);
        expect(find.text('Ledger Allocation'), findsNothing);
        await tester.ensureVisible(keyed('claim-receipt-summary'));
        await tester.pumpAndSettle();
        await capture(
          tester,
          'Claim Receipt Approval Summary ${width.toInt()}',
        );
        for (final (line, account) in [
          ('receipt-a-taxed', '5000 · Business Services'),
          ('receipt-a-asset', '1500 · Equipment'),
          ('receipt-b-taxed', '5100 · Printing'),
        ]) {
          await tap(tester, keyed('claim-expense-account-$line'));
          await tap(tester, find.text(account).last);
        }
        await tap(tester, keyed('claim-receipt-payable'));
        await tap(tester, find.text('2100 · Claims Payable').last);
        expect(find.text('Ledger Allocation'), findsOneWidget);
        expect(keyed('claim-receipt-costs'), findsOneWidget);
        await capture(tester, 'Claim Receipt Approval ${width.toInt()}');
        await tap(tester, keyed('claim-receipt-approve'));
        expect(w.claims.byId(original.id)!.status, ClaimStatus.approved);
        final report = await w.report(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(report.expenses, BigInt.from(18792));
        expect(report.assets, BigInt.from(2000));
        expect(report.liabilities, BigInt.from(20792));
        final activity = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        expect(activity.rows.length, 3);
        expect(activity.unresolved, isEmpty);
        expect(
          activity.rows.fold<BigInt>(BigInt.zero, (s, r) => s + r.taxMinor!),
          BigInt.from(1392),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        final recovered = w.claims.byId(original.id)!;
        expect(recovered.legacySource!.toJson(), original.toJson());
        expect(recovered.expenseDraft!.taxMode, 'Exclusive');
        expect(recovered.expenseDraft!.receiptLineBases, isEmpty);
        expect(
          recovered.expenseDraft!.lines.map((l) => l.toJson()).toList(),
          saved.expenseDraft!.lines.map((l) => l.toJson()).toList(),
        );
        expect(recovered.amount, Money.fromDecimal('207.92', 'MYR'));
        expect((await w.journals()).length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'current Expense-based Claim selects tax, retains originals, and explicit Discard drops edits',
    (tester) async {
      await prepare(tester, 720);
      installFixedPopoutHost(tester);
      final f = await fixture();
      final w = f.w;
      addTearDown(w.dispose);
      final seed = f.claim();
      w.claims.saveDraft(seed);
      await host(tester, w);
      await tap(tester, keyed('claim-edit-${seed.id}'));
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byType(ClaimReceiptsEditor), findsNothing);
      expect(keyed('claim-add-receipt'), findsNothing);
      await tap(tester, keyed('expense-field-category'));
      await tap(
        tester,
        find.descendant(
          of: keyed('expense-category-menu'),
          matching: find.text('Utilities'),
        ),
      );
      await tap(tester, keyed('expense-field-tax'));
      await tap(
        tester,
        find.descendant(
          of: keyed('expense-tax-menu'),
          matching: find.text('Service Tax · 8%'),
        ),
      );
      final memo = keyed('expense-field-notes');
      await tester.ensureVisible(memo);
      await enterAccountingText(tester, memo, 'Contoh Services receipt review');
      final originalId = seed.attachments.single.originalId;
      expect(keyed('expense-attachment-row-$originalId'), findsOneWidget);
      expect(keyed('expense-attachment-view-$originalId'), findsOneWidget);
      await tap(tester, keyed('record-claim-save-draft'));
      final saved = w.claims.byId(seed.id)!;
      expect(saved.expenseDraft!.lines.first.category, 'Utilities');
      expect(
        saved.expenseDraft!.lines.first.taxSnapshot!.choice,
        f.code.choice,
      );
      expect(saved.expenseDraft!.notes, 'Contoh Services receipt review');
      expect(saved.amount, seed.amount);
      expect(saved.legacySource!.toJson(), seed.toJson());
      expect(saved.attachments.single.originalId, originalId);
      final facts = saved.toJson();
      await tap(tester, keyed('claim-edit-${seed.id}'));
      await tap(tester, keyed('expense-add-line'));
      expect(keyed('expense-remove-line-3'), findsOneWidget);
      await tester.ensureVisible(keyed('expense-field-notes'));
      await enterAccountingText(
        tester,
        keyed('expense-field-notes'),
        'Unsaved correction',
      );
      await tap(
        tester,
        find
            .byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Close',
            )
            .last,
      );
      expect(keyed('expense-discard-changes'), findsOneWidget);
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(w.claims.byId(seed.id)!.toJson(), facts);
      await tap(tester, keyed('expense-discard-changes'));
      expect(find.byType(RecordExpensePage), findsNothing);
      expect(w.claims.byId(seed.id)!.toJson(), facts);
      expect(await w.journals(), isEmpty);
      expect(await w.expenses(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'receipt upload actions link reviewed originals, preserve cancellation and skip',
    (tester) async {
      await prepare(tester, 720);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final initial = f.claim();
      final destination = Directory.systemTemp.createTempSync(
        'claim-upload-test-',
      );
      addTearDown(() => destination.deleteSync(recursive: true));
      var filed = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(namingSettingsChannel, (call) async {
            if (call.method == 'load') {
              return jsonEncode([
                {'type': 'custom', 'text': 'CLAIM'},
              ]);
            }
            if (call.method == 'loadFolder') return destination.path;
            if (call.method == 'saveDocument') {
              final file = File('${destination.path}/receipt-${++filed}.pdf');
              await file.writeAsBytes(call.arguments['bytes'] as List<int>);
              return file.path;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(namingSettingsChannel, null),
      );
      final document = pw.Document()
        ..addPage(pw.Page(build: (_) => pw.Text('Receipt original')));
      final bytes = await document.save();
      final accounts = (await f.w.accounts()).map((a) => a.account).toList();
      var pickCount = 0, saved = false, cancelledPick = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ClaimEditorDialog(
                id: initial.id,
                initial: initial,
                receiptTaxProposal: true,
                receiptAccounts: accounts,
                receiptTaxCodes: [f.code],
                onSaveDraft: (_) {
                  saved = true;
                },
                onSubmit: (_) {
                  saved = true;
                },
                onAttachmentsPick: (_) async {
                  pickCount++;
                  if (cancelledPick) return [];
                  return [
                    PickedExpenseAttachment(
                      name: 'new-original.pdf',
                      mimeType: 'application/pdf',
                      bytes: bytes,
                    ),
                  ];
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ClaimReceiptsEditor editor() =>
          tester.widget(find.byType(ClaimReceiptsEditor));
      Future<void> review(Finder action, {bool skip = false}) async {
        await tester.ensureVisible(action);
        await realAction(tester, () => tester.tap(action));
        expect(find.byType(ReceiptReviewDialog), findsOneWidget);
        if (skip) {
          await realAction(
            tester,
            () => tester.tap(keyed('receipt-review-skip')),
          );
        } else {
          await realAction(
            tester,
            () => tester.tap(keyed('receipt-review-save')),
          );
          await realAction(
            tester,
            () => tester.tap(keyed('receipt-review-close')),
            closesEditor: true,
          );
        }
        await tester.pumpAndSettle();
      }

      expect(editor().draft.receipts.length, 2);
      await review(keyed('claim-add-receipt'));
      expect(pickCount, 1);
      expect(editor().draft.receipts.length, 3);
      final added = editor().draft.receipts.last;
      expect(added.originals.length, 1);
      expect(
        added.originals.single,
        isNot(initial.attachments.single.originalId),
      );
      expect(
        editor().evidence.any((a) => a.originalId == added.originals.single),
        isTrue,
      );
      await review(keyed('receipt-add-original-receipt-a'));
      expect(editor().draft.receipts.length, 3);
      expect(editor().draft.receipts.first.originals.length, 2);
      cancelledPick = true;
      final before = editor().draft.receipts.length;
      await tap(tester, keyed('claim-add-receipt'));
      expect(editor().draft.receipts.length, before);
      cancelledPick = false;
      await review(keyed('claim-add-receipt'), skip: true);
      expect(editor().draft.receipts.length, before);
      expect(find.byType(ReceiptReviewDialog), findsNothing);
      await tap(tester, keyed('claim-cancel'));
      expect(saved, isFalse);
      expect(filed, 2);
      expect(
        File('${destination.path}/receipt-1.pdf').readAsBytesSync(),
        bytes,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('receipt draft preserves priced facts and uses the shared inverse-pricing adjustment', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final original = f.claim();
    final draft = ClaimReceiptsDraft(
      currency: 'MYR',
      date: original.incurredOn!,
      initial: original.receipts,
    );
    addTearDown(draft.dispose);
    final r = draft.receipts.first, l = r.lines.first;
    l.quantity.text = '3';
    l.rate.text = '3.34';
    l.amount.text = '10';
    l.adjustment = '-0.02';
    final accounts = (await f.w.accounts()).map((a) => a.account).toList();
    var built = draft.build(accounts, f.w.taxRates, original.attachments);
    expect(built.first.lines.first.item.pricingAdjustment, '-0.02');
    l.amount.text = '10';
    draft.reprice(l, 'Amount');
    expect(l.rate.text, '3.34');
    expect(l.adjustment, '-0.02');
    l.quantity.text = '4';
    draft.reprice(l, 'Quantity');
    expect(l.amount.text, '13.36');
    expect(l.adjustment, isNull);
    built = draft.build(accounts, f.w.taxRates, original.attachments);
    expect(built.first.lines.first.item.amount, '13.36');
    r.originals.add(r.originals.first);
    expect(
      () => draft.build(accounts, f.w.taxRates, original.attachments),
      throwsFormatException,
    );
  });
  test('changed receipt date rejects an expired retained tax and missing original remains unresolved', () async {
    final f = await fixture();
    addTearDown(f.w.dispose);
    final expired = f.w.saveTaxRate(
      CompanyTaxRate.fromJson({
        ...f.code.toJson(),
        'through': '2026-09-30T00:00:00.000Z',
      }),
    );
    final source = f.claim(rate: expired);
    final draft = ClaimReceiptsDraft(
      currency: 'MYR',
      date: source.incurredOn!,
      initial: source.receipts,
    );
    addTearDown(draft.dispose);
    final accounts = (await f.w.accounts()).map((a) => a.account).toList();
    draft.receipts.first.date.text = '01-10-2026';
    expect(draft.gross(f.w.taxRates), isNull);
    expect(
      () => draft.build(accounts, f.w.taxRates, source.attachments),
      throwsStateError,
    );
    draft.receipts.first.lines.first.tax = '0';
    expect(
      draft
          .build(accounts, f.w.taxRates, source.attachments)
          .first
          .totals
          .tax
          .minorUnits,
      0,
    );
    draft.receipts.first.originals[0] = 'missing';
    expect(
      () => draft.build(accounts, f.w.taxRates, source.attachments),
      throwsFormatException,
    );
  });
}
