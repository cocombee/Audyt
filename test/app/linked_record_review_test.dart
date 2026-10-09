import 'dart:math' as math;

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/linked_record_review.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/frontend_catalog.dart';

import 'frontend_catalog_test.dart' show openForm;

void main() {
  for (final width in [720.0, 1162.0, 1224.0]) {
    for (final workflow in [
      'Refunds',
      'Credit Notes',
      'Receive Payment',
      'Pay Bills',
    ]) {
      testWidgets(
        'linked $workflow actual preview route keeps detail in helpers at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 809);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadJournalLayoutFonts();
          await openForm(
            tester,
            frontendAreas.values
                .expand((v) => v)
                .singleWhere((f) => f.title == workflow),
          );
          expect(find.byType(LinkedRecordReview), findsOneWidget);
          final frame = find
              .descendant(
                of: find.byType(AlertDialog).last,
                matching: find.byWidgetPredicate(
                  (v) => v is Material && v.type == MaterialType.card,
                ),
              )
              .first;
          expect(
            tester.getSize(frame).width,
            closeTo(
              math.min(
                AccountingPopoutTokens.normalContentWidth +
                    AccountingPopoutTokens.contentInset * 2,
                width - AccountingPopoutTokens.windowInsets.horizontal,
              ),
              .01,
            ),
          );
          await captureUi(
            tester,
            'Linked $workflow Normal Initial ${width.toInt()}',
          );
          await tester.tap(find.byKey(const ValueKey('load-linked-examples')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('linked-source')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Example 002 · Partial Balance').last);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Example only; no file is attached.'),
            findsOneWidget,
          );
          for (final label in [
            if (workflow == 'Credit Notes') 'Credit Amount (RM)',
            'Existing Evidence',
          ]) {
            final help = find.byWidgetPredicate(
              (widget) =>
                  widget is AccountingFieldHelp && widget.label == label,
            );
            final message = tester.widget<AccountingFieldHelp>(help).message;
            expect(find.text(message), findsNothing);
            await tester.ensureVisible(help);
            await tester.tap(help);
            await tester.pumpAndSettle();
            expect(find.text(message), findsOneWidget);
            await captureUi(
              tester,
              'Linked $workflow $label Helper ${width.toInt()}',
            );
            Tooltip.dismissAllToolTips();
            await tester.pumpAndSettle();
          }
          expect(
            find.text('Design preview · No live records are loaded or posted.'),
            findsOneWidget,
          );
          if (workflow == 'Credit Notes') {
            expect(
              find.text(
                'Credit adjusts the source balance; no cash is refunded.',
              ),
              findsOneWidget,
            );
          }
          await captureUi(
            tester,
            'Linked $workflow Normal Selected ${width.toInt()}',
          );
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('linked-amount')))
                .controller!
                .text,
            '400.00',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
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
