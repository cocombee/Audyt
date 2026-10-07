import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart' show accountingCloseIcon;
import '../support/accounting_text_input.dart';
import 'claim_receipts_proposal_test.dart' show prepare, capture, tap;
import 'restored_page_routes_test.dart' show tables;

Finder keyed(String name) => find.byKey(ValueKey(name)).last;

Future<AccountingWorkspace> host(WidgetTester t, double width) async {
  await prepare(t, width);
  t.view.physicalSize = Size(width, 809);
  final w = await AccountingWorkspace.open(':memory:');
  addTearDown(w.dispose);
  w.savePreferences(
    w.preferences.change('Sales Preferences', {
      'Show Quantity': true,
      'Show Rate': true,
      'Customer Message': 'Retain my PDF customer message.',
    }),
  );
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: AudytApp(workspace: w, showInitialSetup: false),
    ),
  );
  await t.pumpAndSettle();
  await tap(t, keyed('accounting-settings'));
  return w;
}

Future<void> choose(WidgetTester t, String label, String choice) async {
  await tap(t, keyed('design-field-$label'));
  await tap(t, find.text(choice).last);
}

Future<void> enter(WidgetTester t, String label, String value) async {
  final field = keyed('design-field-$label');
  await t.ensureVisible(field);
  await enterAccountingText(t, field, value);
  await t.pumpAndSettle();
}

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

  test('email previews stay outside durable and transactional preferences', () {
    expect(
      liveSettingsForms(const {})
          .any((f) => f.title == 'Messages' || f.title == 'Online Delivery'),
      isFalse,
    );
    for (final title in [
      'Invoices',
      'Quotations',
      'Sales Receipts',
      'Bills',
      'Record Expense',
    ]) {
      final sections = transactionSettingsFields(title);
      expect(sections.containsKey('Messages'), isFalse);
      expect(sections.containsKey('Online Delivery'), isFalse);
    }
  });

  for (final width in [720.0, 1162.0]) {
    testWidgets(
      'actual Messages route keeps PDF preferences and drafts at $width',
      (t) async {
        final w = await host(t, width);
        final before = tables(w);
        await tap(t, keyed('settings-editor-Messages'));
        final section = t.getRect(keyed('settings-editor-Messages'));
        final helper = t.getRect(
          find.text('Configure email greetings and messages.'),
        );
        final manage = t.getRect(keyed('settings-manage-messages'));
        expect(
          helper.left,
          closeTo(section.left + accountingContentInset, 0.01),
        );
        expect(manage.left, closeTo(helper.left, 0.01));
        await capture(t, 'Sales Email Messages Section ${width.toInt()}');
        await tap(t, keyed('settings-manage-messages'));
        expect(find.text('Sales Email Messages'), findsOneWidget);
        expect(
          t
              .widget<ButtonStyleButton>(keyed('email-use-standard-message'))
              .onPressed,
          isNull,
        );
        expect(
          t.getSize(keyed('email-use-standard-message')).width,
          lessThan(600),
        );
        await capture(t, 'Sales Email Messages Empty ${width.toInt()}');
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        expect(tables(w), before);
        await tap(t, keyed('settings-manage-messages'));
        await tap(t, keyed('design-review'));
        expect(
          find.text('Complete Sales Form before reviewing.'),
          findsOneWidget,
        );
        for (final (label, options) in <(String, List<String>)>[
          ('Salutation', ['<Blank>', 'To:', 'Dear']),
          (
            'Name Format',
            [
              '[First] [Last]',
              '[Title] [Last]',
              '[First]',
              '[Full Name]',
              '[Company Name]',
              '[Display Name]',
            ],
          ),
          (
            'Sales Form',
            [
              'Invoice',
              'Quotation',
              'Credit Note',
              'Sales Receipt',
              'Statement',
              'Refund Receipt',
            ],
          ),
        ]) {
          await tap(t, keyed('design-field-$label'));
          for (final option in options) {
            expect(find.text(option), findsWidgets);
          }
          await capture(t, 'Sales Email $label Options ${width.toInt()}');
          await tap(t, find.text(options.last).last);
        }
        await choose(t, 'Sales Form', 'Invoice');
        expect(
          find.text('Complete Sales Form before reviewing.'),
          findsNothing,
        );
        await tap(t, keyed('design-field-Use Greeting'));
        await enter(t, 'Email Subject Line', 'Fictional invoice review');
        await enter(
          t,
          'Email Message',
          'Fictional message only.\nSecond line.',
        );
        await tap(t, keyed('design-field-Email Me A Copy'));
        await enter(t, 'Copy (Cc)', 'copy@example.test');
        await enter(t, 'Blind Copy (Bcc)', 'blind@example.test');
        await capture(t, 'Sales Email Messages Entered ${width.toInt()}');
        await tap(t, keyed('design-review'));
        expect(find.byType(AccountingInformationRows), findsOneWidget);
        expect(find.text('Fictional invoice review'), findsOneWidget);
        expect(find.text('copy@example.test'), findsOneWidget);
        expect(
          t.widget<ButtonStyleButton>(keyed('design-review')).onPressed,
          isNull,
        );
        await capture(t, 'Sales Email Messages Review ${width.toInt()}');
        await tap(t, keyed('design-back'));
        await enter(t, 'Email Message', 'Fictional retained message.');
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await capture(t, 'Sales Email Messages Discard ${width.toInt()}');
        await tap(t, find.text('Keep Editing').last);
        expect(
          accountingDescriptionText('Fictional retained message.'),
          findsOneWidget,
        );
        await tap(t, accountingCloseIcon().last);
        await tap(t, find.text('Discard').last);
        expect(tables(w), before);
        await tap(t, keyed('settings-manage-messages'));
        expect(
          t
              .widget<TextFormField>(keyed('design-field-Email Subject Line'))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          t
              .widget<AccountingSwitchListTile>(
                keyed('design-field-Use Greeting'),
              )
              .value,
          isFalse,
        );
        await tap(t, accountingCloseIcon().last);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'actual Online Delivery options and guarded preview at $width',
      (t) async {
        final w = await host(t, width);
        final before = tables(w);
        await tap(t, keyed('settings-editor-Online Delivery'));
        final section = t.getRect(keyed('settings-editor-Online Delivery'));
        final helper = t.getRect(
          find.text('Configure sales email content and PDF attachments.'),
        );
        final manage = t.getRect(keyed('settings-manage-online-delivery'));
        expect(
          helper.left,
          closeTo(section.left + accountingContentInset, 0.01),
        );
        expect(manage.left, closeTo(helper.left, 0.01));
        await capture(t, 'Online Delivery Section ${width.toInt()}');
        await tap(t, keyed('settings-manage-online-delivery'));
        final email = t.getRect(keyed('design-field-Email Options'));
        final invoice = t.getRect(
          keyed('design-field-Additional Email Options For Invoices'),
        );
        expect(invoice.top, closeTo(email.top, 0.01));
        expect(
          invoice.left,
          greaterThanOrEqualTo(email.right + accountingContentInset),
        );
        await capture(t, 'Online Delivery Empty ${width.toInt()}');
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsNothing);
        await tap(t, keyed('settings-manage-online-delivery'));
        await tap(t, keyed('design-review'));
        expect(
          find.text(
            'Complete Email Options, Additional Email Options For Invoices before reviewing.',
          ),
          findsOneWidget,
        );
        await tap(t, keyed('design-field-Email Options'));
        expect(find.text('Show Short Summary In Email'), findsWidgets);
        expect(find.text('Show Full Details In Email'), findsWidgets);
        await capture(t, 'Online Delivery Summary Options ${width.toInt()}');
        await tap(t, find.text('Show Full Details In Email').last);
        expect(
          find.text(
            'Complete Additional Email Options For Invoices before reviewing.',
          ),
          findsOneWidget,
        );
        await tap(t, keyed('design-field-PDF Attached'));
        await tap(
          t,
          keyed('design-field-Additional Email Options For Invoices'),
        );
        expect(find.text('Online Invoice'), findsWidgets);
        expect(find.text('Plain Text'), findsWidgets);
        await capture(t, 'Online Delivery Invoice Options ${width.toInt()}');
        await tap(t, find.text('Plain Text').last);
        expect(find.textContaining('before reviewing.'), findsNothing);
        await capture(t, 'Online Delivery Details ${width.toInt()}');
        await tap(t, keyed('design-review'));
        expect(find.byType(AccountingInformationRows), findsOneWidget);
        expect(find.text('Show Full Details In Email'), findsOneWidget);
        expect(find.text('Plain Text'), findsOneWidget);
        expect(
          t.widget<ButtonStyleButton>(keyed('design-review')).onPressed,
          isNull,
        );
        await capture(t, 'Online Delivery Review ${width.toInt()}');
        await tap(t, accountingCloseIcon().last);
        expect(find.text('Discard Unsaved Changes?'), findsOneWidget);
        await tap(t, find.text('Keep Editing').last);
        await tap(t, keyed('design-back'));
        expect(find.text('Plain Text'), findsOneWidget);
        await tap(t, accountingCloseIcon().last);
        await tap(t, find.text('Discard').last);
        expect(tables(w), before);
        await tap(t, keyed('settings-manage-online-delivery'));
        expect(
          t
              .widget<AccountingSwitchListTile>(
                keyed('design-field-PDF Attached'),
              )
              .value,
          isFalse,
        );
        await tap(t, accountingCloseIcon().last);
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('required warnings update without clearing a command error', (
    t,
  ) async {
    await prepare(t, 720);
    await t.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: FrontendFormDialog(
          form: const DesignForm('Required Field Warning Check', [
            DesignField('Name', required: true),
            DesignField('Type', required: true, options: ['One', 'Two']),
          ]),
          onCommit: (_) async => throw StateError('Retain this command error'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, keyed('design-review'));
    expect(find.text('Complete Name, Type before reviewing.'), findsOneWidget);
    await enter(t, 'Name', 'Fictional');
    expect(find.text('Complete Type before reviewing.'), findsOneWidget);
    await choose(t, 'Type', 'One');
    expect(find.textContaining('before reviewing.'), findsNothing);
    await tap(t, keyed('design-review'));
    await tap(t, keyed('design-review'));
    expect(find.textContaining('Retain this command error'), findsOneWidget);
    await tap(t, keyed('design-back'));
    await enter(t, 'Name', 'Still fictional');
    expect(find.textContaining('Retain this command error'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
