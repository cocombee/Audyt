import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_popout_host.dart';
import '../support/accounting_text_input.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual legacy route uses Expense owner and retains original on save at $width',
      (t) async {
        await prepare(t, width);
        installFixedPopoutHost(t);
        final store = ClaimStore.demo();
        addTearDown(store.dispose);
        final original = store.all.first;
        final before = original.toJson();
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: ClaimsPage(store: store)),
            ),
          ),
        );
        await t.pumpAndSettle();
        await revealAccountingRecord(
          t,
          find.byKey(ValueKey('claim-edit-${original.id}')),
        );
        await tap(t, find.byKey(ValueKey('claim-edit-${original.id}')));
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(find.text('Claim category'), findsNothing);
        expect(find.text('Business purpose'), findsNothing);
        expect(
          find.byKey(const ValueKey('expense-document-number')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('claim-expense-claimant')),
          findsOneWidget,
        );
        expect(store.byId(original.id)!.toJson(), before);
        final add = find.byKey(const ValueKey('expense-add-line'));
        await tap(t, add);
        final remove = find.byKey(const ValueKey('expense-remove-line-1'));
        expect(remove, findsOneWidget);
        await tap(t, remove);
        expect(remove, findsNothing);
        await capture(
          t,
          'Legacy Claim Existing Expense Lines ${width.toInt()}',
        );
        await tap(t, find.byKey(const ValueKey('record-claim-save-draft')));
        expect(t.takeException(), isNull);
        expect(find.byType(RecordExpensePage), findsNothing);
        final saved = store.byId(original.id)!;
        expect(saved.legacySource!.toJson(), before);
        expect(
          saved.expenseDraft!.attachments.single.originalSha256,
          original.attachments.single.originalSha256,
        );
        expect(saved.expenseDraft!.taxMode, isNull);
        await tap(t, find.byKey(ValueKey('claim-edit-${original.id}')));
        expect(find.byType(RecordExpensePage), findsOneWidget);
        await capture(
          t,
          'Legacy Claim Existing Expense Header ${width.toInt()}',
        );
        await tap(t, find.byType(AccountingCloseIcon).last);
        expect(store.byId(original.id)!.toJson(), saved.toJson());
        await tap(t, find.byKey(ValueKey('claim-more-${original.id}')));
        await tap(t, find.byKey(ValueKey('claim-original-${original.id}')));
        expect(
          t.widget<RecordExpensePage>(find.byType(RecordExpensePage)).readOnly,
          isTrue,
        );
        expect(find.byKey(const ValueKey('expense-add-line')), findsNothing);
        expect(
          find.byKey(const ValueKey('expense-tax-selection-warning')),
          findsNothing,
        );
        await capture(t, 'Legacy Claim Original Evidence ${width.toInt()}');
        await tap(t, find.byType(AccountingCloseIcon).last);
        expect(store.byId(original.id)!.toJson(), saved.toJson());
      },
    );

    for (final status in [ClaimStatus.submitted, ClaimStatus.paid]) {
      testWidgets(
        'current legacy ${status.name} Claim permits local line edits without false save authority at $width',
        (t) async {
          await prepare(t, width);
          installFixedPopoutHost(t);
          final store = ClaimStore.demo();
          addTearDown(store.dispose);
          final original = store.all.firstWhere((c) => c.status == status);
          final before = store.all.map((c) => c.toJson()).toList();
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: ClaimsPage(store: store)),
              ),
            ),
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(ValueKey('claim-edit-${original.id}')));
          expect(
            t
                .widget<RecordExpensePage>(find.byType(RecordExpensePage))
                .readOnly,
            isFalse,
          );
          expect(find.byType(ClaimEditorDialog), findsNothing);
          await tap(t, find.byKey(const ValueKey('expense-add-line')));
          expect(
            find.byKey(const ValueKey('expense-remove-line-1')),
            findsOneWidget,
          );
          await tap(t, find.byKey(const ValueKey('expense-remove-line-1')));
          for (final key in [
            'record-claim-save-draft',
            'record-claim-submit',
          ]) {
            expect(
              t.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed,
              isNull,
            );
          }
          expect(
            t
                .widget<RecordExpensePage>(find.byType(RecordExpensePage))
                .claimContext!
                .unavailableReason,
            contains('Saving changes to this Claim is unavailable'),
          );
          await capture(
            t,
            'Legacy Claim ${status.name} Current Lines ${width.toInt()}',
          );
          await tap(t, find.byType(AccountingCloseIcon).last);
          expect(store.all.map((c) => c.toJson()).toList(), before);
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'legacy Expense owner retains forced Quantity Rate and original solid actions at $width',
      (t) async {
        await prepare(t, width);
        installFixedPopoutHost(t);
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        workspace.savePreferences(
          workspace.preferences.change('Purchase Preferences', {
            'Show Quantity': true,
            'Show Rate': true,
          }),
        );
        final original = workspace.claims.all.firstWhere(
          (claim) => claim.status.name == 'draft',
        );
        final before = original.toJson();
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: ClaimsPage(
                  store: workspace.claims,
                  workspace: workspace,
                  payeeStore: workspace.payees,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await revealAccountingRecord(
          t,
          find.byKey(ValueKey('claim-edit-${original.id}')),
        );
        await tap(t, find.byKey(ValueKey('claim-edit-${original.id}')));
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('expense-line-0-quantity')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('expense-line-0-rate')),
          findsOneWidget,
        );
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('expense-line-0-rate')),
              )
              .controller!
              .text,
          original.amount.toDecimalString(),
        );
        await tap(t, find.byKey(const ValueKey('expense-add-line')));
        await tap(t, find.byKey(const ValueKey('expense-remove-line-1')));
        expect(
          t.getRect(find.byKey(const ValueKey('expense-add-line'))).left,
          greaterThan(
            t.getRect(find.byKey(const ValueKey('expense-field-amount'))).right,
          ),
        );
        await capture(t, 'Legacy Claim Forced Quantity Rate ${width.toInt()}');
        expect(workspace.claims.byId(original.id)!.toJson(), before);
        expect(t.takeException(), isNull);
      },
    );
  }
}
