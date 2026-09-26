import 'dart:convert';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/membership_service.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/expense_category.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_expense_creation.dart';
import 'package:audyt/features/purchases/presentation/claim_expense_creation_dialog.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

import '../features/accounting/data/claim_receipt_tax_test.dart'
    show fixture, Fixture;
import '../support/fixed_popout_host.dart';
import '../support/accounting_text_input.dart';
import '../support/receipt_editor_actions.dart' show realAction;
import 'claim_expense_editor_journey_test.dart' show maintainedBody;
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;

const actorId = '11111111-1111-4111-8111-111111111111';
const claimantId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> identity(String id, String role) => {
  'id': id,
  'name': id == claimantId
      ? 'Fictional Registered Employee With A Long Name'
      : 'Fictional Registered $role',
  'role': role,
  'revision': 2,
};

ServiceClaimantContext registration(Fixture f, String role) =>
    ServiceClaimantContext.fromJson({
      'businessId': f.w.identity.businessId.value,
      'actor': identity(actorId, role),
      'claimants': [
        identity(actorId, role),
        if (role != 'employee') identity(claimantId, 'employee'),
      ],
    });

/// Explicit disposable command adapter. This exercises actual local persistence
/// behind the editor boundary, not production service/actor authorization.
class FixtureGateway implements ClaimExpenseCreationGateway {
  FixtureGateway(this.f, this.context);
  final Fixture f;
  ServiceClaimantContext context;
  final calls = <ClaimExpenseCreationCommand>[];
  final acknowledgements = <String, String>{};
  bool loseFirstAcknowledgement = false;
  @override
  String get businessId => f.w.identity.businessId.value;
  @override
  Future<ServiceClaimantContext> claimants(String query) async => context;
  @override
  Future<void> execute(ClaimExpenseCreationCommand command) async {
    calls.add(command);
    if (!sameClaimActor(
      context,
      ServiceClaimantContext.fromJson({
        'businessId': command.businessId,
        'actor': identity(
          command.expectedActor.identityId,
          command.expectedActor.role,
        ),
        'claimants': [],
      }),
    )) {
      throw StateError('Fixture actor changed.');
    }
    final payload = jsonEncode([
      command.claimId.value,
      command.intent.name,
      command.selectedClaimant.identityId,
      command.draft.toJson(),
    ]);
    final prior = acknowledgements[command.requestId.value];
    if (prior != null) {
      if (prior != payload) throw StateError('Fixture request reused.');
      return;
    }
    final selected = command.selectedClaimant;
    f.w.payees.save(
      Payee(
        id: selected.identityId,
        name: selected.name,
        type: selected.role == 'director'
            ? PayeeType.director
            : PayeeType.staff,
      ),
    );
    if (command.intent == ClaimCreationIntent.submitForReview) {
      f.w.claims.saveAndSubmit(command.validationClaim);
    } else {
      f.w.claims.saveDraft(command.validationClaim);
    }
    acknowledgements[command.requestId.value] = payload;
    if (loseFirstAcknowledgement) {
      loseFirstAcknowledgement = false;
      throw StateError('Fixture response interrupted after commit.');
    }
  }
}

Future<void> host(
  WidgetTester tester,
  Fixture f,
  FixtureGateway? gateway, {
  ExpenseAttachmentsPicker? picker,
}) async {
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
            claimCreationGateway: gateway,
            onAttachmentsPick: picker,
            receiptTaxProposal: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  for (final (key, value) in [
    ('expense-field-payee', 'Fictional Office Supplier'),
    ('expense-field-date', '14-09-2026'),
  ]) {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await enterAccountingText(tester, field, value);
    await tester.pumpAndSettle();
  }
  await tap(tester, find.byKey(const ValueKey('expense-tax-treatment')));
  await tap(tester, find.text('Tax Exclusive').last);
  await tap(tester, find.byKey(const ValueKey('expense-field-category')));
  final category = ExpenseCategoryCatalog.seeded.firstWhere(
    (c) => c.displayName == 'Office Supplies & Small Equipment',
  );
  await tap(
    tester,
    find.byKey(ValueKey('expense-category-option-${category.code}')),
  );
  for (final (key, value) in [
    ('expense-field-amount', '140'),
    ('expense-field-item-or-split', 'Fictional office stationery'),
    ('expense-field-notes', 'Fictional business purpose'),
  ]) {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await enterAccountingText(tester, field, value);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final role in ['employee', 'accountant', 'director']) {
    for (final width in [720.0, 1224.0]) {
      testWidgets('new $role Claim uses actual Expense entry at $width', (
        tester,
      ) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = await fixture();
        addTearDown(f.w.dispose);
        final gateway = FixtureGateway(f, registration(f, role));
        await host(tester, f, gateway);
        await tap(tester, find.byKey(const ValueKey('claims-create')));
        expect(find.byType(ClaimExpenseCreationDialog), findsOneWidget);
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(find.text('Personally Paid'), findsOneWidget);
        final selector = find.byKey(const ValueKey('claim-create-claimant'));
        if (role == 'employee') {
          expect(tester.widget(selector), isA<InputDecorator>());
          expect(
            find.byKey(const ValueKey('expense-settings-shortcut')),
            findsNothing,
          );
        } else {
          expect(
            find.ancestor(
              of: selector,
              matching: find.byType(AccountingSelector<String>),
            ),
            findsOneWidget,
          );
          await tap(tester, selector);
          await tap(
            tester,
            find.byKey(const ValueKey('claim-create-option-$claimantId')),
          );
          expect(find.text('Add Claimant'), findsNothing);
        }
        await fill(tester);
        FocusScope.of(tester.element(selector)).unfocus();
        await tester.pumpAndSettle();
        final bodyScroll = find
            .ancestor(of: selector, matching: find.byType(Scrollable))
            .evaluate()
            .map(
              (element) =>
                  (element as StatefulElement).state as ScrollableState,
            )
            .map((state) => state.position)
            .singleWhere((position) => position.axis == Axis.vertical);
        bodyScroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text('Claimant')).top,
          greaterThan(tester.getRect(find.text('Claim')).bottom),
        );
        await capture(tester, 'New Claim $role Expense Body ${width.toInt()}');
        expect(
          find.byKey(const ValueKey('expense-payment-account-dropdown')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('record-expense-save')), findsNothing);
        final submit = find.byKey(const ValueKey('record-claim-submit'));
        await tap(tester, submit);
        expect(
          gateway.calls,
          isEmpty,
          reason: 'A draft without an original cannot be submitted.',
        );
        expect(find.byType(RecordExpensePage), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('expense-add-receipt-action')),
        );
        await tester.pumpAndSettle();
        await capture(
          tester,
          'New Claim $role Expense Receipts ${width.toInt()}',
        );
        await tap(
          tester,
          find.byKey(const ValueKey('record-claim-save-draft')),
        );
        expect(find.byType(RecordExpensePage), findsNothing);
        expect(gateway.calls, hasLength(1));
        final command = gateway.calls.single;
        expect(command.intent, ClaimCreationIntent.saveDraft);
        expect(command.expectedActor.identityId, actorId);
        expect(
          command.selectedClaimant.identityId,
          role == 'employee' ? actorId : claimantId,
        );
        final claim = f.w.claims.byId(command.claimId)!;
        expect(claim.status, ClaimStatus.draft);
        expect(claim.expenseDraft!.toJson(), command.draft.toJson());
        expect(claim.expenseDraft!.paymentAccount, isEmpty);
        expect(claim.expenseDraft!.paymentAccountId, isNull);
        expect(claim.expenseDraft!.taxMode, 'Exclusive');
        expect(claim.expenseDraft!.lines.single.tax, '0');
        expect(await f.w.journals(), isEmpty);
        expect(await f.w.expenses(), isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'missing Claim service retains Expense body, honest unavailable commands and untouched Close at $width',
      (tester) async {
        await prepare(tester, width);
        installFixedPopoutHost(tester);
        final f = await fixture();
        addTearDown(f.w.dispose);
        await host(tester, f, null);
        final before = f.w.database.exportDataArchive(
          f.w.identity.businessId,
          DateTime.utc(2026, 10, 6),
        );
        await tap(tester, find.byKey(const ValueKey('claims-create')));
        expect(find.byType(ClaimEditorDialog), findsNothing);
        expect(find.byType(RecordExpensePage), findsOneWidget);
        expect(find.text('Unavailable'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message == 'Claim creation is currently unavailable.',
          ),
          findsNWidgets(2),
        );
        expect(find.textContaining('Reconnect'), findsNothing);
        for (final key in ['record-claim-save-draft', 'record-claim-submit']) {
          expect(
            tester
                .widget<ButtonStyleButton>(find.byKey(ValueKey(key)))
                .onPressed,
            isNull,
          );
        }
        expect(f.w.claims.all, isEmpty);
        await capture(tester, 'New Claim Unavailable Header ${width.toInt()}');
        await tester.ensureVisible(
          find.byKey(const ValueKey('expense-add-receipt-action')),
        );
        await tester.pumpAndSettle();
        await capture(
          tester,
          'New Claim Unavailable Receipts ${width.toInt()}',
        );
        await tap(tester, find.byKey(const ValueKey('record-expense-cancel')));
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(find.byType(RecordExpensePage), findsNothing);
        expect(
          f.w.database.exportDataArchive(
            f.w.identity.businessId,
            DateTime.utc(2026, 10, 6),
          ),
          before,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'uncertain creation retries the same claim and request identity',
    (tester) async {
      await prepare(tester, 1224);
      installFixedPopoutHost(tester);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final gateway = FixtureGateway(f, registration(f, 'accountant'))
        ..loseFirstAcknowledgement = true;
      await host(tester, f, gateway);
      await tap(tester, find.byKey(const ValueKey('claims-create')));
      await fill(tester);
      await tap(tester, find.byKey(const ValueKey('record-claim-save-draft')));
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(f.w.claims.all, hasLength(1));
      await tap(
        tester,
        find.byKey(const ValueKey('record-expense-retry-save')),
      );
      expect(find.byType(RecordExpensePage), findsNothing);
      expect(gateway.calls, hasLength(2));
      expect(gateway.calls.last.requestId, gateway.calls.first.requestId);
      expect(gateway.calls.last.claimId, gateway.calls.first.claimId);
      expect(
        gateway.calls.last.draft.toJson(),
        gateway.calls.first.draft.toJson(),
      );
      expect(gateway.acknowledgements, hasLength(1));
      expect(f.w.claims.all, hasLength(1));
      expect(await f.w.journals(), isEmpty);
    },
  );

  testWidgets('cross-company registered context cannot open Claim creation', (
    tester,
  ) async {
    await prepare(tester, 1224);
    final f = await fixture();
    addTearDown(f.w.dispose);
    final foreign = ServiceClaimantContext.fromJson({
      'businessId': '33333333-3333-4333-8333-333333333333',
      'actor': identity(actorId, 'accountant'),
      'claimants': [identity(actorId, 'accountant')],
    });
    final gateway = FixtureGateway(f, foreign);
    await host(tester, f, gateway);
    await tap(tester, find.byKey(const ValueKey('claims-create')));
    expect(find.byType(RecordExpensePage), findsNothing);
    expect(find.byType(ClaimEditorDialog), findsNothing);
    expect(gateway.calls, isEmpty);
    expect(f.w.claims.all, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changed registered actor blocks creation without losing entered facts',
    (tester) async {
      await prepare(tester, 1224);
      installFixedPopoutHost(tester);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final gateway = FixtureGateway(f, registration(f, 'accountant'));
      await host(tester, f, gateway);
      await tap(tester, find.byKey(const ValueKey('claims-create')));
      await fill(tester);
      gateway.context = ServiceClaimantContext.fromJson({
        'businessId': gateway.businessId,
        'actor': {...identity(actorId, 'accountant'), 'revision': 3},
        'claimants': [
          {...identity(actorId, 'accountant'), 'revision': 3},
          identity(claimantId, 'employee'),
        ],
      });
      await tap(tester, find.byKey(const ValueKey('claim-create-claimant')));
      await tester.enterText(
        find.byKey(const ValueKey('claim-create-claimant-search')),
        'Employee',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.text('Claimant lookup failed. Reopen the claim and try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Payee'));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('record-claim-save-draft')));
      expect(gateway.calls, isEmpty);
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(f.w.claims.all, isEmpty);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('expense-field-payee')),
            )
            .controller!
            .text,
        'Fictional Office Supplier',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new employee submits reviewed original bytes without local destination filing',
    (tester) async {
      await prepare(tester, 1224);
      installFixedPopoutHost(tester);
      final f = await fixture();
      addTearDown(f.w.dispose);
      final gateway = FixtureGateway(f, registration(f, 'employee'));
      final bytes = raster.encodePng(raster.Image(width: 40, height: 60));
      final filingCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        namingSettingsChannel,
        (call) async {
          filingCalls.add(call.method);
          throw StateError(
            'A Claim must not file locally before acknowledgement.',
          );
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          null,
        ),
      );
      await host(
        tester,
        f,
        gateway,
        picker: (_) async => [
          PickedExpenseAttachment(
            name: 'fictional-receipt.png',
            mimeType: 'image/png',
            bytes: bytes,
          ),
        ],
      );
      await tap(tester, find.byKey(const ValueKey('claims-create')));
      await fill(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('expense-add-receipt-action')),
      );
      await tester.pumpAndSettle();
      await realAction(
        tester,
        () => tester.tap(
          find.byKey(const ValueKey('expense-add-receipt-action')),
        ),
      );
      expect(find.byType(ReceiptReviewDialog), findsOneWidget);
      expect(
        tester
            .widget<ReceiptReviewDialog>(find.byType(ReceiptReviewDialog))
            .setupKind,
        isNull,
      );
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
      );
      await realAction(
        tester,
        () => tester.tap(find.byKey(const ValueKey('receipt-review-close'))),
        closesEditor: true,
      );
      expect(filingCalls, isEmpty);
      expect(find.byType(ReceiptReviewDialog), findsNothing);
      await tap(tester, find.byKey(const ValueKey('record-claim-submit')));
      expect(gateway.calls, hasLength(1));
      final command = gateway.calls.single;
      expect(command.intent, ClaimCreationIntent.submitForReview);
      final saved = f.w.claims.byId(command.claimId)!;
      expect(saved.status, ClaimStatus.submitted);
      expect(saved.attachments.single.originalBytes, bytes);
      expect(saved.expenseDraft!.reviewSnapshots, hasLength(1));
      expect(saved.claimantIdentity!.payeeId, actorId);
      expect(await f.w.journals(), isEmpty);
      expect(await f.w.expenses(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'employee command rejects another claimant and freezes the Expense body',
    () async {
      final f = await fixture();
      addTearDown(f.w.dispose);
      final self = registration(f, 'employee');
      final other = ServiceClaimant.fromJson(identity(claimantId, 'employee'));
      expect(
        () => ClaimExpenseCreationCommand(
          requestId: EntityId.random(),
          claimId: EntityId.random(),
          intent: ClaimCreationIntent.saveDraft,
          context: self,
          claimant: other,
          draft: maintainedBody(f),
        ),
        throwsArgumentError,
      );
      final body = maintainedBody(f);
      final command = ClaimExpenseCreationCommand(
        requestId: EntityId.random(),
        claimId: EntityId.random(),
        intent: ClaimCreationIntent.submitForReview,
        context: self,
        claimant: self.actor,
        draft: body,
      );
      final frozen = command.draft.toJson();
      expect(() => body.lines.clear(), throwsUnsupportedError);
      final editableCopy = command.draft.toJson();
      (editableCopy['lines'] as List).clear();
      expect(command.draft.toJson(), frozen);
      expect(command.validationClaim.submissionErrors, isEmpty);
    },
  );
}
