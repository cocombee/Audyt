import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/expense_category.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart'
    show RecordExpensePage, RecordExpenseClaimContext;
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/claim_expense_snapshot_test.dart'
    show expenseBody;
import '../features/accounting/data/claim_receipt_tax_test.dart'
    show fixture, Fixture;
import '../support/fixed_popout_host.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;

RecordExpenseDraft maintainedBody(Fixture f) {
  final body = expenseBody(f).toJson();
  final lines = body['lines'] as List;
  const names = [
    'Office Supplies & Small Equipment',
    'Equipment, Computers & Furniture',
    'Office Supplies & Small Equipment',
  ];
  for (var index = 0; index < lines.length; index++) {
    (lines[index] as Map)['category'] = ExpenseCategoryCatalog.seeded
        .firstWhere((category) => category.displayName == names[index])
        .displayName;
  }
  return RecordExpenseDraft.fromJson(body);
}

Claim identifiedClaim(Fixture f, RecordExpenseDraft body) {
  f.w.payees.save(
    const Payee(
      id: 'registered-employee-fixture',
      name: 'Fictional Registered Claimant With A Long Name',
      type: PayeeType.staff,
    ),
  );
  return Claim.expense(
    id: EntityId.random(),
    draft: body,
    claimantName: 'Fictional Registered Claimant With A Long Name',
    claimantIdentity: ClaimantIdentity(
      payeeId: 'registered-employee-fixture',
      type: ClaimantType.staff,
    ),
  );
}

Future<void> host(WidgetTester tester, Fixture f) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: ClaimsPage(
            store: f.w.claims,
            workspace: f.w,
            payeeStore: f.w.payees,
            receiptTaxProposal: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('returned Claim edits the existing Expense body at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      installFixedPopoutHost(tester);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final submitted = f.w.claims.saveAndSubmit(
        identifiedClaim(f, maintainedBody(f)),
      );
      final original = f.w.claims.returnForCorrection(
        submitted.id,
        expectedCurrent: submitted,
      );
      await host(tester, f);
      await tap(tester, find.byKey(ValueKey('claim-edit-${original.id}')));
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byType(ClaimEditorDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('claim-expense-claimant')),
        findsOneWidget,
      );
      expect(find.text('Personally Paid'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expense-payment-account-dropdown')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('record-expense-save')), findsNothing);
      expect(find.text('Claim category'), findsNothing);
      expect(find.text('Receipt 1'), findsNothing);
      expect(
        find.byKey(const ValueKey('expense-recurrence-information')),
        findsOneWidget,
      );
      expect(find.text('Next Dates'), findsOneWidget);
      await capture(tester, 'Returned Claim Expense Body ${width.toInt()}');
      final save = find.byKey(const ValueKey('record-claim-save-draft'));
      await tap(tester, save);
      expect(tester.takeException(), isNull);
      expect(find.byType(RecordExpensePage), findsNothing);
      final saved = f.w.claims.byId(original.id)!;
      expect(saved.status, ClaimStatus.returned);
      expect(saved.claimantName, original.claimantName);
      expect(
        saved.claimantIdentity!.toJson(),
        original.claimantIdentity!.toJson(),
      );
      expect(saved.expenseDraft!.toJson(), original.expenseDraft!.toJson());
      expect(saved.expenseDraft!.paymentAccount, isEmpty);
      expect(saved.expenseDraft!.paymentAccountId, isNull);
      expect(await f.w.expenses(), isEmpty);
      expect(await f.w.journals(), isEmpty);

      await tap(tester, find.byKey(ValueKey('claim-edit-${saved.id}')));
      final submit = find.byKey(const ValueKey('record-claim-submit'));
      final button = tester.widget<FilledButton>(submit);
      expect(
        button.style!.backgroundColor!.resolve({}),
        AccountingTheme.of(tester.element(submit)).primary,
      );
      await tap(tester, submit);
      expect(tester.takeException(), isNull);
      expect(f.w.claims.byId(original.id)!.status, ClaimStatus.submitted);
      expect(
        f.w.claims.byId(original.id)!.expenseDraft!.toJson(),
        saved.expenseDraft!.toJson(),
      );
      expect(await f.w.journals(), isEmpty);
    });

    testWidgets(
      'submitted Claim opens its retained editable Expense body at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = await fixture();
        addTearDown(f.w.dispose);
        final submitted = f.w.claims.saveAndSubmit(
          identifiedClaim(f, maintainedBody(f)),
        );
        final frozen = submitted.toJson();
        await host(tester, f);
        await tap(tester, find.byKey(ValueKey('claim-edit-${submitted.id}')));
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(
          tester
              .widget<RecordExpensePage>(find.byType(RecordExpensePage))
              .readOnly,
          isFalse,
        );
        expect(find.byType(ClaimEditorDialog), findsNothing);
        for (final action in [
          'record-claim-save-draft',
          'record-claim-submit',
        ]) {
          final button = find.byKey(ValueKey(action));
          expect(button, findsOneWidget);
          expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
          expect(
            tester
                .widget<Tooltip>(
                  find.descendant(of: button, matching: find.byType(Tooltip)),
                )
                .message,
            'Saving changes to this Claim is unavailable. Your saved Claim is unchanged.',
          );
        }
        final addLine = find.byKey(const ValueKey('expense-add-line'));
        expect(addLine, findsOneWidget);
        expect(tester.widget<IconButton>(addLine).onPressed, isNotNull);
        expect(
          find.byKey(const ValueKey('record-expense-card-footer')),
          findsOneWidget,
        );
        expect(find.text(submitted.claimantName), findsOneWidget);
        final original = find.byKey(
          ValueKey(
            'expense-attachment-view-${submitted.attachments.single.originalId}',
          ),
        );
        await tester.ensureVisible(original);
        await tester.pumpAndSettle();
        await capture(
          tester,
          'Submitted Claim Expense Originals ${width.toInt()}',
        );
        expect(original, findsOneWidget);
        await tap(tester, original);
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        await tap(
          tester,
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.label == 'Close',
              )
              .last,
        );
        expect(find.byType(AttachmentPreviewDialog), findsNothing);
        expect(f.w.claims.byId(submitted.id)!.toJson(), frozen);
        await tap(tester, find.byKey(const ValueKey('record-expense-cancel')));
        expect(find.byType(RecordExpensePage), findsNothing);
        expect(tester.takeException(), isNull);
        expect(await f.w.journals(), isEmpty);
      },
    );
  }

  testWidgets('submission validation and retry retain Claim command intent', (
    tester,
  ) async {
    await prepare(tester, 1224);
    installFixedPopoutHost(tester);
    final f = await fixture();
    addTearDown(f.w.dispose);
    final original = identifiedClaim(f, maintainedBody(f));
    var validation = true;
    var submissions = 0;
    var drafts = 0;
    final attempts = <Map<String, Object?>>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => RecordExpensePage(
                  includeTopSafeArea: false,
                  savedDraft: original.expenseDraft,
                  settingsWorkspace: f.w,
                  payeeStore: f.w.payees,
                  onCancel: () => Navigator.pop(dialogContext),
                  onSaved: () => Navigator.pop(dialogContext),
                  claimContext: RecordExpenseClaimContext(
                    claimantField: Text(original.claimantName),
                    submissionErrors: (_) => validation
                        ? ['Review the business purpose before submitting.']
                        : [],
                    saveDraft: (_) async {
                      drafts++;
                    },
                    submitForReview: (draft) async {
                      submissions++;
                      attempts.add(draft.toJson());
                      if (submissions == 1) {
                        throw StateError('Disconnected before command');
                      }
                      f.w.claims.saveAndSubmit(original.reviseExpense(draft));
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Open'));
    await tap(tester, find.byKey(const ValueKey('record-claim-submit')));
    expect(submissions, 0);
    expect(drafts, 0);
    expect(
      find.text('Review the business purpose before submitting.'),
      findsOneWidget,
    );
    expect(find.byType(RecordExpensePage), findsOneWidget);
    validation = false;
    await tap(tester, find.byKey(const ValueKey('record-expense-retry-save')));
    expect(submissions, 1);
    expect(find.text('Disconnected before command'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('record-expense-retry-save')));
    expect(submissions, 2);
    expect(drafts, 0);
    expect(attempts[1], attempts[0]);
    expect(attempts[0]['paymentAccount'], isEmpty);
    expect(attempts[0]['paymentAccountId'], isNull);
    expect(f.w.claims.byId(original.id)!.status, ClaimStatus.submitted);
    expect(await f.w.journals(), isEmpty);
    expect(await f.w.expenses(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an Expense saver cannot coexist with Claim commands', (
    tester,
  ) async {
    await prepare(tester, 1224);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordExpensePage(
          onSave: (_) async {},
          claimContext: RecordExpenseClaimContext(
            claimantField: const Text('Claimant'),
            saveDraft: (_) async {},
            submitForReview: (_) async {},
            submissionErrors: (_) => [],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isA<ArgumentError>());
  });

  test(
    'Expense-backed revisions preserve identity and reject lifecycle reset',
    () async {
      final f = await fixture();
      addTearDown(f.w.dispose);
      final original = identifiedClaim(f, maintainedBody(f));
      final body = original.expenseDraft!.toJson();
      body['notes'] = 'Corrected business memo';
      final changed = RecordExpenseDraft.fromJson(body);
      final returned = original.submit().returnForCorrection();
      final revised = returned.reviseExpense(changed);
      expect(revised.status, ClaimStatus.returned);
      expect(revised.id, original.id);
      expect(
        revised.claimantIdentity!.toJson(),
        original.claimantIdentity!.toJson(),
      );
      expect(revised.claimantName, original.claimantName);
      expect(revised.businessPurpose, 'Corrected business memo');
      expect(original.expenseDraft!.notes, isNot('Corrected business memo'));
      body['submissionId'] = 'different-form';
      expect(
        () => returned.reviseExpense(RecordExpenseDraft.fromJson(body)),
        throwsFormatException,
      );
      for (final immutable in [
        original.submit(),
        original.submit().approve(),
        original.submit().decline(),
      ]) {
        expect(() => immutable.reviseExpense(changed), throwsStateError);
      }
    },
  );
}
