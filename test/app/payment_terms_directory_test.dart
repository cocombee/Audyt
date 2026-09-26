import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/payment_terms_directory_dialog.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import 'restored_page_routes_test.dart' show tables;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'load' || call.method == 'loadFolder') return null;
          throw StateError('Unexpected Settings mutation: ${call.method}');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null);
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets('actual Bill Add Term retains parent draft at $width', (
      t,
    ) async {
      await prepare(t, width);
      final w = await AccountingWorkspace.open(':memory:');
      await setupBill(w);
      addTearDown(w.dispose);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(body: BillsPage(workspace: w)),
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder key(String name) => find.byKey(ValueKey(name)).last;
      await tap(t, key('new-bill'));
      expect(find.byType(FrontendFormDialog), findsOneWidget);
      await tap(t, key('design-field-Reference'));
      await t.enterText(
        key('design-field-Reference'),
        'Disposable retained bill',
      );
      // Existing Bill opening reserves its document number. The Term preview
      // must add no changes beyond that original opening command.
      final before = tables(w);
      await tap(t, key('design-field-Payment Terms'));
      final actions = find.text('Add Term');
      expect(actions, findsOneWidget);
      expect(
        t.getRect(actions).top,
        lessThan(t.getRect(find.text('Net 15').last).top),
      );
      await capture(t, 'Bill Add Term Menu ${width.toInt()}');
      await tap(t, actions);
      expect(find.text('New Term'), findsOneWidget);
      await capture(t, 'Bill Inline New Term ${width.toInt()}');
      await tap(t, key('design-field-Name'));
      await t.enterText(key('design-field-Name'), 'Disposable term');
      await tap(t, accountingCloseIcon().last);
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await tap(t, find.text('Discard').last);
      expect(find.text('New Term'), findsNothing);
      expect(
        t.widget<TextFormField>(key('design-field-Reference')).controller!.text,
        'Disposable retained bill',
      );
      expect(
        t
            .widget<AccountingSelector<String>>(
              find
                  .ancestor(
                    of: key('design-field-Payment Terms'),
                    matching: find.byType(AccountingSelector<String>),
                  )
                  .last,
            )
            .value,
        'Use Vendor Default',
      );
      await capture(t, 'Bill Add Term Return ${width.toInt()}');
      await tap(t, accountingCloseIcon().last);
      await tap(t, find.text('Discard').last);
      expect(tables(w), before);
      expect(t.takeException(), isNull);
    });
    for (final demo in [false, true]) {
      testWidgets(
        'actual Settings Terms no-write journey demo=$demo at $width',
        (t) async {
          await prepare(t, width);
          final w = await AccountingWorkspace.open(':memory:');
          addTearDown(w.dispose);
          final before = tables(w);
          Widget app = AudytApp(workspace: w, showInitialSetup: false);
          if (demo) app = DemoCompany(child: app);
          await t.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: app,
            ),
          );
          await t.pumpAndSettle();
          Finder key(String name) => find.byKey(ValueKey(name)).last;
          Future<void> fill(String label, String text) async {
            await tap(t, key('design-field-$label'));
            await t.enterText(key('design-field-$label'), text);
            await t.pumpAndSettle();
          }

          Future<void> choose(String label, String choice) async {
            await tap(t, key('design-field-$label'));
            await tap(t, find.text(choice).last);
          }

          await tap(t, key('accounting-settings'));
          await tap(t, key('settings-editor-Terms'));
          await tap(t, key('settings-manage-terms'));
          expect(find.byType(PaymentTermsDirectoryDialog), findsOneWidget);
          final checkbox = t.getRect(key('terms-include-inactive'));
          final report = t.getRect(key('terms-run-report'));
          final create = t.getRect(key('terms-new'));
          expect(checkbox.center.dy, closeTo(report.center.dy, 1));
          expect(create.center.dy, report.center.dy);
          expect(create.width, lessThan(200));
          expect(
            t.widget<ButtonStyleButton>(key('terms-run-report')).onPressed,
            isNull,
          );
          await capture(
            t,
            'Terms Directory ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
          );
          if (demo) {
            expect(find.text('Net 15'), findsOneWidget);
            await fillSearch(t, '90');
            expect(find.text('Net 90'), findsOneWidget);
            expect(find.text('Net 15'), findsNothing);
            await fillSearch(t, '');
          } else {
            expect(
              find.text('The maintained terms list is not connected yet.'),
              findsOneWidget,
            );
          }
          await tap(t, key('terms-new'));
          expect(find.byType(FrontendFormDialog), findsOneWidget);
          await capture(
            t,
            'New Term Fixed Days ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
          );
          await tap(t, accountingCloseIcon().last);
          expect(find.text('Discard Unsaved Changes?'), findsNothing);
          await tap(t, key('terms-new'));
          await fill('Name', 'Disposable monthly term');
          await fill('Due In Days', '15');
          await choose('Due Rule', 'Day Of Month');
          await fill('Monthly Due Day', '20');
          await fill('Rollover Within Days', '5');
          await choose('Due Rule', 'Days After Issue');
          expect(
            t
                .widget<TextFormField>(key('design-field-Due In Days'))
                .controller!
                .text,
            '15',
          );
          await choose('Due Rule', 'Day Of Month');
          expect(
            t
                .widget<TextFormField>(key('design-field-Monthly Due Day'))
                .controller!
                .text,
            '20',
          );
          expect(
            t
                .widget<TextFormField>(key('design-field-Rollover Within Days'))
                .controller!
                .text,
            '5',
          );
          await capture(
            t,
            'New Term Monthly ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
          );
          await fill('Monthly Due Day', '32');
          await tap(t, key('design-review'));
          expect(
            find.textContaining('Day Of Month must be between 1 and 31'),
            findsOneWidget,
          );
          await fill('Monthly Due Day', '20');
          await fill('Rollover Within Days', '2.5');
          await tap(t, key('design-review'));
          expect(
            find.textContaining('Rollover Within Days must be a whole number'),
            findsOneWidget,
          );
          await fill('Rollover Within Days', '5');
          await tap(t, key('design-review'));
          expect(find.byType(AccountingInformationRows), findsOneWidget);
          expect(find.text('Disposable monthly term'), findsOneWidget);
          expect(find.text('20'), findsOneWidget);
          expect(find.text('5'), findsOneWidget);
          expect(
            t.widget<ButtonStyleButton>(key('design-review')).onPressed,
            isNull,
          );
          await capture(
            t,
            'New Term Review ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
          );
          await tap(t, find.text('Back').last);
          await tap(t, key('design-field-Name'));
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await capture(
            t,
            'New Term Discard ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
          );
          await tap(t, find.text('Keep Editing').last);
          expect(
            t.widget<TextFormField>(key('design-field-Name')).controller!.text,
            'Disposable monthly term',
          );
          await tap(t, accountingCloseIcon().last);
          await tap(t, find.text('Discard').last);
          expect(find.byType(FrontendFormDialog), findsNothing);
          expect(find.byType(PaymentTermsDirectoryDialog), findsOneWidget);
          await tap(t, key('terms-new'));
          expect(
            t.widget<TextFormField>(key('design-field-Name')).controller!.text,
            '',
          );
          await tap(t, accountingCloseIcon().last);
          expect(tables(w), before);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> fillSearch(WidgetTester t, String value) async {
  await t.enterText(find.byKey(const ValueKey('terms-search')), value);
  await t.pumpAndSettle();
}
