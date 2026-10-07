import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claim_receipts_proposal_test.dart' show capture, tap;
import 'sales_email_settings_dialog_test.dart' show host, keyed;
import 'restored_page_routes_test.dart' show tables;
import '../support/accounting_test_finders.dart' show accountingCloseIcon;

void main() {
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async {
          if (call.method == 'load' || call.method == 'loadFolder') return null;
          throw StateError('Unexpected preference mutation: ${call.method}');
        }),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );

  test(
    'Accounting preview cannot become durable or a transaction shortcut',
    () {
      expect(
        CompanyPreferences.supportedDefaults.containsKey(
          'Accounting Preferences',
        ),
        isFalse,
      );
      expect(
        liveSettingsForms(const {})
            .any((f) => f.title == 'Accounting Preferences'),
        isFalse,
      );
      for (final title in [
        'Invoices',
        'Quotations',
        'Sales Receipts',
        'Bills',
        'Record Expense',
      ]) {
        expect(
          transactionSettingsFields(title)
              .containsKey('Accounting Preferences'),
          isFalse,
        );
      }
    },
  );
  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'actual Accounting preferences preview, choices, draft and no writes at $width',
      (t) async {
        final w = await host(t, width);
        final before = tables(w);
        await tap(t, keyed('settings-editor-Accounting Preferences'));
        await t.ensureVisible(find.text('Accounting Preferences'));
        await t.pumpAndSettle();
        final left =
            t.getRect(keyed('settings-editor-Accounting Preferences')).left +
            accountingContentInset;
        expect(
          t
              .getRect(
                find.text(
                  'Configure financial periods and report presentation.',
                ),
              )
              .left,
          closeTo(left, 0.01),
        );
        expect(
          t.getRect(keyed('settings-manage-accounting-preferences')).left,
          closeTo(left, 0.01),
        );
        await capture(t, 'Accounting Preferences Section ${width.toInt()}');
        await tap(t, keyed('settings-manage-accounting-preferences'));
        final dialog = t.widget<FrontendFormDialog>(
          find.byType(FrontendFormDialog).last,
        );
        expect(dialog.onCommit, isNull);
        expect(dialog.previewConfirmationEnabled, isFalse);
        expect(dialog.form.fields.map((f) => f.label), [
          'Financial Year Starts',
          'Tax Year Starts',
          'Reporting Basis',
          'Date Format',
          'Currency Format',
          'Duplicate Cheque Warning',
          'Duplicate Supplier Bill Warning',
          'Duplicate Journal Warning',
        ]);
        expect(dialog.form.fields[0].options, [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ]);
        expect(dialog.form.fields[1].options, [
          'January',
          'Same As Financial Year',
        ]);
        expect(dialog.form.fields[2].options, ['Accrual', 'Cash']);
        expect(dialog.form.fields[3].options, [
          'MM/DD/YYYY',
          'DD/MM/YYYY',
          'DD-MM-YYYY',
          'YYYY-MM-DD',
          'YYYY/MM/DD',
          'MM-DD-YYYY',
          'DD.MM.YYYY',
          'MM.DD.YYYY',
          'YYYY.MM.DD',
        ]);
        expect(dialog.form.fields[4].options, [
          r'$123,456.00',
          r'123.456,00 $',
          r'123 456,00 $',
          r'$1,23,456.00',
          r'$ 123.456,00',
        ]);
        expect(
          find.byKey(const ValueKey('design-field-Close Through Date')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-field-Home Currency')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('design-field-Duplicate Warnings')),
          findsNothing,
        );
        await capture(t, 'Accounting Preferences Empty Top ${width.toInt()}');
        await t.ensureVisible(keyed('design-field-Duplicate Journal Warning'));
        await t.pumpAndSettle();
        await capture(
          t,
          'Accounting Preferences Empty Bottom ${width.toInt()}',
        );
        for (final (label, value) in [
          ('Financial Year Starts', 'October'),
          ('Tax Year Starts', 'Same As Financial Year'),
          ('Reporting Basis', 'Cash'),
          ('Date Format', 'YYYY.MM.DD'),
          ('Currency Format', r'123.456,00 $'),
        ]) {
          await tap(t, keyed('design-field-$label'));
          await capture(
            t,
            'Accounting Preferences $label Menu ${width.toInt()}',
          );
          await tap(t, find.text(value).last);
        }
        await tap(t, keyed('design-field-Duplicate Supplier Bill Warning'));
        expect(
          t
              .widget<AccountingSwitchListTile>(
                keyed('design-field-Duplicate Cheque Warning'),
              )
              .value,
          isFalse,
        );
        expect(
          t
              .widget<AccountingSwitchListTile>(
                keyed('design-field-Duplicate Supplier Bill Warning'),
              )
              .value,
          isTrue,
        );
        expect(
          t
              .widget<AccountingSwitchListTile>(
                keyed('design-field-Duplicate Journal Warning'),
              )
              .value,
          isFalse,
        );
        await tap(t, keyed('design-review'));
        expect(find.text('Not Set'), findsNothing);
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Yes'), findsOneWidget);
        expect(
          t.widget<ButtonStyleButton>(keyed('design-review')).onPressed,
          isNull,
        );
        await capture(t, 'Accounting Preferences Review ${width.toInt()}');
        await tap(t, find.text('Back').last);
        await t.ensureVisible(keyed('design-field-Reporting Basis'));
        await t.pumpAndSettle();
        await t.tapAt(t.getCenter(keyed('design-field-Reporting Basis')));
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        // Escape closes the selector only; the edited form remains guarded.
        expect(
          find.descendant(
            of: find.byType(FrontendFormDialog).last,
            matching: find.text('Accounting Preferences'),
          ),
          findsOneWidget,
        );
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(t, 'Accounting Preferences Discard ${width.toInt()}');
        await tap(t, find.text('Keep Editing').last);
        expect(find.text('Cash'), findsOneWidget);
        await tap(t, accountingCloseIcon().last);
        await tap(t, find.text('Discard').last);
        expect(tables(w), before);
        await tap(t, keyed('settings-manage-accounting-preferences'));
        await t.ensureVisible(
          keyed('design-field-Duplicate Supplier Bill Warning'),
        );
        await t.pumpAndSettle();
        expect(
          t
              .widget<AccountingSwitchListTile>(
                keyed('design-field-Duplicate Supplier Bill Warning'),
              )
              .value,
          isFalse,
        );
        await capture(t, 'Accounting Preferences Reopen ${width.toInt()}');
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      },
    );
  }
}
