import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_image_zoom.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'long business details remain visible in invoice rows at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, width == 720 ? 580 : 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final workspace = await AccountingWorkspace.open(':memory:');
        addTearDown(workspace.dispose);
        final preferences = workspace.preferences
            .change('Business Profile', {
              'Business Name': 'Fictional Information Rows Company',
              'Legal Name': 'Fictional Information Rows Company Sdn Bhd',
              'Address Line 1': 'Suite 123, Fictional Business Building',
              'Address Line 2': 'A deliberately long second address line that should wrap without hiding the city or postcode',
              'City': 'Fictional City',
              'State / Region': 'Selangor',
              'Postcode': '12345',
              'Country': 'Malaysia',
              'Email': 'fictional.finance@example.invalid',
              'Telephone': '+60 00 000 0000',
              'Website': 'https://example.invalid',
              'Registration Number': 'FICTIONAL-REGISTRATION',
            })
            .change('Sales Preferences', {
              'Customer Message':
                  'Fictional customer message\nSecond message line',
            })
            .change('Numbering & Document Appearance', {
              'Footer': 'Fictional retained footer',
            });
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.3)),
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showInvoicePreferencesPreview(
                          context,
                          workspace,
                          preferences,
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final title = find.text('Invoice Appearance Preview');
        expect(
          tester.widget<Text>(title).style,
          AccountingTypography.sectionTitle(tester.element(title)),
        );
        expect(
          find.descendant(
            of: find.byType(AccountingImageZoom),
            matching: title,
          ),
          findsNothing,
        );
        expect(
          tester.getRect(title).bottom,
          lessThan(
            tester
                .getRect(
                  find.byKey(
                    const ValueKey('accounting-fitted-popout-content'),
                  ),
                )
                .top,
          ),
        );
        final rows = tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows;
        final factTexts = find.descendant(
          of: find.byType(AccountingInformationRows),
          matching: find.byType(Text),
        );
        final labelStyle = tester.widget<Text>(factTexts.at(0)).style!;
        final informationStyle = tester.widget<Text>(factTexts.at(2)).style!;
        final normalStyle = AccountingTypography.value(tester.element(title));
        expect(informationStyle, normalStyle);
        expect(
          labelStyle,
          AccountingTypography.sidewaysDetailsLabel(tester.element(title)),
        );
        expect(labelStyle.fontSize, normalStyle.fontSize);
        expect(labelStyle.fontFamily, normalStyle.fontFamily);
        expect(labelStyle.fontWeight, FontWeight.w600);
        expect(
          rows,
          contains((
            'Legal Name',
            'Fictional Information Rows Company Sdn Bhd',
          )),
        );
        expect(
          rows,
          contains((
            'Address Line 2',
            preferences.text('Business Profile', 'Address Line 2'),
          )),
        );
        expect(rows, contains(('Email', 'fictional.finance@example.invalid')));
        expect(rows, contains(('Registration', 'FICTIONAL-REGISTRATION')));
        expect(find.text('Fictional Information Rows Company'), findsOneWidget);
        expect(
          find.textContaining('Fictional retained footer'),
          findsOneWidget,
        );
        final page = tester.getRect(
          find.byKey(const ValueKey('invoice-document-page')),
        );
        expect(page.left, greaterThanOrEqualTo(24));
        expect(page.right, lessThanOrEqualTo(width - 24));
        expect(
          page.bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height - 24),
        );
        expect(tester.takeException(), isNull);
        await captureUi(
          tester,
          'Invoice Information Rows ${width.toInt()} Scaled',
        );
        await tester.tap(accountingCloseIcon().last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('invoice-document-dialog')),
          findsNothing,
        );
      },
    );
  }
}
