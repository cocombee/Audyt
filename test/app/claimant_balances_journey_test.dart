import 'package:audyt/app/app.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/claimant_statements_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/claim_recognition_reversal_test.dart'
    show claimFixture;
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  testWidgets(
    'open liability details retain one report snapshot during refresh',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await claimFixture();
      await tester.pumpWidget(
        AudytApp(
          workspace: f.w,
          initialPath: '/claims',
          showInitialSetup: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('claims-balances')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('claimant-from')),
        '01-09-2026',
      );
      await tester.enterText(
        find.byKey(const ValueKey('claimant-through')),
        '30-09-2026',
      );
      await tester.tap(find.byKey(const ValueKey('claimant-run')));
      await tester.pumpAndSettle();
      final view = find.byKey(ValueKey('claimant-control-${f.payable.value}'));
      await tester.ensureVisible(view);
      await tester.tap(view);
      await tester.pumpAndSettle();
      expect(find.text(f.source.value), findsOneWidget);

      final reversal = EntityId.random();
      f.w.reverseClaimRecognition(
        reviewedClaim: f.approved,
        requestId: reversal,
        expectedRecognitionJournalId: f.source,
        decision: ClaimRecognitionDecision.returnForCorrection,
        reversedOn: DateTime.utc(2026, 9, 15),
        reason: 'Review corrected receipt facts',
        changedAt: DateTime.utc(2026, 9, 15, 12),
      );
      await tester.pumpAndSettle();
      // Force the open dialog to rebuild after the parent report refreshed.
      tester.view.physicalSize = const Size(1224, 1000);
      ModalRoute.of(tester.element(find.text('Ledger Closing Credit')))!
          .changedExternalState();
      await tester.pumpAndSettle();
      expect(find.text(f.source.value), findsOneWidget);
      expect(find.text(reversal.value), findsNothing);

      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(view);
      await tester.tap(view);
      await tester.pumpAndSettle();
      expect(find.text(reversal.value), findsOneWidget);
      expect(find.text(f.source.value), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'live Claims claimant balances and journal trace are read-only at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final f = await claimFixture();
        final before = tables(f.w);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(
              workspace: f.w,
              initialPath: '/claims',
              showInitialSetup: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('claims-balances')));
        await tester.pumpAndSettle();
        expect(find.byType(ClaimantStatementsDialog), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('claimant-from')),
          '01-09-2026',
        );
        await tester.enterText(
          find.byKey(const ValueKey('claimant-through')),
          '30-09-2026',
        );
        await tester.tap(find.byKey(const ValueKey('claimant-run')));
        await tester.pumpAndSettle();
        expect(find.text('RM 12.50'), findsWidgets);
        expect(
          find.text('Unlinked Recorded Name · Separate Claim'),
          findsOneWidget,
        );
        await captureUi(tester, 'Claimant Balances ${width.toInt()}');
        await tester.tap(
          find.byKey(ValueKey('claimant-view-unlinked:${f.approved.id.value}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Approved Claim'), findsOneWidget);
        expect(find.text(f.source.value), findsOneWidget);
        expect(find.text(f.approved.id.value), findsOneWidget);
        await captureUi(tester, 'Claimant Statement ${width.toInt()}');
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(ValueKey('claimant-control-${f.payable.value}')),
        );
        await tester.tap(
          find.byKey(ValueKey('claimant-control-${f.payable.value}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ledger Closing Credit'), findsOneWidget);
        expect(find.text(f.source.value), findsOneWidget);
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('claimant-from')));
        await tester.enterText(
          find.byKey(const ValueKey('claimant-from')),
          '01-10-2026',
        );
        await tester.tap(find.byKey(const ValueKey('claimant-run')));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter valid dates with the start on or before the end.'),
          findsOneWidget,
        );
        expect(tables(f.w), before);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('claimant-from')));
        await tester.enterText(
          find.byKey(const ValueKey('claimant-from')),
          '01-08-2026',
        );
        await tester.enterText(
          find.byKey(const ValueKey('claimant-through')),
          '31-08-2026',
        );
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const ValueKey('claimant-run'))),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('claimant-run')));
        await tester.pumpAndSettle();
        final emptyClaims = find.text(
          'No recognized claims through this date.',
        );
        expect(emptyClaims, findsOneWidget);
        await tester.ensureVisible(emptyClaims);
        await tester.pumpAndSettle();
        await captureUi(tester, 'Claimant Balances Empty ${width.toInt()}');
        expect(tables(f.w), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
