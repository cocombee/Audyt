import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/linked_record_review.dart';

void main() {
  testWidgets(
    'refund uses remaining source balance and rejects excess without upload',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadJournalLayoutFonts();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: const Scaffold(body: LinkedRecordReview(workflow: 'Refunds')),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('load-linked-examples')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('linked-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Example 002 · Partial Balance').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('linked-amount')))
            .controller!
            .text,
        '400.00',
      );
      expect(find.text('Choose Files'), findsNothing);
      await captureUi(tester, 'Linked Refund Currency Heading');
      await tester.enterText(
        find.byKey(const ValueKey('linked-amount')),
        '401.00',
      );
      await tester.tap(find.byKey(const ValueKey('review-linked-record')));
      await tester.pumpAndSettle();
      expect(find.textContaining('no more than RM 400.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
