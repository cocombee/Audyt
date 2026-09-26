import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'invoice lines show exact subtotal, tax and total beneath items',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FrontendFormDialog(
                    form: DesignForm(
                      'Invoices',
                      [
                        DesignField('Currency', options: ['MYR']),
                        DesignField(
                          'Tax Mode',
                          options: ['Exclusive', 'Inclusive'],
                        ),
                        DesignField('Memo', multiline: true),
                      ],
                      lines: true,
                      lineFields: [
                        'Description',
                        'Quantity',
                        'Rate',
                        'Tax Rate (%)',
                      ],
                    ),
                    initial: {
                      'Currency': 'MYR',
                      'Tax Mode': 'Exclusive',
                      '_lines': [
                        {
                          'Description': 'Service',
                          'Quantity': '2',
                          'Rate': '100',
                          'Tax Rate (%)': '8',
                        },
                      ],
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('design-line-subtotal')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('design-line-tax')), findsOneWidget);
      expect(find.byKey(const ValueKey('design-line-total')), findsOneWidget);
      expect(find.text('RM 200.00'), findsOneWidget);
      expect(find.text('RM 16.00'), findsOneWidget);
      expect(find.text('RM 216.00'), findsOneWidget);
      final memo = find.byKey(const ValueKey('design-field-Memo'));
      expect(
        tester.getTopLeft(memo).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('design-line-total'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 720.0, 1224.0]) {
    testWidgets(
      'item line keeps add visible and first line permanent at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const FrontendFormDialog(
                      form: DesignForm(
                        'Line Editor',
                        [
                          DesignField('Currency', options: ['MYR']),
                        ],
                        lines: true,
                        lineFields: [
                          'Description',
                          'Quantity',
                          'Rate',
                          'Tax Rate (%)',
                        ],
                      ),
                      initial: {'Currency': 'MYR'},
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final add = find.byKey(const ValueKey('design-add-line'));
        expect(add, findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-remove-line-0')),
          findsNothing,
        );
        expect(tester.getRect(add).right, lessThanOrEqualTo(width));
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(add, findsOneWidget);
        expect(
          find.byKey(const ValueKey('design-remove-line-1')),
          findsOneWidget,
        );
        expect(find.text('Item 1'), findsWidgets);
        expect(find.text('Item 2'), findsWidgets);
        await tester.tap(find.byKey(const ValueKey('design-remove-line-1')));
        await tester.pumpAndSettle();
        expect(find.text('Item 2'), findsNothing);
        expect(find.text('Item 1'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
