import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('live report replaces preview without a duplicate tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: FrontendAreaPage(
            area: 'reports',
            title: 'Reports',
            initialPage: 'Receivables Ageing',
            existingLabel: 'Ledger Reports',
            existing: Text('Live ledger'),
            extraPages: {'Receivables Ageing': Text('Live ageing report')},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receivables Ageing'), findsOneWidget);
    expect(find.text('Live ageing report'), findsOneWidget);
    expect(find.byKey(const ValueKey('design-open-form')), findsNothing);
    await tester.ensureVisible(find.text('Ledger Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ledger Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Live ledger'), findsOneWidget);
    await tester.ensureVisible(find.text('Receivables Ageing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receivables Ageing'));
    await tester.pumpAndSettle();
    expect(find.text('Live ageing report'), findsOneWidget);
  });

  testWidgets('preview note follows the record content inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: DemoCompany(
            child: FrontendAreaPage(
              area: 'taxes',
              title: 'Taxes',
              initialPage: 'Tax Overview',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final note = find.text(
      'Preview records last only while this screen is open. Existing accounting records are unaffected.',
    );
    await tester.ensureVisible(note);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(note).dx,
      closeTo(tester.getTopLeft(find.text('DEMO-TAXOVERVIEW-2')).dx, 0.01),
    );
  });
}
