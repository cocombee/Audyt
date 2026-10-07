import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test(
    'staged Statement choices do not enter durable or transaction Settings',
    () {
      for (final form in liveSettingsForms(const {})) {
        expect(
          form.fields.any((f) => f.label == 'Transaction Detail'),
          isFalse,
        );
        expect(form.fields.any((f) => f.label == 'Show Ageing Table'), isFalse);
      }
      for (final title in [
        'Invoices',
        'Quotations',
        'Bills',
        'Record Expense',
        'Sales Receipts',
        'Products & Services',
      ]) {
        expect(
          transactionSettingsFields(title).containsKey('Statements'),
          isFalse,
        );
      }
    },
  );

  for (final width in [720.0, 1162.0]) {
    testWidgets('actual Settings Statements preserves preferences at $width', (
      t,
    ) async {
      await prepare(t, width);
      t.view.physicalSize = Size(width, 809);
      final w = await AccountingWorkspace.open(':memory:');
      addTearDown(w.dispose);
      w.savePreferences(
        w.preferences.change('Sales Preferences', {
          'Show Quantity': true,
          'Show Rate': true,
          'Customer Message': 'Keep my existing customer message.',
        }),
      );
      final before = tables(w);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(workspace: w, showInitialSetup: false),
        ),
      );
      await t.pumpAndSettle();
      Finder key(String label) => find.byKey(ValueKey(label)).last;
      Future<void> choose(String value) async {
        await tap(t, key('design-field-Transaction Detail'));
        await tap(t, find.text(value).last);
      }

      await tap(t, key('accounting-settings'));
      await tap(t, key('settings-editor-Statements'));
      await tap(t, key('settings-manage-statements'));
      expect(find.text('Statement Settings'), findsOneWidget);
      expect(
        t
            .widget<AccountingSwitchListTile>(
              key('design-field-Show Ageing Table'),
            )
            .value,
        isFalse,
      );
      await capture(t, 'Statement Settings Empty ${width.toInt()}');
      await tap(t, accountingCloseIcon().last);
      expect(find.text('Discard Unsaved Changes?'), findsNothing);
      expect(find.text('Statement Settings'), findsNothing);
      await tap(t, key('settings-manage-statements'));
      await choose('Single Transaction Line');
      await tap(t, key('design-field-Show Ageing Table'));
      expect(
        t
            .widget<AccountingSwitchListTile>(
              key('design-field-Show Ageing Table'),
            )
            .value,
        isTrue,
      );
      await choose('All Detail Lines');
      await capture(t, 'Statement Settings Details ${width.toInt()}');
      await tap(t, key('design-review'));
      expect(find.byType(AccountingInformationRows), findsOneWidget);
      expect(find.text('All Detail Lines'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(
        t.widget<ButtonStyleButton>(key('design-review')).onPressed,
        isNull,
      );
      await capture(t, 'Statement Settings Review ${width.toInt()}');
      await tap(t, find.text('Back').last);
      await tap(t, accountingCloseIcon().last);
      expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
      await capture(t, 'Statement Settings Discard ${width.toInt()}');
      await tap(t, find.text('Keep Editing').last);
      expect(find.text('All Detail Lines'), findsOneWidget);
      expect(
        t
            .widget<AccountingSwitchListTile>(
              key('design-field-Show Ageing Table'),
            )
            .value,
        isTrue,
      );
      await tap(t, accountingCloseIcon().last);
      await tap(t, find.text('Discard').last);
      expect(find.text('Statement Settings'), findsNothing);
      expect(tables(w), before);
      await tap(t, key('settings-manage-statements'));
      expect(
        t
            .widget<AccountingSwitchListTile>(
              key('design-field-Show Ageing Table'),
            )
            .value,
        isFalse,
      );
      await tap(t, accountingCloseIcon().last);
      expect(tables(w), before);
      expect(t.takeException(), isNull);
    });
  }
}
