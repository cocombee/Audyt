import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/accounting/domain/payee.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('legacy edit retains claimant without quick-add at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = ClaimStore.demo();
      addTearDown(store.dispose);
      final initial = store.all.firstWhere(
        (claim) => claim.status == ClaimStatus.draft,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: ClaimsPage(store: store),
        ),
      );
      await tester.pumpAndSettle();
      final edit = find.byKey(ValueKey('claim-edit-${initial.id}'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('claim-claimant-autocomplete')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('claim-expense-claimant')),
        findsOneWidget,
      );
      expect(find.byType(RecordExpensePage), findsOneWidget);
      expect(find.byType(ClaimEditorDialog), findsNothing);
      expect(find.text('Add Claimant'), findsNothing);
      expect(store.byId(initial.id)!.claimantName, initial.claimantName);
      expect(tester.takeException(), isNull);
    });

    testWidgets('legacy quick-add excludes Employee at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final payees = PayeeStore(payees: PayeeCatalog.demo);
      final before = payees.all.length;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: ClaimEditorDialog(
              id: EntityId.parse('018f0c4e-56f1-7d4a-b9bb-6e2d6b8c5b99'),
              payeeStore: payees,
              onSaveDraft: (_) {},
              onSubmit: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('claim-claimant')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('claim-add-claimant')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('claim-add-payee-type')));
      await tester.pumpAndSettle();
      expect(find.text('Employee'), findsNothing);
      expect(find.text('Director'), findsWidgets);
      expect(payees.all.length, before);
      expect(tester.takeException(), isNull);
    });
  }
}
