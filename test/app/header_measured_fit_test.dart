import 'dart:convert';
import 'dart:typed_data';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/bank_statement_import.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('page header measures live action changes at $width', (
      tester,
    ) async {
      await prepare(tester, width);
      var long = false;
      var calls = 0;
      late StateSetter update;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: AccountingPageShell(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return AccountingPageHeader(
                      routeLabel: 'Header Fit',
                      title: 'Accounting Workspace Review',
                      description: 'Review the current records and retain the established title and action spacing.',
                      action: AccountingButton.primary(
                        context,
                        key: const ValueKey('measured-header-action'),
                        onPressed: () => calls++,
                        child: Text(
                          long
                              ? 'Review All Outstanding Accounting Records And Approvals'
                              : 'Add',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('Accounting Workspace Review');
      final action = find.byKey(const ValueKey('measured-header-action'));
      final shortTop = tester.getTopLeft(action).dy;
      expect(shortTop, closeTo(tester.getTopLeft(title).dy, 0.1));
      await tester.tap(action);
      expect(calls, 1);
      update(() => long = true);
      await tester.pumpAndSettle();
      final header = tester.getRect(
        find.byKey(const ValueKey('accounting-page-header')),
      );
      final frame = tester.getRect(action);
      if (width == 720) {
        expect(frame.top, greaterThan(tester.getBottomLeft(title).dy));
      } else {
        expect(frame.top, closeTo(tester.getTopLeft(title).dy, 0.1));
      }
      expect(frame.right, closeTo(header.right, 0.1));
      expect(tester.takeException(), isNull);
      await capture(tester, 'Measured Page Header ${width.toInt()}');
      update(() => long = false);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(action).dy, closeTo(shortTop, 0.1));
      await tester.tap(action);
      expect(calls, 2);
    });

    testWidgets(
      'bank filename header fits its real title and action group at $width',
      (tester) async {
        await prepare(tester, width);
        final w = await createDemoWorkspace();
        addTearDown(w.dispose);
        final name =
            'Fictional Bank September Statement With A Longer Filename.csv';
        final id = EntityId.random();
        w.database.importBankStatement(
          id: id,
          businessId: w.identity.businessId,
          paymentAccountId: 'demo-bank',
          importedAt: DateTime.utc(2026, 9, 30),
          statement: BankStatementImport.csv(
            filename: name,
            currency: 'MYR',
            bytes: Uint8List.fromList(
              utf8.encode(
                'Date,Description,Amount\n2026-09-01,Fictional payment,-10.00',
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: BankingPage(workspace: w, compact: true)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openStatementReview(tester, statementId: id.value);
        final header = find.byKey(
          const ValueKey('statement-match-file-header'),
        );
        final title = find.descendant(of: header, matching: find.text(name));
        final back = find.byKey(const ValueKey('review-back-to-documents'));
        final titleRect = tester.getRect(title);
        final backRect = tester.getRect(back);
        final headerRect = tester.getRect(header);
        expect(
          titleRect.left,
          closeTo(headerRect.left + accountingContentInset, 0.1),
        );
        expect(
          backRect.right,
          closeTo(headerRect.right - accountingContentInset, 0.1),
        );
        if (width == 720) {
          expect(backRect.top, greaterThan(titleRect.bottom));
        } else {
          expect(backRect.top, lessThan(titleRect.bottom));
        }
        expect(tester.takeException(), isNull);
        await capture(tester, 'Measured Bank File Header ${width.toInt()}');
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(header, findsNothing);
        final short = w.database
            .bankStatements(w.identity.businessId, 'demo-bank')
            .singleWhere((s) => s.filename == 'Demo Bank.csv');
        await openStatementReview(tester, statementId: short.id.value);
        final shortTitle = find.descendant(
          of: header,
          matching: find.text('Demo Bank.csv'),
        );
        expect(
          tester.getRect(back).top,
          lessThan(tester.getRect(shortTitle).bottom),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
