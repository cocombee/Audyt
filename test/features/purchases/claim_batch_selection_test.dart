import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';

import '../../app/claim_receipts_proposal_test.dart' show prepare;

import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';

void main() {
  testWidgets(
    'draft and submitted claims can be selected without becoming payable',
    (tester) async {
      await prepare(tester, 1224);
      final fixtures = [...ClaimStore.demo().all];
      while (fixtures.length < 6) {
        fixtures.add(
          Claim.fromJson({
            ...fixtures.first.toJson(),
            'id': EntityId.random().value,
          }),
        );
      }
      final store = ClaimStore(claims: fixtures);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: ClaimsPage(store: store)),
        ),
      );
      final firstRow = find.byKey(ValueKey('claim-row-${store.all.first.id}'));
      final firstTitle = find.byKey(
        ValueKey('claim-payee-${store.all.first.id}'),
      );
      final firstDetails = find.descendant(
        of: firstRow,
        matching: find.textContaining('Claimant:'),
      );
      final titleInset =
          tester.getTopLeft(firstTitle).dy - tester.getTopLeft(firstRow).dy;
      final detailsInset =
          tester.getTopLeft(firstDetails).dy - tester.getTopLeft(firstRow).dy;
      await tester.tap(find.byKey(const ValueKey('claims-select-payment')));
      await tester.pump();
      expect(
        tester.getTopLeft(firstTitle).dy - tester.getTopLeft(firstRow).dy,
        titleInset,
      );
      expect(
        tester.getTopLeft(firstDetails).dy - tester.getTopLeft(firstRow).dy,
        detailsInset,
      );

      final selectionHit = tester.widget<InkWell>(
        find.byKey(ValueKey('claim-selection-hit-${store.all.first.id}')),
      );
      expect(
        selectionHit.overlayColor?.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      final checkboxContext = tester.element(
        find.byKey(ValueKey('claim-payment-select-${store.all.first.id}')),
      );
      expect(
        Theme.of(checkboxContext).checkboxTheme.overlayColor
            ?.resolve({WidgetState.hovered}),
        Theme.of(checkboxContext).colorScheme.primary.withValues(alpha: 0.12),
      );

      for (final claim in store.all.take(2)) {
        final checkbox = find.byKey(
          ValueKey('claim-payment-select-${claim.id}'),
        );
        final row = find.byKey(ValueKey('claim-row-${claim.id}'));
        expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);
        expect(tester.getTopLeft(checkbox).dx - tester.getTopLeft(row).dx, 20);
        final title = tester.getRect(
          find.byKey(ValueKey('claim-payee-${claim.id}')),
        );
        final details = tester.getRect(
          find.descendant(of: row, matching: find.textContaining('Claimant:')),
        );
        expect(
          tester.getCenter(checkbox).dy,
          closeTo((title.top + details.bottom) / 2, 2),
        );
        await tester.tap(checkbox);
        await tester.pump();
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      }
      expect(find.text('Record Payment (2)'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('claims-pay-selected')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('select approved claims and record one reference for both', (
    tester,
  ) async {
    await prepare(tester, 1224);
    final first = ClaimStore.demo().all.first;
    final second = Claim.fromJson({
      ...first.toJson(),
      'id': EntityId.random().value,
    });
    final store = ClaimStore(
      claims: [
        first.submit().approve(),
        second.submit().approve(),
        for (var i = 0; i < 4; i++)
          Claim.fromJson({...first.toJson(), 'id': EntityId.random().value}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: ClaimsPage(store: store)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('claims-select-payment')));
    await tester.pump();
    for (final claim in [first, second]) {
      await tester.tap(
        find.byKey(ValueKey('claim-payment-select-${claim.id}')),
      );
      await tester.pump();
    }
    expect(find.text('Record Payment (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('claims-pay-selected')));
    await tester.pumpAndSettle();
    for (final claim in [first, second]) {
      expect(
        find.byKey(ValueKey('claim-allocation-${claim.id.value}')),
        findsOneWidget,
      );
    }
    await tester.enterText(
      find.byKey(const ValueKey('claims-batch-reference')),
      'REIMBURSE-SEP-001',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('claims-batch-confirm')));
    await tester.pumpAndSettle();
    final paid = [store.byId(first.id)!, store.byId(second.id)!];
    expect(paid.every((c) => c.status == ClaimStatus.paid), isTrue);
    expect(store.all.where((c) => c.status == ClaimStatus.draft), hasLength(4));
    expect(paid.map((c) => c.paymentBatchId).toSet(), hasLength(1));
    expect(
      paid.every((c) => c.paymentReference == 'REIMBURSE-SEP-001'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
