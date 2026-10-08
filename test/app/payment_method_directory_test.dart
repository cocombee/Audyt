import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/payment_method_directory_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import '../support/accounting_text_input.dart' show enterAccountingText;
import 'restored_page_routes_test.dart' show tables;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'load' || call.method == 'loadFolder') return null;
          throw StateError('Unexpected Settings mutation: ${call.method}');
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );

  for (final width in [720.0, 1162.0]) {
    testWidgets('compact payment row actions retain routes at $width', (
      t,
    ) async {
      await prepare(t, width);
      t.view.physicalSize = Size(width, 809);
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: DemoCompany(
            child: AudytApp(workspace: w, showInitialSetup: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder key(String id) => find.byKey(ValueKey(id)).last;
      await tap(t, key('accounting-settings'));
      await tap(t, key('settings-editor-Payment Methods'));
      await tap(t, key('settings-manage-payment-methods'));
      final row = key('payment-method-row-demo-cash');
      final actions = find.descendant(
        of: row,
        matching: find.byType(IconButton),
      );
      expect(actions, findsNWidgets(4));
      final frames = actions
          .evaluate()
          .map((e) => t.getRect(find.byWidget(e.widget)))
          .toList();
      for (final frame in frames) {
        expect(
          frame.size,
          const Size(
            accountingSmallControlHeight,
            accountingSmallControlHeight,
          ),
        );
        expect(frame.center.dy, frames.first.center.dy);
      }
      expect(find.byTooltip('Run Report for Cash'), findsOneWidget);
      expect(find.byTooltip('Make Inactive Cash'), findsOneWidget);
      expect(
        t.widget<ButtonStyleButton>(key('payment-method-report')).onPressed,
        isNotNull,
      );
      await capture(t, 'Payment Method Compact Actions ${width.toInt()}');
      await tap(t, key('payment-method-activity-demo-cash'));
      expect(find.text('Cash · Activity'), findsOneWidget);
      await tap(t, accountingCloseIcon().last);
      await tap(t, key('payment-method-activation-demo-cash'));
      expect(
        t
            .widget<ButtonStyleButton>(key('payment-method-deactivate-confirm'))
            .onPressed,
        isNull,
      );
      await tap(t, accountingCloseIcon().last);
      await tap(t, key('payment-method-include-inactive'));
      final inactive = key('payment-method-row-demo-inactive');
      expect(
        find.descendant(of: inactive, matching: find.byType(IconButton)),
        findsNWidgets(4),
      );
      expect(find.byTooltip('Make Active Archived Transfer'), findsOneWidget);
      await capture(
        t,
        'Payment Method Compact Inactive Actions ${width.toInt()}',
      );
      await tap(t, key('payment-method-activation-demo-inactive'));
      expect(
        t
            .widget<ButtonStyleButton>(key('payment-method-activate-confirm'))
            .onPressed,
        isNull,
      );
      await tap(t, accountingCloseIcon().last);
      expect(tables(w), before);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'Activity Columns reflow retains selection and order at $width',
      (t) async {
        await prepare(t, width);
        t.view.physicalSize = Size(width, 809);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final before = tables(w);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: w, showInitialSetup: false),
            ),
          ),
        );
        await t.pumpAndSettle();
        Finder key(String id) => find.byKey(ValueKey(id)).last;
        await tap(t, key('accounting-settings'));
        await tap(t, key('settings-editor-Payment Methods'));
        await tap(t, key('settings-manage-payment-methods'));
        await tap(t, key('payment-method-activity-demo-cash'));
        await tap(t, key('payment-method-report-customise'));
        await t.ensureVisible(key('payment-method-activity-column-row-date'));
        await t.pumpAndSettle();
        final date = key('payment-method-activity-Date');
        final type = key('payment-method-activity-Transaction Type');
        expect(t.getCenter(date).dy, closeTo(t.getCenter(type).dy, .1));
        expect(t.getRect(date).right, lessThan(t.getRect(type).left));
        expect(
          t.getCenter(key('payment-method-activity-Name')).dy,
          greaterThan(t.getCenter(date).dy),
          reason: 'Only Activity Columns opts into at most three slots per row',
        );
        final debit = key('payment-method-activity-Debit');
        final credit = key('payment-method-activity-Credit');
        expect(t.getCenter(debit).dy, closeTo(t.getCenter(credit).dy, .1));
        await capture(t, 'Activity Columns Responsive ${width.toInt()}');
        await tap(t, debit);
        expect(t.widget<Checkbox>(debit).value, isTrue);
        final debitRow = key('payment-method-activity-column-row-debit');
        await t.ensureVisible(key('payment-method-activity-column-row-date'));
        await t.pumpAndSettle();
        final debitLabel = find.descendant(
          of: debitRow,
          matching: find.text('Debit'),
        );
        final dateRow = key('payment-method-activity-column-row-date');
        await t.drag(
          debitLabel,
          t.getCenter(dateRow) - t.getCenter(debitLabel),
        );
        await t.pumpAndSettle();
        await capture(t, 'Activity Columns Reordered ${width.toInt()}');
        await tap(t, key('payment-method-activity-options-back'));
        final table = key('payment-method-report-table');
        final header = t.widget<Table>(table).children.first.children.first;
        expect(
          find.descendant(
            of: find.byWidget(header),
            matching: find.text('Debit (RM)'),
          ),
          findsOneWidget,
        );
        await tap(t, key('payment-method-report-customise'));
        expect(t.widget<Checkbox>(debit).value, isTrue);
        await tap(t, key('payment-method-activity-options-back'));
        await tap(t, accountingCloseIcon().last);
        await tap(t, find.text('Discard').last);
        expect(find.byType(PaymentMethodReportPreview), findsNothing);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final width in [720.0, 1224.0]) {
    for (final activity in [false, true]) {
      testWidgets('report draft dismissal activity=$activity at $width', (
        t,
      ) async {
        await prepare(t, width);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final before = tables(w);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: w, showInitialSetup: false),
            ),
          ),
        );
        await t.pumpAndSettle();
        Finder key(String name) => find.byKey(ValueKey(name)).last;
        await tap(t, key('accounting-settings'));
        await tap(t, key('settings-editor-Payment Methods'));
        await tap(t, key('settings-manage-payment-methods'));
        Future<void> openReport() async {
          if (activity) {
            await tap(t, key('payment-method-activity-demo-debit'));
          } else {
            await tap(t, key('payment-method-report'));
          }
        }

        await openReport();
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        await openReport();
        await tap(t, key('payment-method-report-customise'));
        await tap(t, key('payment-method-report-heading-Report Title'));
        final title = 'Disposable ${activity ? 'Activity' : 'Master'} Draft';
        await t.enterText(
          key('payment-method-report-heading-Report Title'),
          title,
        );
        await tap(
          t,
          activity
              ? key('payment-method-activity-options-back')
              : key('payment-method-report-columns-back'),
        );
        expect(find.text(title), findsOneWidget);
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(
          t,
          'Report Title Discard ${activity ? 'Activity' : 'Master'} ${width.toInt()}',
        );
        await tap(t, find.text('Keep Editing').last);
        expect(find.text(title), findsOneWidget);
        await tap(t, key('payment-method-report-notes'));
        await enterAccountingText(
          t,
          key('payment-method-report-note-editor'),
          'Disposable report note',
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(
          t,
          'Report Focused Note Discard ${activity ? 'Activity' : 'Master'} ${width.toInt()}',
        );
        await tap(t, find.text('Keep Editing').last);
        expect(
          t
              .widget<AccountingDescriptionField>(
                key('payment-method-report-note-editor'),
              )
              .controller!
              .text,
          'Disposable report note',
        );
        await tap(t, key('payment-method-report-export'));
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(find.text(title), findsOneWidget);
        await t.tapAt(const Offset(4, 4));
        await t.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(t, find.text('Keep Editing').last);
        expect(
          t
              .widget<AccountingDescriptionField>(
                key('payment-method-report-note-editor'),
              )
              .controller!
              .text,
          'Disposable report note',
        );
        await tap(t, accountingCloseIcon().last);
        await tap(t, find.text('Discard').last);
        expect(find.byType(PaymentMethodReportPreview), findsNothing);
        await openReport();
        expect(find.text(title), findsNothing);
        expect(
          find.byKey(const ValueKey('payment-method-report-note-editor')),
          findsNothing,
        );
        if (activity) {
          final originalFrom = t
              .widget<TextField>(key('payment-method-report-From'))
              .controller!
              .text;
          await tap(t, key('payment-method-report-From'));
          await t.enterText(key('payment-method-report-From'), '01-01-2025');
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await capture(t, 'Report Date Discard Activity ${width.toInt()}');
          await tap(t, find.text('Keep Editing').last);
          expect(
            t
                .widget<TextField>(key('payment-method-report-From'))
                .controller!
                .text,
            '01-01-2025',
          );
          await t.enterText(key('payment-method-report-From'), originalFrom);
          expect(
            t
                .widget<TextField>(key('payment-method-report-From'))
                .controller!
                .text,
            originalFrom,
          );
        } else {
          await tap(t, key('payment-method-report-customise'));
          await tap(t, key('payment-method-report-filter-Created Date'));
          await tap(t, key('payment-method-report-columns-back'));
          await tap(t, accountingCloseIcon().last);
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await capture(t, 'Report Filter Discard Master ${width.toInt()}');
          await tap(t, find.text('Keep Editing').last);
          await tap(t, key('payment-method-report-customise'));
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-Created Date'),
                )
                .value,
            isTrue,
          );
          await tap(t, key('payment-method-report-filter-Created Date'));
          await tap(t, key('payment-method-report-columns-back'));
        }
        await tap(t, key('payment-method-report-customise'));
        await tap(t, key('payment-method-report-filter-Report Title'));
        await tap(t, key('payment-method-report-filter-Report Title'));
        await tap(
          t,
          activity
              ? key('payment-method-activity-options-back')
              : key('payment-method-report-columns-back'),
        );
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(find.byType(PaymentMethodReportPreview), findsNothing);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final width in [720.0, 1224.0]) {
    for (final demo in [false, true]) {
      testWidgets('actual Settings payment directory demo=$demo at $width', (
        t,
      ) async {
        await prepare(t, width);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final before = tables(w);
        Widget app = AudytApp(workspace: w, showInitialSetup: false);
        if (demo) app = DemoCompany(child: app);
        await t.pumpWidget(
          RepaintBoundary(key: const ValueKey('workspace-capture'), child: app),
        );
        await t.pumpAndSettle();
        Finder key(String name) => find.byKey(ValueKey(name)).last;
        await tap(t, key('accounting-settings'));
        await tap(t, key('settings-editor-Payment Methods'));
        await tap(t, key('settings-manage-payment-methods'));
        expect(find.byType(PaymentMethodDirectoryDialog), findsOneWidget);
        final includeBox = t.getRect(key('payment-method-include-inactive'));
        final runButton = t.getRect(key('payment-method-report'));
        final newButton = t.getRect(key('payment-method-new'));
        expect(includeBox.center.dy, closeTo(runButton.center.dy, 1));
        expect(newButton.center.dy, runButton.center.dy);
        expect(includeBox.right, lessThan(runButton.left));
        expect(runButton.width, lessThan(200));
        expect(newButton.width, lessThan(250));
        expect(
          t.widget<ButtonStyleButton>(key('payment-method-report')).onPressed,
          isNotNull,
        );
        await capture(
          t,
          'Payment Method Directory ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );

        await tap(t, key('payment-method-report'));
        expect(find.byType(PaymentMethodReportPreview), findsOneWidget);
        expect(find.text('Payment Method List'), findsNWidgets(2));
        expect(find.text('Payment Method'), findsOneWidget);
        expect(
          t
              .widget<ButtonStyleButton>(key('payment-method-report-run'))
              .onPressed,
          isNull,
        );
        expect(find.text('Amount (RM)'), findsNothing);
        await capture(
          t,
          'Payment Method List Report ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(t, key('payment-method-report-export'));
        for (final format in [
          'Excel',
          'PDF',
          'CSV',
          'Add To Management Reports',
        ]) {
          expect(
            t
                .widget<MenuItemButton>(
                  key('payment-method-report-export-$format'),
                )
                .onPressed,
            format == 'PDF' || format == 'Add To Management Reports'
                ? isNotNull
                : isNull,
          );
        }
        await capture(
          t,
          'Payment Method Report Export ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.byType(PaymentMethodReportPreview), findsOneWidget);
        expect(
          t
              .widget<ButtonStyleButton>(key('payment-method-report-print'))
              .onPressed,
          isNotNull,
        );
        expect(
          t
              .widget<ButtonStyleButton>(
                key('payment-method-report-save-customisation'),
              )
              .onPressed,
          isNotNull,
        );
        await tap(t, key('payment-method-report-customise'));
        expect(
          find.byKey(
            const ValueKey('payment-method-report-filter-Report Period'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('payment-method-report-notes')),
          findsOneWidget,
        );
        for (final column in [
          'Create Date',
          'Created By',
          'Last Modified',
          'Last Modified By',
        ]) {
          await tap(t, key('payment-method-report-column-$column'));
        }
        await t.ensureVisible(find.text('Columns').last);
        await t.pumpAndSettle();
        await capture(
          t,
          'Payment Method Report Columns ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        expect(paymentMethodReportMetadataDateChoices.length, 26);
        final filterRowWidth = t
            .getSize(find.byType(AccountingOrdinaryFields).first)
            .width;
        expect(
          t.getSize(key('payment-method-report-filter-value-Deleted')).width,
          greaterThanOrEqualTo((filterRowWidth - 20) / 2),
        );
        expect(
          t.getSize(key('payment-method-report-columns-back')).width,
          lessThan(filterRowWidth / 2),
        );
        for (final filter in [
          'Payment Method',
          'Created Date',
          'Last Modified Date',
          'Deleted',
        ]) {
          expect(
            t
                .widget<Checkbox>(key('payment-method-report-filter-$filter'))
                .value,
            isFalse,
          );
        }
        final headerCheckboxTops = [
          for (final label in ['Show Logo', 'Company Name', 'Report Title'])
            t.getTopLeft(key('payment-method-report-filter-$label')).dy,
        ];
        expect(headerCheckboxTops.toSet().length, 1);
        expect(
          t.getTopLeft(key('payment-method-report-filter-Time Prepared')).dy,
          t.getTopLeft(key('payment-method-report-filter-Date Prepared')).dy,
        );
        expect(
          t.getTopLeft(key('payment-method-report-column-Created By')).dy,
          t.getTopLeft(key('payment-method-report-column-Create Date')).dy,
        );
        if (demo) {
          await tap(t, key('payment-method-report-filter-Payment Method'));
          await tap(t, key('payment-method-report-filter-method-demo-cash'));
          await tap(t, key('payment-method-report-filter-method-demo-card'));
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-method-demo-cash'),
                )
                .value,
            isTrue,
          );
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-method-demo-card'),
                )
                .value,
            isTrue,
          );
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-method-demo-debit'),
                )
                .value,
            isFalse,
          );
          await t.ensureVisible(
            key('payment-method-report-filter-Payment Method'),
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Report Multiple Choices ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-filter-Select All'));
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-method-demo-inactive'),
                )
                .value,
            isTrue,
          );
          await tap(t, key('payment-method-report-filter-Payment Method'));
          expect(
            find.byKey(
              const ValueKey('payment-method-report-filter-method-demo-cash'),
            ),
            findsNothing,
          );
          await tap(t, key('payment-method-report-filter-Payment Method'));
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-method-demo-cash'),
                )
                .value,
            isTrue,
          );
        } else {
          await tap(t, key('payment-method-report-filter-Payment Method'));
          expect(
            find.text(
              'The maintained payment-method choices are not connected yet.',
            ),
            findsOneWidget,
          );
          await capture(
            t,
            'Payment Method Report Empty Method Choices ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-filter-Payment Method'));
        }
        await tap(
          t,
          key('payment-method-report-filter-value-Last Modified Date'),
        );
        await capture(
          t,
          'Payment Method Report Metadata Date Menu ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(t, find.text('Custom').last);
        expect(
          t
              .widget<Checkbox>(
                key('payment-method-report-filter-Last Modified Date'),
              )
              .value,
          isTrue,
        );
        await tap(
          t,
          key('payment-method-report-filter-Last Modified Date-From'),
        );
        await t.enterText(
          key('payment-method-report-filter-Last Modified Date-From'),
          '01012024',
        );
        expect(
          t
              .widget<TextField>(
                key('payment-method-report-filter-Last Modified Date-From'),
              )
              .controller!
              .text,
          '01-01-2024',
        );
        await capture(
          t,
          'Payment Method Report Custom Metadata Dates ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(
          t,
          key('payment-method-report-filter-value-Last Modified Date'),
        );
        await tap(t, find.text('Today').last);
        expect(
          find.byKey(
            const ValueKey(
              'payment-method-report-filter-Last Modified Date-From',
            ),
          ),
          findsNothing,
        );
        await tap(
          t,
          key('payment-method-report-filter-value-Last Modified Date'),
        );
        await tap(t, find.text('Custom').last);
        expect(
          t
              .widget<TextField>(
                key('payment-method-report-filter-Last Modified Date-From'),
              )
              .controller!
              .text,
          '01-01-2024',
        );
        await tap(t, key('payment-method-report-filter-Company Name'));
        await tap(t, key('payment-method-report-heading-Company Name'));
        await t.enterText(
          key('payment-method-report-heading-Company Name'),
          'Preview Company',
        );
        await tap(t, key('payment-method-report-Header Alignment'));
        await tap(t, find.text('Right').last);
        await tap(t, key('payment-method-report-filter-Date Prepared'));
        await tap(t, key('payment-method-report-filter-Time Prepared'));
        await capture(
          t,
          'Payment Method Report Header Footer ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(t, key('payment-method-report-Sort By'));
        await tap(t, find.text('Last Modified').last);
        await tap(t, key('payment-method-report-Sort Order'));
        await tap(t, find.text('Descending Order').last);
        await capture(
          t,
          'Payment Method Report Sorting ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(t, find.text('Back To Report'));
        await tap(t, key('payment-method-report-customise'));
        expect(
          t
              .widget<TextField>(
                key('payment-method-report-heading-Company Name'),
              )
              .controller!
              .text,
          'Preview Company',
        );
        expect(
          t
              .widget<AccountingSelector<String>>(
                find.ancestor(
                  of: key('payment-method-report-Header Alignment'),
                  matching: find.byType(AccountingSelector<String>),
                ),
              )
              .value,
          'Right',
        );
        expect(
          t
              .widget<AccountingSelector<String>>(
                find.ancestor(
                  of: key('payment-method-report-Sort By'),
                  matching: find.byType(AccountingSelector<String>),
                ),
              )
              .value,
          'Last Modified',
        );
        expect(
          t
              .widget<AccountingSelector<String>>(
                find.ancestor(
                  of: key('payment-method-report-Sort Order'),
                  matching: find.byType(AccountingSelector<String>),
                ),
              )
              .value,
          'Descending Order',
        );
        await tap(t, key('payment-method-report-filter-value-Created Date'));
        await tap(
          t,
          find
              .descendant(
                of: find.byType(MenuItemButton),
                matching: find.text('Custom'),
              )
              .last,
        );
        expect(
          t
              .widget<TextField>(
                key('payment-method-report-filter-Created Date-From'),
              )
              .controller!
              .text,
          isEmpty,
        );
        await tap(t, key('payment-method-report-filter-Created Date-From'));
        await t.enterText(
          key('payment-method-report-filter-Created Date-From'),
          '02022024',
        );
        await tap(t, key('payment-method-report-filter-Created Date-Through'));
        await t.enterText(
          key('payment-method-report-filter-Created Date-Through'),
          '03022024',
        );
        expect(
          t
              .widget<TextField>(
                key('payment-method-report-filter-Last Modified Date-From'),
              )
              .controller!
              .text,
          '01-01-2024',
        );
        await t.ensureVisible(
          key('payment-method-report-filter-Created Date-From'),
        );
        await t.pumpAndSettle();
        await capture(
          t,
          'Payment Method Report Both Metadata Date Pairs ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        expect(
          t
              .widget<Checkbox>(
                key('payment-method-report-filter-Last Modified Date'),
              )
              .value,
          isTrue,
        );
        expect(
          t
              .widget<TextField>(
                key('payment-method-report-filter-Last Modified Date-From'),
              )
              .controller!
              .text,
          '01-01-2024',
        );
        await tap(t, find.text('Back To Report'));
        final reportTable = t.widget<Table>(key('payment-method-report-table'));
        expect(reportTable.children.first.children.length, 5);
        expect(reportTable.children.length, demo ? 5 : 1);
        if (demo) expect(find.text('Unavailable'), findsNWidgets(16));
        await capture(
          t,
          'Payment Method List Metadata ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(t, find.text('Discard').last);
        expect(find.byType(PaymentMethodReportPreview), findsNothing);
        expect(find.byType(PaymentMethodDirectoryDialog), findsOneWidget);
        expect(tables(w), before);

        if (demo) {
          await tap(t, key('payment-method-activity-demo-debit'));
          expect(find.text('Debit Card · Activity'), findsOneWidget);
          expect(find.text('Payment Method'), findsNothing);
          expect(find.text('Created Date'), findsNothing);
          expect(find.text('Last Modified Date'), findsNothing);
          final activityTable = t.widget<Table>(
            key('payment-method-report-table'),
          );
          expect(activityTable.children.first.children.length, 9);
          expect(activityTable.children.length, 1);
          expect(find.text('Amount (RM)'), findsOneWidget);
          expect(find.text('Balance (RM)'), findsOneWidget);
          await t.enterText(key('payment-method-report-From'), '01012024');
          expect(
            t
                .widget<TextField>(key('payment-method-report-From'))
                .controller!
                .text,
            '01-01-2024',
          );
          expect(
            t
                .widget<ButtonStyleButton>(key('payment-method-report-run'))
                .onPressed,
            isNull,
          );
          await capture(t, 'Payment Method Activity ${width.toInt()}');
          expect(paymentMethodActivityReportPeriodChoices.length, 31);
          expect(
            paymentMethodReportMetadataDateChoices,
            isNot(contains('Next Year')),
          );
          expect(paymentMethodActivityReportGroupingChoices.length, 13);
          Finder menuChoice(String label) => find
              .descendant(
                of: find.byType(MenuItemButton),
                matching: find.text(label),
              )
              .last;
          await tap(t, key('payment-method-activity-Report Period'));
          await tap(t, menuChoice('All Dates'));
          expect(
            find.byKey(const ValueKey('payment-method-report-From')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('payment-method-report-Through')),
            findsNothing,
          );
          await capture(
            t,
            'Payment Method Activity All Dates ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-Report Period'));
          await tap(t, menuChoice('Next Year'));
          expect(
            t.widget<TextField>(key('payment-method-report-From')).enabled,
            isFalse,
          );
          expect(
            t
                .widget<TextField>(key('payment-method-report-From'))
                .controller!
                .text,
            isEmpty,
          );
          expect(
            t.widget<TextField>(key('payment-method-report-Through')).enabled,
            isFalse,
          );
          await capture(
            t,
            'Payment Method Activity Future Period ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-Report Period'));
          await tap(t, menuChoice('Since 90 Days Ago'));
          expect(
            find.byKey(const ValueKey('payment-method-report-Through')),
            findsNothing,
          );
          await capture(
            t,
            'Payment Method Activity Since Period ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-Report Period'));
          await tap(t, menuChoice('Custom'));
          expect(
            t
                .widget<TextField>(key('payment-method-report-From'))
                .controller!
                .text,
            '01-01-2024',
          );
          await tap(t, key('payment-method-report-customise'));
          expect(find.text('Customise Activity Report'), findsOneWidget);
          expect(find.text('Created Date'), findsOneWidget);
          expect(paymentMethodActivityFilterNames.length, 19);
          for (final name in paymentMethodActivityFilterNames) {
            expect(
              key('payment-method-activity-filter-enable-$name'),
              findsOneWidget,
            );
          }
          expect(find.text('Deleted'), findsNothing);
          expect(
            t.getTopLeft(key('payment-method-activity-Without Cents')).dy,
            greaterThan(
              t.getTopLeft(key('payment-method-activity-Divide By 1000')).dy,
            ),
          );
          await tap(t, key('payment-method-activity-Divide By 1000'));
          await tap(t, key('payment-method-activity-Without Cents'));
          await tap(t, key('payment-method-activity-Show In Red'));
          await tap(t, key('payment-method-activity-Negative Numbers'));
          await tap(t, menuChoice('(100)'));
          await tap(t, key('payment-method-activity-Group By'));
          await tap(t, menuChoice('Supplier'));
          await capture(
            t,
            'Payment Method Activity General Options ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-options-back'));
          await tap(t, key('payment-method-report-customise'));
          expect(
            t
                .widget<Checkbox>(key('payment-method-activity-Divide By 1000'))
                .value,
            isTrue,
          );
          expect(
            t
                .widget<Checkbox>(key('payment-method-activity-Without Cents'))
                .value,
            isTrue,
          );
          expect(
            t
                .widget<Checkbox>(key('payment-method-activity-Show In Red'))
                .value,
            isTrue,
          );
          expect(find.text('(100)'), findsOneWidget);
          expect(
            t
                .widget<AccountingSelector<String>>(
                  find.ancestor(
                    of: key('payment-method-activity-Group By'),
                    matching: find.byType(AccountingSelector<String>),
                  ),
                )
                .value,
            'Supplier',
          );
          expect(
            t
                .widget<TextField>(key('payment-method-report-From'))
                .controller!
                .text,
            '01-01-2024',
          );
          for (final column in ['Debit', 'Credit', 'Qty', 'Created By']) {
            await tap(t, key('payment-method-activity-$column'));
          }
          await tap(t, key('payment-method-activity-Split'));
          await capture(
            t,
            'Payment Method Activity Optional Columns ${width.toInt()}',
          );
          await t.ensureVisible(key('payment-method-activity-column-row-date'));
          await t.pumpAndSettle();
          final amountDrag = find
              .descendant(
                of: key('payment-method-activity-column-row-amount'),
                matching: find.text('Amount'),
              )
              .first;
          final dateTarget = key('payment-method-activity-column-row-date');
          await t.drag(
            amountDrag,
            t.getCenter(dateTarget) - t.getCenter(amountDrag),
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Reordered Columns ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-options-back'));
          final reorderedTable = t.widget<Table>(
            key('payment-method-report-table'),
          );
          expect(reorderedTable.children.first.children.length, 12);
          final firstHeader = find.descendant(
            of: key('payment-method-report-table'),
            matching: find.text('Amount (RM)'),
          );
          expect(t.widget<Text>(firstHeader).textAlign, TextAlign.right);
          expect(
            find.descendant(
              of: key('payment-method-report-table'),
              matching: find.text('Debit (RM)'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: key('payment-method-report-table'),
              matching: find.text('Credit (RM)'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: key('payment-method-report-table'),
              matching: find.text('Qty'),
            ),
            findsOneWidget,
          );
          expect(
            t.getTopLeft(firstHeader).dx,
            lessThan(
              t
                  .getTopLeft(
                    find.descendant(
                      of: key('payment-method-report-table'),
                      matching: find.text('Transaction Date'),
                    ),
                  )
                  .dx,
            ),
          );
          await capture(
            t,
            'Payment Method Activity Reordered Headers ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-customise'));
          for (final column in [
            'Date',
            'Transaction Type',
            'No.',
            'Name',
            'Memo/Description',
            'Account',
            'Amount',
            'Balance',
            'Debit',
            'Credit',
            'Qty',
            'Created By',
          ]) {
            await tap(t, key('payment-method-activity-$column'));
          }
          await tap(t, key('payment-method-activity-options-back'));
          expect(
            find.byKey(const ValueKey('payment-method-report-table')),
            findsNothing,
          );
          expect(
            find.text('Select at least one report column.'),
            findsOneWidget,
          );
          await capture(
            t,
            'Payment Method Activity No Columns ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-customise'));
          for (final column in [
            'Date',
            'Transaction Type',
            'No.',
            'Name',
            'Memo/Description',
            'Account',
            'Split',
            'Amount',
            'Balance',
          ]) {
            await tap(t, key('payment-method-activity-$column'));
          }
          await tap(t, key('payment-method-activity-options-back'));
          await tap(t, key('payment-method-report-customise'));
          AccountingSelector<String> filterSelector(String name) =>
              t.widget<AccountingSelector<String>>(
                find.ancestor(
                  of: key('payment-method-activity-filter-value-$name'),
                  matching: find.byType(AccountingSelector<String>),
                ),
              );
          expect(filterSelector('Due Date').options.length, 31);
          expect(filterSelector('Created Date').options.length, 26);
          expect(filterSelector('Last Modified Date').options.length, 26);
          expect(filterSelector('Payment Method').displayLabel, 'Debit Card');
          await t.ensureVisible(
            key('payment-method-activity-filter-field-Payment Method'),
          );
          await t.pumpAndSettle();
          await t.tap(
            key('payment-method-activity-filter-value-Payment Method'),
          );
          await t.pumpAndSettle();
          await tap(
            t,
            key(
              'payment-method-activity-filter-option-Payment Method-item:demo-card',
            ),
          );
          expect(
            filterSelector('Payment Method').options
                .where((o) => o.checked == true)
                .length,
            2,
          );
          expect(
            key(
              'payment-method-activity-filter-option-Payment Method-item:demo-cash',
            ),
            findsOneWidget,
          );
          await capture(
            t,
            'Payment Method Activity Multiple Method Menu ${width.toInt()}',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Customise Activity Report'), findsOneWidget);
          expect(filterSelector('Payment Method').displayLabel, 'Multiple ...');
          await tap(
            t,
            key('payment-method-activity-filter-enable-Payment Method'),
          );
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-activity-filter-enable-Payment Method'),
                )
                .value,
            isFalse,
          );
          expect(
            filterSelector('Payment Method').options
                .where((o) => o.checked == true)
                .length,
            2,
          );
          await tap(t, key('payment-method-activity-filter-value-Cleared'));
          await tap(t, menuChoice('Reconciled'));
          expect(filterSelector('Cleared').value, 'mode:Reconciled');
          expect(
            filterSelector('Cleared').options.every((o) => o.checked == null),
            isTrue,
          );
          await tap(t, key('payment-method-activity-filter-value-A/R Paid'));
          await tap(t, menuChoice('Paid'));
          await tap(t, key('payment-method-activity-filter-value-A/P Paid'));
          await tap(t, menuChoice('Unpaid'));
          await t.ensureVisible(
            key('payment-method-activity-filter-field-Transaction Type'),
          );
          await t.pumpAndSettle();
          await t.tap(
            key('payment-method-activity-filter-value-Transaction Type'),
          );
          await t.pumpAndSettle();
          await t.enterText(
            key('payment-method-activity-filter-search-Transaction Type'),
            'Invoice',
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Type Search ${width.toInt()}',
          );
          expect(
            filterSelector('Transaction Type').options
                .any((o) => o.value == 'item:Invoice'),
            isTrue,
          );
          await tap(
            t,
            key(
              'payment-method-activity-filter-option-Transaction Type-item:Invoice',
            ),
          );
          expect(
            filterSelector('Transaction Type').options
                .any((o) => o.value == 'item:Invoice' && o.checked == true),
            isTrue,
          );
          await t.enterText(
            key('payment-method-activity-filter-search-Transaction Type'),
            'Bill',
          );
          await t.pumpAndSettle();
          await tap(
            t,
            key(
              'payment-method-activity-filter-option-Transaction Type-item:Bill',
            ),
          );
          expect(
            filterSelector('Transaction Type').options
                .where((o) => o.checked == true)
                .length,
            2,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          await tap(
            t,
            key('payment-method-activity-filter-value-Transaction Type'),
          );
          await tap(
            t,
            key(
              'payment-method-activity-filter-option-Transaction Type-mode:Posting',
            ),
          );
          expect(filterSelector('Transaction Type').value, 'mode:Posting');
          expect(
            filterSelector('Transaction Type').options
                .where((o) => o.checked == true),
            isEmpty,
          );
          final amount = key('payment-method-activity-filter-text-Amount');
          await t.ensureVisible(amount);
          await t.pumpAndSettle();
          final amountWidth = t.getSize(amount).width;
          await t.enterText(amount, '=123456789012345.67');
          await t.pumpAndSettle();
          expect(t.getSize(amount).width, amountWidth);
          expect(
            t.widget<TextField>(amount).controller!.text,
            '=123456789012345.67',
          );
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-activity-filter-enable-Amount'),
                )
                .value,
            isTrue,
          );
          await capture(
            t,
            'Payment Method Activity Status Text Filters ${width.toInt()}',
          );
          for (final name in ['Due Date', 'Created Date']) {
            await tap(t, key('payment-method-activity-filter-value-$name'));
            await tap(t, menuChoice('Custom'));
          }
          await t.enterText(
            key('payment-method-activity-filter-Due Date-From'),
            '01112026',
          );
          await t.enterText(
            key('payment-method-activity-filter-Created Date-From'),
            '01012025',
          );
          await capture(
            t,
            'Payment Method Activity Independent Filter Dates ${width.toInt()}',
          );
          await t.ensureVisible(
            key('payment-method-activity-filter-dates-Created Date'),
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Created Filter Dates ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-options-back'));
          await tap(t, key('payment-method-report-customise'));
          expect(filterSelector('Payment Method').displayLabel, 'Multiple ...');
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-activity-filter-enable-Payment Method'),
                )
                .value,
            isFalse,
          );
          expect(filterSelector('A/R Paid').value, 'mode:Paid');
          expect(filterSelector('A/P Paid').value, 'mode:Unpaid');
          expect(
            t
                .widget<TextField>(
                  key('payment-method-activity-filter-Due Date-From'),
                )
                .controller!
                .text,
            '01-11-2026',
          );
          expect(
            t
                .widget<TextField>(
                  key('payment-method-activity-filter-Created Date-From'),
                )
                .controller!
                .text,
            '01-01-2025',
          );
          await t.ensureVisible(
            key('payment-method-activity-filter-field-Payment Method'),
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Retained Filters ${width.toInt()}',
          );
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-Report Period'),
                )
                .value,
            isFalse,
          );
          await tap(t, key('payment-method-report-filter-Company Name'));
          await tap(t, key('payment-method-report-heading-Company Name'));
          await t.enterText(
            key('payment-method-report-heading-Company Name'),
            'Preview Activity Company',
          );
          await tap(t, key('payment-method-report-heading-Report Title'));
          await t.enterText(
            key('payment-method-report-heading-Report Title'),
            'Preview Activity',
          );
          await tap(t, key('payment-method-report-filter-Report Period'));
          await tap(t, key('payment-method-report-filter-Date Prepared'));
          await tap(t, key('payment-method-report-filter-Time Prepared'));
          await tap(t, key('payment-method-report-Header Alignment'));
          await tap(t, find.text('Centre').last);
          await tap(t, key('payment-method-report-Footer Alignment'));
          await tap(t, find.text('Right').last);
          await t.ensureVisible(key('payment-method-report-presentation'));
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Header Footer ${width.toInt()}',
          );
          final activitySort = t.widget<AccountingSelector<String>>(
            find.ancestor(
              of: key('payment-method-report-Sort By'),
              matching: find.byType(AccountingSelector<String>),
            ),
          );
          expect(activitySort.options.length, 27);
          expect(
            activitySort.options.map((o) => o.label),
            containsAll([
              'Tax Amount',
              'Tax Code',
              'Unit Price/Rate',
              'A/P Paid',
            ]),
          );
          expect(
            activitySort.options.map((o) => o.label),
            isNot(contains('Amount')),
          );
          await tap(t, key('payment-method-report-Sort By'));
          await capture(
            t,
            'Payment Method Activity Sort Menu ${width.toInt()}',
          );
          await tap(t, find.text('Unit Price/Rate').last);
          await tap(t, key('payment-method-report-Sort Order'));
          await tap(t, find.text('Descending Order').last);
          await tap(t, key('payment-method-activity-options-back'));
          expect(find.text('Preview Activity Company'), findsOneWidget);
          expect(find.text('Preview Activity'), findsOneWidget);
          await tap(t, key('payment-method-report-customise'));
          expect(
            t
                .widget<TextField>(
                  key('payment-method-report-heading-Report Title'),
                )
                .controller!
                .text,
            'Preview Activity',
          );
          expect(
            t
                .widget<Checkbox>(
                  key('payment-method-report-filter-Report Period'),
                )
                .value,
            isTrue,
          );
          expect(
            t
                .widget<AccountingSelector<String>>(
                  find.ancestor(
                    of: key('payment-method-report-Sort By'),
                    matching: find.byType(AccountingSelector<String>),
                  ),
                )
                .value,
            'Unit Price/Rate',
          );
          expect(
            t
                .widget<AccountingSelector<String>>(
                  find.ancestor(
                    of: key('payment-method-report-Sort Order'),
                    matching: find.byType(AccountingSelector<String>),
                  ),
                )
                .value,
            'Descending Order',
          );
          await t.ensureVisible(key('payment-method-report-presentation'));
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Retained Presentation ${width.toInt()}',
          );
          await tap(t, key('payment-method-activity-options-back'));
          await tap(t, key('payment-method-report-export'));
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.byType(PaymentMethodReportPreview), findsOneWidget);
          await capture(
            t,
            'Payment Method Activity Retained General ${width.toInt()}',
          );
          await t.drag(
            key('payment-method-report-table-scroll'),
            const Offset(-1200, 0),
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Trailing Columns ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-notes'));
          final note = key('payment-method-report-note-editor');
          expect(
            t.widget<AccountingDescriptionField>(note).role,
            AccountingDescriptionRole.memo,
          );
          expect(t.widget<AccountingDescriptionField>(note).maxLength, 4000);
          await capture(
            t,
            'Payment Method Activity Notes Empty ${width.toInt()}',
          );
          await enterAccountingText(
            t,
            note,
            'Supporting report context\nReviewed separately.',
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Notes Entered ${width.toInt()}',
          );
          final retainedNote = t
              .widget<AccountingDescriptionField>(note)
              .controller!
              .text;
          await tap(t, key('payment-method-report-close-notes'));
          expect(
            find.byKey(const ValueKey('payment-method-report-note-editor')),
            findsNothing,
          );
          await tap(t, key('payment-method-report-notes'));
          expect(
            t.widget<AccountingDescriptionField>(note).controller!.text,
            retainedNote,
          );
          expect(tables(w), before);
          await capture(
            t,
            'Payment Method Activity Notes Retained ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-close-notes'));
          await tap(t, key('payment-method-report-print'));
          expect(key('payment-method-report-print-dialog'), findsOneWidget);
          expect(
            t
                .widget<ButtonStyleButton>(
                  key('payment-method-report-print-submit'),
                )
                .onPressed,
            isNull,
          );
          expect(
            t
                .widget<ButtonStyleButton>(
                  key('payment-method-report-save-pdf'),
                )
                .onPressed,
            isNull,
          );
          await capture(
            t,
            'Payment Method Activity Print Preview ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-print-orientation'));
          await tap(t, find.text('Landscape').last);
          await tap(t, key('payment-method-report-repeat-header'));
          await capture(
            t,
            'Payment Method Activity Print Options ${width.toInt()}',
          );
          await tap(t, accountingCloseIcon().last);
          await tap(t, key('payment-method-report-email'));
          expect(
            t
                .widget<AccountingSelector<String>>(
                  find.ancestor(
                    of: key('payment-method-report-print-orientation'),
                    matching: find.byType(AccountingSelector<String>),
                  ),
                )
                .value,
            'Landscape',
          );
          expect(
            t
                .widget<Checkbox>(key('payment-method-report-repeat-header'))
                .value,
            isTrue,
          );
          await tap(t, key('payment-method-report-print-email'));
          expect(
            find.byKey(const ValueKey('payment-method-report-print-dialog')),
            findsNothing,
          );
          expect(key('payment-method-report-email-dialog'), findsOneWidget);
          expect(
            t
                .widget<TextField>(key('payment-method-report-email-To'))
                .controller!
                .text,
            isEmpty,
          );
          expect(
            t
                .widget<AccountingDescriptionField>(
                  key('payment-method-report-email-Body'),
                )
                .controller!
                .text,
            isEmpty,
          );
          expect(
            t
                .widget<TextField>(key('payment-method-report-email-Report'))
                .decoration!
                .suffixText,
            '.pdf',
          );
          expect(
            t
                .widget<ButtonStyleButton>(
                  key('payment-method-report-email-send'),
                )
                .onPressed,
            isNull,
          );
          await capture(
            t,
            'Payment Method Activity Email Empty ${width.toInt()}',
          );
          await tap(t, key('payment-method-report-email-To'));
          await t.enterText(
            key('payment-method-report-email-To'),
            'review@example.test',
          );
          await enterAccountingText(
            t,
            key('payment-method-report-email-Body'),
            'Draft report message.',
          );
          await t.pumpAndSettle();
          await capture(
            t,
            'Payment Method Activity Email Entered ${width.toInt()}',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(t, find.text('Keep Editing').last);
          expect(
            t
                .widget<TextField>(key('payment-method-report-email-To'))
                .controller!
                .text,
            'review@example.test',
          );
          await tap(t, key('payment-method-report-email-close'));
          await capture(
            t,
            'Payment Method Activity Email Discard Warning ${width.toInt()}',
          );
          await tap(t, find.text('Discard').last);
          expect(
            find.byKey(const ValueKey('payment-method-report-email-dialog')),
            findsNothing,
          );
          expect(tables(w), before);
          await tap(t, key('payment-method-report-export'));
          await tap(t, key('payment-method-report-export-PDF'));
          expect(key('payment-method-report-print-dialog'), findsOneWidget);
          expect(
            t
                .widget<AccountingSelector<String>>(
                  find.ancestor(
                    of: key('payment-method-report-print-orientation'),
                    matching: find.byType(AccountingSelector<String>),
                  ),
                )
                .value,
            'Landscape',
          );
          await capture(
            t,
            'Payment Method Activity PDF Route ${width.toInt()}',
          );
          await tap(t, accountingCloseIcon().last);
          await tap(t, accountingCloseIcon().last);
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(t, find.text('Discard').last);
          expect(find.byType(PaymentMethodReportPreview), findsNothing);
          expect(find.byType(PaymentMethodDirectoryDialog), findsOneWidget);
          expect(tables(w), before);
          expect(find.text('Archived Transfer'), findsNothing);
          final debitRow = key('payment-method-row-demo-debit');
          expect(
            find.descendant(
              of: debitRow,
              matching: find.text('Card Payment: No'),
            ),
            findsOneWidget,
          );
          await tap(t, key('payment-method-edit-demo-debit'));
          expect(
            t.widget<TextFormField>(key('design-field-Name')).controller!.text,
            'Debit Card',
          );
          final card = key('design-field-This Is A Credit Or Debit Card');
          expect(t.widget<Checkbox>(card).value, isFalse);
          await t.enterText(key('design-field-Name'), 'Renamed fictional card');
          expect(t.widget<Checkbox>(card).value, isFalse);
          await tap(t, key('design-review'));
          expect(find.text('Renamed fictional card'), findsOneWidget);
          expect(find.text('No'), findsOneWidget);
          expect(
            t.widget<ButtonStyleButton>(key('design-review')).onPressed,
            isNull,
          );
          await capture(
            t,
            'Payment Method Directory Edit Review ${width.toInt()}',
          );
          await tap(t, key('design-back'));
          await tap(t, key('design-field-Name'));
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
          await tap(t, key('design-keep-editing'));
          expect(
            t.widget<TextFormField>(key('design-field-Name')).controller!.text,
            'Renamed fictional card',
          );
          await tap(t, accountingCloseIcon().last);
          await tap(t, key('design-discard-changes'));
          expect(
            find.descendant(of: debitRow, matching: find.text('Debit Card')),
            findsOneWidget,
          );
          await tap(t, key('payment-method-view-demo-card'));
          expect(
            t
                .widget<AccountingInformationRows>(
                  find.byType(AccountingInformationRows),
                )
                .rows,
            [
              ('Name', 'Company Card'),
              ('Card Payment', 'Yes'),
              ('Status', 'Active'),
            ],
          );
          await capture(t, 'Payment Method Directory Facts ${width.toInt()}');
          await tap(t, accountingCloseIcon().last);
          await tap(t, key('payment-method-activation-demo-debit'));
          expect(
            t
                .widget<ButtonStyleButton>(
                  key('payment-method-deactivate-confirm'),
                )
                .onPressed,
            isNull,
          );
          await capture(
            t,
            'Payment Method Directory Inactive Warning ${width.toInt()}',
          );
          await tap(t, accountingCloseIcon().last);
          await tap(t, key('payment-method-include-inactive'));
          expect(find.text('Archived Transfer'), findsOneWidget);
          await capture(
            t,
            'Payment Method Directory Includes Inactive ${width.toInt()}',
          );
          await tap(t, key('payment-method-activation-demo-inactive'));
          expect(
            t
                .widget<ButtonStyleButton>(
                  key('payment-method-activate-confirm'),
                )
                .onPressed,
            isNull,
          );
          await tap(t, accountingCloseIcon().last);
        }

        await tap(t, key('payment-method-new'));
        expect(
          t
              .widget<Checkbox>(
                key('design-field-This Is A Credit Or Debit Card'),
              )
              .value,
          isFalse,
        );
        await capture(
          t,
          'Payment Method Directory New ${demo ? 'Demo' : 'Empty'} ${width.toInt()}',
        );
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        await tap(t, accountingCloseIcon().last);
        expect(find.byType(PaymentMethodDirectoryDialog), findsNothing);
        expect(key('settings-manage-payment-methods'), findsOneWidget);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final width in [720.0, 1224.0]) {
    for (final activity in [false, true]) {
      final scope = activity ? 'Activity' : 'Master';
      final reportTitle = activity
          ? 'Payment Method Activity'
          : 'Payment Method List';
      testWidgets('$scope saved report local draft scope at $width', (t) async {
        await prepare(t, width);
        final w = await AccountingWorkspace.open(':memory:');
        addTearDown(w.dispose);
        final before = tables(w);
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(workspace: w, showInitialSetup: false),
            ),
          ),
        );
        await t.pumpAndSettle();
        Finder key(String name) => find.byKey(ValueKey(name)).last;
        await tap(t, key('accounting-settings'));
        await tap(t, key('settings-editor-Payment Methods'));
        await tap(t, key('settings-manage-payment-methods'));
        await tap(
          t,
          key(
            activity
                ? 'payment-method-activity-demo-debit'
                : 'payment-method-report',
          ),
        );
        await tap(t, key('payment-method-report-save-customisation'));
        expect(key('payment-method-saved-report-dialog'), findsOneWidget);
        final name = key('payment-method-saved-report-name');
        expect(t.widget<TextField>(name).controller!.text, reportTitle);
        final group = t.widget<AccountingSelector<String>>(
          find
              .ancestor(
                of: key('payment-method-saved-report-group'),
                matching: find.byType(AccountingSelector<String>),
              )
              .first,
        );
        expect(group.options.first.label, 'Add New Group');
        expect(group.options.first.leading, isA<AccountingAddIcon>());
        expect(group.value, 'None');
        expect(
          t
              .widget<ButtonStyleButton>(
                key('payment-method-saved-report-save'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('payment-method-saved-report-group-name')),
          findsNothing,
        );
        await capture(t, '$scope Saved Report Empty ${width.toInt()}');
        await tap(t, key('payment-method-saved-report-group'));
        await capture(t, '$scope Saved Report Group Menu ${width.toInt()}');
        await tap(t, key('payment-method-saved-report-new-group'));
        expect(key('payment-method-saved-report-group-name'), findsOneWidget);
        expect(
          t
              .widget<ButtonStyleButton>(
                key('payment-method-saved-report-add-group'),
              )
              .onPressed,
          isNull,
        );
        expect(
          t.getSize(key('payment-method-saved-report-add-group')).width,
          lessThan(
            t.getSize(key('payment-method-saved-report-group-name')).width,
          ),
        );
        await capture(t, '$scope Saved Report New Group ${width.toInt()}');
        await tap(t, key('payment-method-saved-report-share'));
        await capture(t, '$scope Saved Report Share Menu ${width.toInt()}');
        final shareChoice = find
            .descendant(
              of: find.byType(MenuItemButton),
              matching: find.text('All'),
            )
            .last;
        await tap(t, shareChoice);
        await t.enterText(name, 'Local report review');
        await t.enterText(
          key('payment-method-saved-report-group-name'),
          'Local group review',
        );
        await capture(t, '$scope Saved Report Entered ${width.toInt()}');
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(t, '$scope Saved Report Discard ${width.toInt()}');
        await tap(t, find.text('Keep Editing'));
        expect(
          t.widget<TextField>(name).controller!.text,
          'Local report review',
        );
        expect(
          t
              .widget<TextField>(key('payment-method-saved-report-group-name'))
              .controller!
              .text,
          'Local group review',
        );
        await tap(t, key('payment-method-saved-report-close'));
        await tap(t, find.text('Discard'));
        expect(
          find.byKey(const ValueKey('payment-method-saved-report-dialog')),
          findsNothing,
        );
        expect(
          key(
            activity
                ? 'payment-method-activity-report'
                : 'payment-method-list-report',
          ),
          findsOneWidget,
        );
        await tap(t, key('payment-method-report-save-customisation'));
        expect(t.widget<TextField>(name).controller!.text, reportTitle);
        expect(
          find.byKey(const ValueKey('payment-method-saved-report-group-name')),
          findsNothing,
        );
        await tap(t, key('payment-method-saved-report-close'));
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets('Master report notes and delivery local draft at $width', (
      t,
    ) async {
      await prepare(t, width);
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: DemoCompany(
            child: AudytApp(workspace: w, showInitialSetup: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder key(String name) => find.byKey(ValueKey(name)).last;
      await tap(t, key('accounting-settings'));
      await tap(t, key('settings-editor-Payment Methods'));
      await tap(t, key('settings-manage-payment-methods'));
      await tap(t, key('payment-method-report'));
      expect(
        find.byKey(
          const ValueKey('payment-method-report-filter-Report Period'),
        ),
        findsNothing,
      );
      await tap(t, key('payment-method-report-notes'));
      final note = key('payment-method-report-note-editor');
      expect(t.widget<AccountingDescriptionField>(note).maxLength, 4000);
      expect(
        t.widget<AccountingDescriptionField>(note).role,
        AccountingDescriptionRole.memo,
      );
      await capture(t, 'Master Report Notes Empty ${width.toInt()}');
      await enterAccountingText(
        t,
        note,
        'Master list context\nLocal review only.',
      );
      await t.pumpAndSettle();
      await capture(t, 'Master Report Notes Entered ${width.toInt()}');
      final retained = t
          .widget<AccountingDescriptionField>(note)
          .controller!
          .text;
      await tap(t, key('payment-method-report-close-notes'));
      expect(
        find.byKey(const ValueKey('payment-method-report-note-editor')),
        findsNothing,
      );
      await tap(t, key('payment-method-report-notes'));
      expect(
        t.widget<AccountingDescriptionField>(note).controller!.text,
        retained,
      );
      await capture(t, 'Master Report Notes Retained ${width.toInt()}');
      await tap(t, key('payment-method-report-close-notes'));
      await tap(t, key('payment-method-report-print'));
      expect(key('payment-method-report-print-dialog'), findsOneWidget);
      expect(
        t
            .widget<ButtonStyleButton>(
              key('payment-method-report-print-submit'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<ButtonStyleButton>(key('payment-method-report-save-pdf'))
            .onPressed,
        isNull,
      );
      await capture(t, 'Master Report Print Empty ${width.toInt()}');
      await tap(t, key('payment-method-report-print-orientation'));
      await tap(t, find.text('Landscape').last);
      await tap(t, key('payment-method-report-repeat-header'));
      await capture(t, 'Master Report Print Options ${width.toInt()}');
      await tap(t, accountingCloseIcon().last);
      await tap(t, key('payment-method-report-email'));
      expect(
        t
            .widget<AccountingSelector<String>>(
              find.ancestor(
                of: key('payment-method-report-print-orientation'),
                matching: find.byType(AccountingSelector<String>),
              ),
            )
            .value,
        'Landscape',
      );
      expect(
        t.widget<Checkbox>(key('payment-method-report-repeat-header')).value,
        isTrue,
      );
      await tap(t, key('payment-method-report-print-email'));
      expect(
        t
            .widget<TextField>(key('payment-method-report-email-Subject'))
            .controller!
            .text,
        'Your Payment Method List Report',
      );
      expect(
        t
            .widget<TextField>(key('payment-method-report-email-Report'))
            .controller!
            .text,
        'Payment Method List Report',
      );
      expect(
        t
            .widget<TextField>(key('payment-method-report-email-Report'))
            .decoration!
            .suffixText,
        '.pdf',
      );
      expect(
        t
            .widget<TextField>(key('payment-method-report-email-To'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        t
            .widget<AccountingDescriptionField>(
              key('payment-method-report-email-Body'),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        t
            .widget<ButtonStyleButton>(key('payment-method-report-email-send'))
            .onPressed,
        isNull,
      );
      await capture(t, 'Master Report Email Empty ${width.toInt()}');
      await enterAccountingText(
        t,
        key('payment-method-report-email-Body'),
        'Master report draft.',
      );
      await t.pumpAndSettle();
      await capture(t, 'Master Report Email Entered ${width.toInt()}');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await capture(t, 'Master Report Email Discard ${width.toInt()}');
      await tap(t, find.text('Keep Editing').last);
      expect(
        t
            .widget<AccountingDescriptionField>(
              key('payment-method-report-email-Body'),
            )
            .controller!
            .text,
        'Master report draft.',
      );
      await tap(t, key('payment-method-report-email-close'));
      await tap(t, find.text('Discard').last);
      expect(
        find.byKey(const ValueKey('payment-method-report-email-dialog')),
        findsNothing,
      );
      await tap(t, key('payment-method-report-export'));
      await tap(t, key('payment-method-report-export-PDF'));
      expect(key('payment-method-report-print-dialog'), findsOneWidget);
      expect(
        t.widget<Checkbox>(key('payment-method-report-repeat-header')).value,
        isTrue,
      );
      await tap(t, accountingCloseIcon().last);
      expect(key('payment-method-list-report'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('payment-method-report-filter-Report Period'),
        ),
        findsNothing,
      );
      expect(tables(w), before);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final width in [720.0, 1224.0]) {
    testWidgets('Master management picker preserves draft and scope at $width', (
      t,
    ) async {
      await prepare(t, width);
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: DemoCompany(
            child: AudytApp(workspace: w, showInitialSetup: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder key(String name) => find.byKey(ValueKey(name)).last;
      await tap(t, key('accounting-settings'));
      await tap(t, key('settings-editor-Payment Methods'));
      await tap(t, key('settings-manage-payment-methods'));
      await tap(t, key('payment-method-report'));
      Future<void> open() async {
        await tap(t, key('payment-method-report-export'));
        await tap(
          t,
          key('payment-method-report-export-Add To Management Reports'),
        );
      }

      await open();
      expect(key('payment-method-management-dialog'), findsOneWidget);
      final name = key('payment-method-management-name');
      expect(t.widget<TextField>(name).controller!.text, isEmpty);
      final action = key('payment-method-management-action');
      expect(t.getTopLeft(action).dy, closeTo(t.getTopLeft(name).dy, 1));
      expect(
        t.getTopLeft(name).dx - t.getTopRight(action).dx,
        closeTo(AccountingResponsive.groupGap, 1),
      );
      expect(t.getSize(name).width, greaterThan(200));
      expect(
        t
            .widget<ButtonStyleButton>(key('payment-method-management-add'))
            .onPressed,
        isNull,
      );
      expect(
        t.getSize(key('payment-method-management-add')).width,
        lessThan(t.getSize(name).width),
      );
      await capture(t, 'Master Management New ${width.toInt()}');
      await tap(t, key('payment-method-management-close'));
      expect(find.text('Discard Unsaved Changes?'), findsNothing);
      await open();
      await t.enterText(name, 'Management review');
      await tap(t, key('payment-method-management-action'));
      await capture(t, 'Master Management Action Menu ${width.toInt()}');
      await tap(
        t,
        find
            .descendant(
              of: find.byType(MenuItemButton),
              matching: find.text('Add To An Existing Management Report'),
            )
            .last,
      );
      expect(
        find.byKey(const ValueKey('payment-method-management-name')),
        findsNothing,
      );
      final existing = t.widget<AccountingSelector<String>>(
        find
            .ancestor(
              of: key('payment-method-management-existing'),
              matching: find.byType(AccountingSelector<String>),
            )
            .first,
      );
      expect(existing.options, isEmpty);
      expect(existing.value, isNull);
      expect(find.text('Company Overview'), findsNothing);
      await capture(t, 'Master Management Existing ${width.toInt()}');
      await tap(t, key('payment-method-management-existing'));
      expect(find.text('No management reports available'), findsOneWidget);
      await capture(t, 'Master Management Empty Choices ${width.toInt()}');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Discard Unsaved Changes?'), findsNothing);
      await tap(t, key('payment-method-management-action'));
      await tap(
        t,
        find
            .descendant(
              of: find.byType(MenuItemButton),
              matching: find.text('Create A New Management Report'),
            )
            .last,
      );
      expect(t.widget<TextField>(name).controller!.text, 'Management review');
      await capture(t, 'Master Management Retained ${width.toInt()}');
      final editable = find.descendant(
        of: name,
        matching: find.byType(EditableText),
      );
      await tap(t, name);
      final beforeReflow = t.state<EditableTextState>(editable);
      await t.enterText(
        name,
        'Long management report name to exercise ordinary field width',
      );
      await t.pumpAndSettle();
      expect(t.getSize(name).width, closeTo(600, 1));
      expect(t.state<EditableTextState>(editable), same(beforeReflow));
      expect(t.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(t.testTextInput.isRegistered, isTrue);
      const continuedName =
          'Long management report name to exercise ordinary field width continued';
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: continuedName,
          selection: TextSelection.collapsed(offset: continuedName.length),
        ),
      );
      await t.pumpAndSettle();
      expect(t.widget<TextField>(name).controller!.text, continuedName);
      // Keep the existing capture and retained-draft assertions unchanged.
      t.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Long management report name to exercise ordinary field width',
          selection: TextSelection.collapsed(offset: 59),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, 'Master Management Long Name ${width.toInt()}');
      await tap(t, name);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await capture(t, 'Master Management Discard ${width.toInt()}');
      await tap(t, find.text('Keep Editing'));
      expect(
        t.widget<TextField>(name).controller!.text,
        'Long management report name to exercise ordinary field width',
      );
      await tap(t, key('payment-method-management-close'));
      await tap(t, find.text('Discard'));
      expect(key('payment-method-list-report'), findsOneWidget);
      await open();
      expect(t.widget<TextField>(name).controller!.text, isEmpty);
      await tap(t, key('payment-method-management-close'));
      await tap(t, accountingCloseIcon().last);
      await tap(t, key('payment-method-activity-demo-debit'));
      await tap(t, key('payment-method-report-export'));
      expect(
        t
            .widget<MenuItemButton>(
              key('payment-method-report-export-Add To Management Reports'),
            )
            .onPressed,
        isNull,
      );
      expect(tables(w), before);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final width in [720.0, 1162.0]) {
    testWidgets('report popout labels follow painted field frames at $width', (
      t,
    ) async {
      await prepare(t, width);
      t.view.physicalSize = Size(width, 809);
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: w, showInitialSetup: false),
        ),
      );
      await t.pumpAndSettle();
      Finder key(String id) => find.byKey(ValueKey(id)).last;
      Future<void> aligned(String label, String id) async {
        final frame = key(id);
        await t.ensureVisible(frame);
        await t.pumpAndSettle();
        expect(
          t
              .getTopLeft(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is Text &&
                          widget.data == label &&
                          widget.style?.fontWeight == FontWeight.w600,
                    )
                    .last,
              )
              .dx,
          closeTo(t.getTopLeft(frame).dx, .1),
          reason: '$label follows its field frame',
        );
      }

      await tap(t, key('accounting-settings'));
      await tap(t, key('settings-editor-Payment Methods'));
      await tap(t, key('settings-manage-payment-methods'));
      await tap(t, key('payment-method-report'));
      await tap(t, key('payment-method-report-customise'));
      await aligned(
        'Report Title',
        'payment-method-report-heading-Report Title',
      );
      await capture(t, 'Report Labels Customise Top ${width.toInt()}');
      await tap(t, key('payment-method-report-filter-Company Name'));
      await aligned(
        'Company Name',
        'payment-method-report-heading-Company Name',
      );
      await aligned(
        'Report Title',
        'payment-method-report-heading-Report Title',
      );
      for (final label in [
        'Header Alignment',
        'Footer Alignment',
        'Sort By',
        'Sort Order',
      ]) {
        await aligned(label, 'payment-method-report-$label');
      }
      await capture(t, 'Report Labels Customise Lower ${width.toInt()}');
      final ordinaryTitle = find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == 'Sort Order' &&
                widget.style?.fontWeight == FontWeight.w600,
          )
          .last;
      final ordinaryTitleGap =
          t.getTopLeft(key('payment-method-report-Sort Order')).dy -
          t.getBottomLeft(ordinaryTitle).dy;
      await tap(t, key('payment-method-report-columns-back'));
      await tap(t, key('payment-method-report-save-customisation'));
      await aligned('Custom Report Name', 'payment-method-saved-report-name');
      await aligned(
        'Add This Report To A Group',
        'payment-method-saved-report-group',
      );
      await aligned('Share With', 'payment-method-saved-report-share');
      await capture(t, 'Report Labels Saved Customisation ${width.toInt()}');
      await tap(t, key('payment-method-saved-report-close'));
      await tap(t, key('payment-method-report-print'));
      await aligned('Orientation', 'payment-method-report-print-orientation');
      await capture(t, 'Report Labels Print ${width.toInt()}');
      await tap(t, key('payment-method-report-print-email'));
      for (final label in ['To', 'CC', 'Subject', 'Body', 'Report']) {
        await aligned(label, 'payment-method-report-email-$label');
      }
      await capture(t, 'Report Labels Email ${width.toInt()}');
      await tap(t, key('payment-method-report-email-close'));
      await tap(t, key('payment-method-report-export'));
      await tap(
        t,
        key('payment-method-report-export-Add To Management Reports'),
      );
      await aligned('Action', 'payment-method-management-action');
      await aligned('Management Report Name', 'payment-method-management-name');
      await capture(t, 'Report Labels Management ${width.toInt()}');
      await tap(t, key('payment-method-management-close'));
      await tap(t, key('payment-method-report-notes'));
      await aligned('Notes', 'payment-method-report-note-editor');
      final notesTitle = find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == 'Notes' &&
                widget.style?.fontWeight == FontWeight.w600,
          )
          .last;
      expect(
        t.getTopLeft(key('payment-method-report-note-editor')).dy -
            t.getBottomLeft(notesTitle).dy,
        closeTo(ordinaryTitleGap, .1),
      );
      expect(
        t.getSize(key('payment-method-report-close-notes')).height,
        accountingControlHeight,
      );
      await capture(t, 'Report Labels Notes ${width.toInt()}');
      expect(tables(w), before);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
