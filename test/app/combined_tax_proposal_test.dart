import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/tax_remittance_wiring_test.dart' show setup;
import '../support/accounting_test_finders.dart';
import 'restored_page_routes_test.dart' show tables;
import 'tax_remittance_proposal_test.dart' as payments;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'combined agency/payment owners retain source facts and exact ledger trace at $width',
      (t) async {
        final f = await setup(), w = f.w;
        addTearDown(w.dispose);
        final saved = f.record(300);
        final before = tables(w);
        await payments.host(t, w, width);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: TaxOverviewPage(
                  workspace: w,
                  agencyProposal: true,
                  taxPaymentsProposal: true,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('tax-overview-from')),
          '01-09-2026',
        );
        await t.enterText(
          find.byKey(const ValueKey('tax-overview-through')),
          '30-09-2026',
        );
        await payments.tap(t, find.byKey(const ValueKey('tax-overview-run')));
        expect(find.text('Record Tax Payment'), findsOneWidget);
        expect(
          find.text('Recorded Tax Payments — Net of Reversals'),
          findsNWidgets(2),
        );
        expect(
          find.text('${f.agency.name} · Revision ${f.agency.revision}'),
          findsOneWidget,
        );
        final agencyCard = find.ancestor(
          of: find.text('${f.agency.name} · Revision ${f.agency.revision}'),
          matching: find.byType(AccountingSummaryTableCard),
        );
        expect(
          find.descendant(of: agencyCard, matching: find.text('RM 3.00')),
          findsOneWidget,
        );
        await payments.capture(t, 'Combined Tax Overview ${width.toInt()}');

        final report = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 9, 30),
        );
        final source = report.rows.single;
        await payments.tap(
          t,
          find.byKey(
            ValueKey(
              'tax-source-view-${source.journalId.value}-${source.lineId}',
            ),
          ),
        );
        expect(find.text('Tax Agency'), findsOneWidget);
        expect(find.text(f.agency.name), findsOneWidget);
        expect(find.text('Agency Revision'), findsOneWidget);
        await payments.capture(t, 'Combined Tax Source Facts ${width.toInt()}');
        await payments.tap(t, accountingCloseIcon());

        await payments.tap(
          t,
          find.byKey(ValueKey('tax-payment-view-${saved.id.value}')),
        );
        expect(find.text('Recorded In Books'), findsOneWidget);
        expect(find.text(saved.journalId.value), findsNWidgets(2));
        await payments.capture(
          t,
          'Combined Tax Payment Facts ${width.toInt()}',
        );
        await payments.tap(t, accountingCloseIcon());

        await payments.tap(
          t,
          find.byKey(ValueKey('tax-account-view-${f.sales.tax.value}')),
        );
        expect(find.text('Recorded Tax Payments'), findsWidgets);
        expect(find.text(saved.journalId.value), findsOneWidget);
        await payments.capture(t, 'Combined Tax Ledger Trace ${width.toInt()}');
        expect(report.remittedTax, BigInt.from(300));
        expect(
          report.accounts.single.closingCredit,
          report.accounts.single.openingCredit +
              report.accounts.single.sourceSalesTax +
              report.accounts.single.otherMovementCredit,
        );
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      },
    );
  }
}
