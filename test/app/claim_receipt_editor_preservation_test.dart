import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/legacy_claim_expense_view.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/claim_receipt_tax_test.dart' show fixture;
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Expense-based Claim preserves mixed receipt taxes and exact original on save/restart at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final dir = Directory.systemTemp.createTempSync(
          'claim-receipt-editor-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite';
        final f = await fixture(path: path);
        var w = f.w;
        addTearDown(() => w.dispose());
        final claim = f.claim();
        w.claims.saveDraft(claim);
        final original = claim.toJson();
        final projection = legacyClaimExpenseView(claim);
        // Original receipt bundles still reject an independently falsified total.
        // The current Expense body derives its total from lines instead of exposing
        // the retired independent Claim Amount field.
        expect(
          () => Claim.fromJson({...original, 'amountMinor': 18300}),
          throwsA(isA<Object>()),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ClaimsPage(store: w.claims, workspace: w),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, find.byKey(ValueKey('claim-edit-${claim.id}')));
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(find.byKey(const ValueKey('claim-amount')), findsNothing);
        final shown = tester
            .widget<RecordExpensePage>(find.byType(RecordExpensePage))
            .savedDraft!;
        expect(shown.taxTotals!.total, claim.amount);
        expect(shown.receiptLineBases, projection.receiptLineBases);
        expect(
          shown.lines.map((l) => l.toJson()).toList(),
          projection.lines.map((l) => l.toJson()).toList(),
        );
        expect(w.claims.byId(claim.id)!.toJson(), original);
        final purpose = find.byKey(const ValueKey('expense-field-notes'));
        await tester.ensureVisible(purpose);
        await enterAccountingText(
          tester,
          purpose,
          'Reviewed business receipt bundle',
        );
        await capture(
          tester,
          'Legacy Claim Mixed Receipt Lines ${width.toInt()}',
        );
        await tap(
          tester,
          find.byKey(const ValueKey('record-claim-save-draft')),
        );
        expect(find.byType(RecordExpensePage), findsNothing);
        final saved = w.claims.byId(claim.id)!;
        expect(saved.legacySource!.toJson(), original);
        expect(saved.expenseDraft!.notes, 'Reviewed business receipt bundle');
        expect(saved.expenseDraft!.taxTotals!.total, claim.amount);
        expect(
          saved.expenseDraft!.receiptLineBases,
          projection.receiptLineBases,
        );
        expect(
          saved.expenseDraft!.lines.map((l) => l.toJson()).toList(),
          projection.lines.map((l) => l.toJson()).toList(),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        final recovered = w.claims.byId(claim.id)!;
        expect(recovered.toJson(), saved.toJson());
        expect(recovered.legacySource!.toJson(), original);
        expect(await w.journals(), isEmpty);
        expect(await w.expenses(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
