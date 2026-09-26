import '../support/accounting_text_input.dart';

import 'dart:convert';

import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/live_settings_catalog.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/company_preferences.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/sales/invoice_form.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1224, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Settings has neutral eye Preview left of green Save and commits without closing',
    (tester) async {
      final workspace = await AccountingWorkspace.open(':memory:');
      addTearDown(workspace.dispose);
      await pump(
        tester,
        SingleChildScrollView(
          child: SizedBox(
            width: 680,
            child: FrontendFormDialog(
              form: liveSettingsForms({})
                  .firstWhere((f) => f.title == 'Sales Preferences'),
              embedded: true,
              initial: workspace.preferences.values('Sales Preferences'),
              onCommit: (values) async => workspace.savePreferences(
                workspace.preferences.change('Sales Preferences', values),
              ),
            ),
          ),
        ),
      );
      final preview = find.byKey(const ValueKey('design-preview'));
      final save = find.byKey(const ValueKey('design-save-settings'));
      expect(
        tester.getRect(preview).right,
        lessThan(tester.getRect(save).left),
      );
      expect(tester.getRect(preview).center.dy, tester.getRect(save).center.dy);
      expect(
        find.descendant(
          of: preview,
          matching: find.byWidgetPredicate(
            (w) => w is AccountingIcon && w.icon == Icons.visibility_outlined,
          ),
        ),
        findsOneWidget,
      );
      final tokens = AccountingTheme.light().extension<AccountingTokens>()!;
      expect(
        tester.widget<FilledButton>(save).style!.backgroundColor!.resolve({}),
        tokens.primary,
      );
      expect(
        tester
            .widget<OutlinedButton>(preview)
            .style!
            .backgroundColor!
            .resolve({}),
        isNot(tokens.primary),
      );
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('design-field-Customer Message')),
        'Thank you',
      );
      await tester.tap(
        find.byKey(const ValueKey('design-field-Enable Discounts')),
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        'Thank you',
      );
      expect(
        workspace.preferences.enabled('Sales Preferences', 'Enable Discounts'),
        true,
      );
      expect(save, findsOneWidget);
    },
  );

  test('each Sales switch changes new invoice fields in both directions', () {
    for (final enabled in [false, true]) {
      final preferences = CompanyPreferences.defaults().change(
        'Sales Preferences',
        {'Show Rate': enabled, 'Enable Discounts': enabled},
      );
      final form = invoiceForm(
        {'customer': 'Customer'},
        {'account': 'Sales'},
        preferences: preferences,
      );
      expect(form.lineFields!.contains('Quantity'), enabled);
      expect(form.lineFields!.contains('Rate'), enabled);
      expect(form.lineFields!.contains('Amount'), !enabled);
      expect(form.lineFields!.contains('Discount'), enabled);
    }
  });

  for (final field in [
    'Track Items',
    'Link To Customer',
    'Billable Expenses',
  ]) {
    for (final enabled in [false, true]) {
      testWidgets('$field $enabled changes expense page fields', (
        tester,
      ) async {
        final preferences = CompanyPreferences.defaults().change(
          'Purchase Preferences',
          {
            'Track Items': field == 'Track Items' ? enabled : true,
            'Link To Customer': field == 'Link To Customer' ? enabled : true,
            'Billable Expenses': field == 'Link To Customer'
                ? enabled
                : field == 'Billable Expenses'
                ? enabled
                : true,
          },
        );
        await pump(tester, RecordExpensePage(preferences: preferences));
        final advanced = find.byKey(const ValueKey('expense-advanced-details'));
        await tester.ensureVisible(advanced);
        await tester.tap(find.text('Advanced Accounting Details'));
        await tester.pumpAndSettle();
        if (field == 'Track Items') {
          expect(
            find.byKey(const ValueKey('expense-field-item-or-split')),
            enabled ? findsOneWidget : findsNothing,
          );
        } else if (field == 'Link To Customer') {
          expect(
            find.byKey(const ValueKey('expense-field-customer')),
            enabled ? findsOneWidget : findsNothing,
          );
        } else {
          expect(
            find.byKey(const ValueKey('expense-field-billable')),
            enabled ? findsOneWidget : findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'disabled purchase options retain existing customer, billable and item details',
    (tester) async {
      final preferences = CompanyPreferences.defaults().change(
        'Purchase Preferences',
        {
          'Track Items': false,
          'Link To Customer': false,
          'Billable Expenses': false,
        },
      );
      const draft = RecordExpenseDraft(
        amount: '10.00',
        date: '27-09-2026',
        payee: 'Supplier',
        paymentAccount: 'Cash',
        category: 'Office',
        tax: 'No tax',
        customer: 'Client',
        billable: true,
        dimensions: 'Class A',
        itemOrSplitDetails: 'Saved item',
        notes: 'Keep',
      );
      await pump(
        tester,
        RecordExpensePage(preferences: preferences, savedDraft: draft),
      );
      expect(
        find.byKey(const ValueKey('expense-field-customer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-field-billable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-field-item-or-split')),
        findsOneWidget,
      );
      expect(accountingDescriptionText('Saved item'), findsOneWidget);
    },
  );

  test('every printed Business Profile text field has an invoice consumer', () {
    final values = {
      ...CompanyPreferences.defaults().values('Business Profile'),
    };
    for (final key in values.keys.where(
      (k) => k != 'Business Logo' && k != '_businessLogoBase64',
    )) {
      values[key] = key == 'Country' ? 'Other Country' : 'Value $key';
    }
    final preferences = CompanyPreferences.defaults().change(
      'Business Profile',
      values,
    );
    final heading = [
      invoiceBusinessHeading(preferences),
      ...invoiceBusinessInformationRows(preferences).map((row) => row.$2),
    ].join('\n');
    for (final entry in values.entries.where(
      (e) => e.key != 'Business Logo' && e.key != '_businessLogoBase64',
    )) {
      expect(heading, contains(entry.value as String), reason: entry.key);
    }
    expect(
      invoiceBusinessInformationRows(
        preferences.change('Numbering & Document Appearance', {
          'Show Registration': false,
        }),
      ).map((row) => row.$2).join('\n'),
      isNot(contains('Value Registration Number')),
    );
  });

  for (final enabled in [false, true]) {
    testWidgets(
      'logo, quantity, discount and tax visibility $enabled use actual document popout',
      (tester) async {
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        final logo = base64Encode(
          raster.encodePng(raster.Image(width: 2, height: 2)),
        );
        final preferences = workspace.preferences
            .change('Business Profile', {
              'Business Name': 'Test Business',
              '_businessLogoBase64': logo,
            })
            .change('Sales Preferences', {
              'Show Rate': enabled,
              'Enable Discounts': enabled,
              'Customer Message': 'Message consumer',
            })
            .change('Numbering & Document Appearance', {
              'Show Logo': enabled,
              'Show Tax Breakdown': enabled,
              'Footer': 'Footer consumer',
            });
        await pump(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showInvoicePreferencesPreview(
                context,
                workspace,
                preferences,
              ),
              child: const Text('Open'),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(Image), enabled ? findsOneWidget : findsNothing);
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join('\n');
        expect(texts, contains('Message consumer'));
        expect(texts, contains('Footer consumer'));
        expect(texts, contains('Test Business'));
        expect(
          find.text('Quantity × Rate'),
          enabled ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('1 × 100.00'),
          enabled ? findsOneWidget : findsNothing,
        );
        expect(find.text('Discount'), enabled ? findsOneWidget : findsNothing);
        expect(find.text('Net'), enabled ? findsOneWidget : findsNothing);
        expect(find.text('Tax'), enabled ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
