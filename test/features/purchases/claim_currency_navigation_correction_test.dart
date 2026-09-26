import 'package:audyt/app/app.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'passes the shared accounting currency into Claim without a visible selector',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1400));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const AudytApp(initialPath: '/claims', accountCurrencyCode: 'USD'),
      );
      await tester.tap(find.byKey(const ValueKey('claims-create')));
      await tester.pumpAndSettle();

      expect(find.text(r'Amount ($)'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('claim-amount')),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .prefix,
        isNull,
      );
      expect(find.text('RM'), findsNothing);
      expect(
        find.byKey(const ValueKey('claim-currency-selector')),
        findsNothing,
      );
      expect(find.text('Currency'), findsNothing);
    },
  );

  testWidgets(
    'stores the configured Claim currency in the Money model when saving a draft',
    (tester) async {
      final store = ClaimStore(claims: const []);
      await tester.binding.setSurfaceSize(const Size(960, 1400));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ClaimsPage(store: store, defaultCurrencyCode: 'USD'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('claims-create')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('claim-claimant')),
        'Aina Rahman',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('claim-claimant-option-demo-payee-aina-rahman'),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('claim-payee')),
        'Acme Office Supplies',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'claim-merchant-option-demo-payee-acme-office-supplies',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('claim-amount')),
        '12.50',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('claim-category')));
      await tester.tap(find.byKey(const ValueKey('claim-category')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('claim-category-option-office-supplies')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('claim-save-draft')),
      );
      await tester.tap(find.byKey(const ValueKey('claim-save-draft')));
      await tester.pumpAndSettle();

      expect(store.all, hasLength(1));
      expect(store.all.single.amount.currency, 'USD');
      expect(store.all.single.amount.minorUnits, 1250);
      expect(
        store.all.single.claimantIdentity?.payeeId,
        'demo-payee-aina-rahman',
      );
      expect(store.all.single.claimantIdentity?.type, ClaimantType.staff);
    },
  );

  testWidgets(
    'preserves an existing Claim currency when editing without a Claim selector',
    (tester) async {
      final claimId = EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8cf120');
      final store = ClaimStore(
        claims: <Claim>[
          Claim.draft(
            id: claimId,
            vendorName: 'Acme Office Supplies',
            amount: Money.fromMinor(1250, 'USD'),
            claimantName: 'Aina Rahman',
            incurredOn: DateTime.utc(2026, 8, 31),
            category: 'Office Supplies & Small Equipment',
            claimCategoryCode: 'office-supplies',
            expenseCategoryCode: 'office-supplies-small-equipment',
            expenseAccountCode: 'expense.office-supplies-small-equipment',
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(960, 1400));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ClaimsPage(store: store, defaultCurrencyCode: 'MYR'),
        ),
      );
      final editAction = find.byKey(ValueKey<String>('claim-edit-$claimId'));
      await tester.ensureVisible(editAction);
      await tester.tap(editAction);
      await tester.pumpAndSettle();

      expect(find.text(r'Amount ($)'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('claim-amount')),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .prefix,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('claim-amount')))
            .controller!
            .text,
        '12.50',
      );
      expect(
        find.byKey(const ValueKey('claim-currency-selector')),
        findsNothing,
      );
      expect(find.text('Currency'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('claim-save-draft')));
      await tester.pumpAndSettle();

      expect(store.byId(claimId)?.amount.currency, 'USD');
      expect(store.byId(claimId)?.amount.minorUnits, 1250);
    },
  );
}
