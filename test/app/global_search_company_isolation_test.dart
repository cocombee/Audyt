import 'package:audyt/app/accounting_global_search.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/domain/recurrence_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restored_page_routes_test.dart' show tables;

void main() {
  Future<AccountingWorkspace> company(String marker) async {
    final workspace = await createDemoWorkspace();
    addTearDown(workspace.dispose);
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: '$marker-payment-account',
        name: '$marker Payment Account',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    await workspace.saveExpenseIntake(
      RecordExpenseDraft(
        submissionId: '$marker-recurring-expense',
        amount: '25.00',
        date: '28-09-2026',
        payee: '$marker Recurring Expense',
        paymentAccount: 'Demo Bank',
        paymentAccountId: 'demo-bank',
        recurrence: RecurrenceRule(
          startsOn: DateTime.utc(2026, 10, 1),
          unit: RecurrenceUnit.months,
          every: 1,
          occurrenceCount: 3,
        ),
        category: 'Office Supplies',
        tax: 'Out Of Scope',
        customer: '',
        billable: false,
        dimensions: '',
        itemOrSplitDetails: '',
        notes: '',
      ),
    );
    return workspace;
  }

  test(
    'every record search category stays within the selected company',
    () async {
      final alpha = await company('AlphaOnly');
      final beta = await company('BetaOnly');
      expect(alpha.identity.businessId, isNot(beta.identity.businessId));
      final alphaBefore = tables(alpha);
      final betaBefore = tables(beta);

      Future<List<AccountingSearchResult>> load(
        AccountingWorkspace workspace,
      ) => loadNonJournalSearchResults(
        claims: workspace.claims,
        vouchers: workspace.vouchers,
        workspace: workspace,
      );

      final alphaResults = await load(alpha);
      final betaResults = await load(beta);
      final uuid = RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      );
      for (final type in [
        'Claim',
        'Payment Voucher',
        'Expense',
        'Recurring Expense',
        'Customer',
        'Invoice Draft',
        'Invoice',
        'Credit Note',
        'Account',
        'Bank Statement',
        'Customer Receipt',
      ]) {
        final a = alphaResults.where((result) => result.type == type).toList();
        final b = betaResults.where((result) => result.type == type).toList();
        expect(a, isNotEmpty, reason: '$type missing from Alpha search');
        expect(b, isNotEmpty, reason: '$type missing from Beta search');
        final alphaId =
            uuid.firstMatch(a.first.extraTerms)?.group(0) ??
            uuid.firstMatch(a.first.detail)?.group(0);
        final betaId =
            uuid.firstMatch(b.first.extraTerms)?.group(0) ??
            uuid.firstMatch(b.first.detail)?.group(0);
        expect(alphaId, isNotNull, reason: '$type missing Alpha record ID');
        expect(betaId, isNotNull, reason: '$type missing Beta record ID');
        expect(alphaId, isNot(betaId), reason: '$type uses shared record ID');
        expect(a.any((result) => result.matches(alphaId!)), isTrue);
        expect(
          b.any((result) => result.matches(alphaId!)),
          isFalse,
          reason: '$type leaked from Alpha to Beta',
        );
        expect(b.any((result) => result.matches(betaId!)), isTrue);
        expect(
          a.any((result) => result.matches(betaId!)),
          isFalse,
          reason: '$type leaked from Beta to Alpha',
        );
      }

      for (final (own, other, marker) in [
        (alphaResults, betaResults, 'AlphaOnly'),
        (betaResults, alphaResults, 'BetaOnly'),
      ]) {
        for (final type in ['Payment Account', 'Recurring Expense']) {
          expect(
            own.any((result) => result.type == type && result.matches(marker)),
            isTrue,
          );
          expect(
            other.any(
              (result) => result.type == type && result.matches(marker),
            ),
            isFalse,
            reason: '$type leaked across companies',
          );
        }
      }
      expect(tables(alpha), alphaBefore);
      expect(tables(beta), betaBefore);
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets('expense suggestions stay in the selected company at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final alpha = await company('AlphaOnly');
      final beta = await company('BetaOnly');
      final alphaBefore = tables(alpha);
      final betaBefore = tables(beta);

      Future<void> search(String value) async {
        await tester.enterText(
          find.byKey(const ValueKey('global-search-field')),
          value,
        );
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(AudytApp(workspace: alpha));
      await tester.pumpAndSettle();
      await search('AlphaOnly MYR:2500');
      expect(
        find.widgetWithText(ListTile, 'AlphaOnly Recurring Expense'),
        findsOneWidget,
      );
      await tester.pumpWidget(AudytApp(workspace: beta));
      await tester.pumpAndSettle();
      await search('AlphaOnly MYR:2500');
      expect(
        find.widgetWithText(ListTile, 'AlphaOnly Recurring Expense'),
        findsNothing,
      );
      await search('BetaOnly MYR:2500');
      expect(
        find.widgetWithText(ListTile, 'BetaOnly Recurring Expense'),
        findsOneWidget,
      );
      expect(tables(alpha), alphaBefore);
      expect(tables(beta), betaBefore);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('voucher source choices follow the active company at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final alpha = await company('AlphaOnly');
      final beta = await company('BetaOnly');
      final alphaBefore = tables(alpha);
      final betaBefore = tables(beta);

      Future<void> openSources(AccountingWorkspace workspace) async {
        await tester.pumpWidget(
          DemoCompany(
            child: AudytApp(
              workspace: workspace,
              initialPath: '/payment-vouchers',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('payment-voucher-editor-dialog')),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('payment-voucher-create')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('voucher-source-selector')));
        await tester.pumpAndSettle();
      }

      await openSources(alpha);
      expect(find.textContaining('AlphaOnly Recurring Expense'), findsWidgets);
      expect(find.textContaining('BetaOnly Recurring Expense'), findsNothing);
      await openSources(beta);
      expect(find.textContaining('BetaOnly Recurring Expense'), findsWidgets);
      expect(find.textContaining('AlphaOnly Recurring Expense'), findsNothing);
      expect(tables(alpha), alphaBefore);
      expect(tables(beta), betaBefore);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
