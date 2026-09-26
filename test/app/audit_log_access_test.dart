import '../support/accounting_test_finders.dart';

import 'package:audyt/app/accounting_components.dart';

import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'package:audyt/app/naming_setup.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/audit_log_dialog.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  setUp(AccountingRecordPageSizes.reset);
  tearDown(AccountingRecordPageSizes.reset);
  for (final width in [720.0, 1224.0]) {
    for (final count in [0, 5, 6]) {
      testWidgets('Audit $count records and growing details at $width', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final dir = Directory.systemTemp.createTempSync('audit-threshold-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final workspace = await AccountingWorkspace.open(
          '${dir.path}/ledger.sqlite',
        );
        addTearDown(workspace.dispose);
        for (var day = 1; day <= count; day++) {
          await workspace.database.closeThrough(
            businessId: workspace.identity.businessId,
            date: DateTime.utc(2026, 8, day),
            actorId: workspace.identity.ownerId,
            changedAt: DateTime.utc(2026, 9, day),
            reason: List.filled(
              20,
              'Reviewed closing evidence and supporting records.',
            ).join(' '),
          );
        }
        Widget host() => RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: AuditLogDialog(workspace: workspace)),
          ),
        );
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        final visible = count >= 6;
        expect(
          find.byKey(const ValueKey('audit-kind')),
          visible ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('audit-from')),
          visible ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('audit-page-next')),
          visible ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('accounting-form-dialog-footer')),
          findsNothing,
        );
        if (visible) {
          expect(find.text('1–5 of 6'), findsOneWidget);
          for (final hint in find.text('DD-MM-YYYY').evaluate()) {
            final paragraph = hint.findRenderObject()! as RenderParagraph;
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: 'The ordinary date hint stays complete on one line',
            );
          }
          final dateBottom = tester
              .getRect(find.byKey(const ValueKey('audit-through')))
              .bottom;
          final apply = tester.getRect(
            find.byKey(const ValueKey('audit-apply-dates')),
          );
          final clear = tester.getRect(
            find.byKey(const ValueKey('audit-clear-dates')),
          );
          expect(clear.bottom, closeTo(apply.bottom, .01));
          if (width == 1224) {
            expect(
              apply.bottom,
              closeTo(dateBottom, .01),
              reason: 'Actions share the date frames’ bottom on their row',
            );
          } else if (apply.top > dateBottom) {
            expect(
              apply.top - dateBottom,
              closeTo(20, .01),
              reason: 'Wrapped action row retains the popout control gap',
            );
          } else {
            expect(apply.bottom, closeTo(dateBottom, .01));
          }
          await tester.ensureVisible(find.byKey(const ValueKey('audit-kind')));
          await tester.tap(find.byKey(const ValueKey('audit-kind')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Journal Posted').last);
          await tester.pumpAndSettle();
          expect(find.text('No accounting events recorded.'), findsOneWidget);
          expect(find.byKey(const ValueKey('audit-kind')), findsOneWidget);
          expect(find.byKey(const ValueKey('audit-page-next')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('audit-kind')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('All Events').last);
          await tester.pumpAndSettle();
        }
        if (count > 0) {
          final row = find.byKey(ValueKey('audit-event-$count'));
          await tester.ensureVisible(row);
          await tester.tap(row);
          await tester.pumpAndSettle();
          final details = find.byKey(ValueKey('audit-details-$count'));
          expect(tester.getSize(details).height, greaterThan(300));
          await tester.ensureVisible(
            find.byKey(ValueKey('audit-filter-actor-$count')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await captureUi(tester, 'Audit Expanded $count ${width.toInt()}');
          if (visible) {
            final next = find.byKey(const ValueKey('audit-page-next'));
            expect(
              tester.getRect(next).top,
              greaterThan(tester.getRect(details).bottom),
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('audit-page-size')),
            );
            await tester.tap(find.byKey(const ValueKey('audit-page-size')));
            await tester.pumpAndSettle();
            final ten = find.widgetWithText(MenuItemButton, '10').last;
            await tester.ensureVisible(ten);
            await tester.pumpAndSettle();
            await tester.tap(ten);
            await tester.pumpAndSettle();
            expect(find.text('1–6 of 6'), findsOneWidget);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(host());
            await tester.pumpAndSettle();
            expect(find.text('1–6 of 6'), findsOneWidget);
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [1224.0, 720.0]) {
    testWidgets('Settings audit flow at width $width', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        namingSettingsChannel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('audit-access-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
      for (var day = 1; day <= 26; day++) {
        await workspace.database.closeThrough(
          businessId: workspace.identity.businessId,
          date: DateTime.utc(2026, 8, day),
          actorId: workspace.identity.ownerId,
          changedAt: DateTime.utc(2026, 9, day),
          reason: 'Reviewed period $day',
        );
      }
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Arial')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('/System/Library/Fonts/Supplemental/Arial.ttf')
                      .readAsBytesSync(),
                ),
              ),
            ))
            .load();
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('accounting-settings')),
      );
      await tester.tap(find.byKey(const ValueKey('accounting-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Audit Log'));
      await tester.tap(find.text('Audit Log'));
      await tester.pumpAndSettle();
      expect(find.text('1–5 of 26'), findsOneWidget);
      await captureUi(tester, 'Audit Log ${width.toInt()}');
      await tester.ensureVisible(find.byKey(const ValueKey('audit-page-next')));
      await tester.tap(find.byKey(const ValueKey('audit-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('6–10 of 26'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('audit-event-21')));
      await tester.tap(find.byKey(const ValueKey('audit-event-21')));
      await tester.pumpAndSettle();
      expect(find.text('Reviewed period 21'), findsOneWidget);
      expect(find.text('21-09-2026 00:00:00 UTC'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-filter-actor-21')),
      );
      await tester.tap(find.byKey(const ValueKey('audit-filter-actor-21')));
      await tester.pumpAndSettle();
      expect(find.text('Actor: Workspace Owner'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-all-actors')),
      );
      await tester.tap(find.byKey(const ValueKey('audit-all-actors')));
      await tester.pumpAndSettle();
      expect(find.text('Actor: Workspace Owner'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('audit-page-next')));
      await tester.tap(find.byKey(const ValueKey('audit-page-next')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-page-previous')),
      );
      await tester.tap(find.byKey(const ValueKey('audit-page-previous')));
      await tester.pumpAndSettle();
      expect(find.text('1–5 of 26'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('audit-from')),
        '26-09-2026',
      );
      await tester.enterText(
        find.byKey(const ValueKey('audit-through')),
        '26-09-2026',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-apply-dates')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-apply-dates')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audit-apply-dates')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('audit-event-26')), findsOneWidget);
      expect(find.byKey(const ValueKey('audit-event-25')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('audit-through')),
        '25-09-2026',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-apply-dates')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-apply-dates')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audit-apply-dates')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter valid DD-MM-YYYY'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-clear-dates')),
      );
      await tester.tap(find.byKey(const ValueKey('audit-clear-dates')));
      await tester.pumpAndSettle();
      expect(find.text('All Events'), findsOneWidget);
      expect(
        tester
            .widget<AccountingSelector<String>>(
              find.ancestor(
                of: find.byKey(const ValueKey('audit-kind')),
                matching: find.byType(AccountingSelector<String>),
              ),
            )
            .value,
        '',
      );
      await tester.tap(find.byKey(const ValueKey('audit-kind')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Journal Posted'));
      await tester.tap(find.text('Journal Posted'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingSelector<String>>(
              find.ancestor(
                of: find.byKey(const ValueKey('audit-kind')),
                matching: find.byType(AccountingSelector<String>),
              ),
            )
            .value,
        'journal_posted',
      );
      await tester.ensureVisible(accountingCloseIcon().last);
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      expect(find.text('Expense Setup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
