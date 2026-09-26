import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/recurring_transactions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

void main() {
  testWidgets(
    'recurring popout aligns New with filter frames and has no Close footer',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = await createDemoWorkspace(includeRowReview: true);
      addTearDown(workspace.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: RecurringTransactionsDialog(workspace: workspace),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filters = find.byWidgetPredicate(
        (w) =>
            w is AccountingSelector<String> &&
            w.semanticsLabel == 'Filter by Status',
      );
      final action = find.byKey(const ValueKey('recurring-new'));
      expect(filters, findsOneWidget);
      expect(
        tester.getRect(action).bottom,
        closeTo(tester.getRect(filters).bottom, .01),
      );
      expect(
        tester.getRect(action).right,
        closeTo(tester.getRect(find.byType(AccountingControlFlow)).right, .01),
      );
      expect(
        find.byKey(const ValueKey('accounting-form-dialog-footer')),
        findsNothing,
      );
      expect(find.text('Close'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'recurring end conditions reflow and save only active limit at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final output = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
        if (output != null) {
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
        final w = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
        addTearDown(w.dispose);
        final source = w.invoiceDrafts().first;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('recurring-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: RecurringTransactionsDialog(workspace: w)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('recurring-new')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('design-field-Schedule Name')),
          'Monthly Review Example',
        );
        await tester.tap(
          find.byKey(const ValueKey('design-field-Source Transaction')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(source.invoice.documentNumber).last,
        );
        await tester.pumpAndSettle();
        final endDate = find.byKey(const ValueKey('design-field-End Date'));
        final count = find.byKey(
          const ValueKey('design-field-Occurrence Count'),
        );
        Future<void> selectEnd(String choice) async {
          await tester.tap(find.byKey(const ValueKey('design-field-Ends')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(choice).last);
          await tester.pumpAndSettle();
        }

        Future<void> capture(String state) async {
          for (final label in [
            'Schedule Name',
            'Repeat',
            'Ends',
            'Preserve Month End',
            if (state == 'After Occurrences') 'Occurrence Count',
          ]) {
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is AccountingFieldHelp &&
                    widget.label.replaceAll(' *', '') == label,
              ),
              findsOneWidget,
              reason:
                  'The actual conditional schedule owner must expose $label guidance.',
            );
          }
          expect(tester.takeException(), isNull);
          if (output == null) return;
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('recurring-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/Recurring Schedule $state ${width.round()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        expect(endDate, findsNothing);
        expect(count, findsNothing);
        await capture('Never');
        await selectEnd('On Date');
        expect(endDate, findsOneWidget);
        expect(count, findsNothing);
        await tester.enterText(endDate, '30-09-2030');
        await tester.pumpAndSettle();
        await capture('On Date');
        await selectEnd('After Occurrences');
        expect(endDate, findsNothing);
        expect(count, findsOneWidget);
        await tester.enterText(count, '3');
        await tester.pumpAndSettle();
        await capture('After Occurrences');
        await selectEnd('On Date');
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: endDate, matching: find.byType(TextField)),
              )
              .controller!
              .text,
          '30-09-2030',
        );
        await selectEnd('After Occurrences');
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: count, matching: find.byType(TextField)),
              )
              .controller!
              .text,
          '3',
        );
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        expect(find.text('End Date'), findsNothing);
        expect(find.text('Occurrence Count'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        final saved = w.database
            .documentSchedules(w.identity.businessId)
            .single;
        expect(saved.schedule.endsOn, isNull);
        expect(saved.schedule.occurrenceCount, 3);
        expect(saved.sourceId, source.invoice.id.value);
        expect(saved.schedule.occurrenceAt(3), isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual recurring manager creates schedule and one draft at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadJournalLayoutFonts();
        final w = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
        addTearDown(w.dispose);
        final source = w.invoiceDrafts().first;
        final before = (await w.journals()).length;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: RecurringTransactionsDialog(workspace: w)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountingRecordPagination), findsNothing);
        await tester.tap(find.byKey(const ValueKey('recurring-new')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('design-field-Schedule Name')),
          'Monthly Review Example',
        );
        await tester.tap(
          find.byKey(const ValueKey('design-field-Source Transaction')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining(source.invoice.documentNumber).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        final schedule = w.database
            .documentSchedules(w.identity.businessId)
            .single;
        expect(schedule.name, 'Monthly Review Example');
        await tester.tap(find.byKey(ValueKey('recurring-view-${schedule.id}')));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Recurring Saved Facts ${width.toInt()}');
        await tester.tap(
          find.byKey(ValueKey('prepare-occurrence-${schedule.id}')),
        );
        await tester.pumpAndSettle();
        expect(
          w.database.documentOccurrences(w.identity.businessId, schedule.id),
          hasLength(1),
        );
        expect(w.invoiceDrafts().length, 2);
        expect((await w.journals()).length, before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
