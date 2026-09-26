import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_description_field.dart';
import 'package:audyt/app/access_design.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  testWidgets('unset optional maintained choice reviews and saves as unset', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => FrontendFormDialog(
                  form: const DesignForm('Optional Selection', [
                    DesignField(
                      'Default Expense Category',
                      choiceLabels: {'expense-a': 'Office Supplies'},
                    ),
                  ]),
                  initial: const {'Default Expense Category': ''},
                  onCommit: (values) async => saved = values,
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
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable Selection'), findsNothing);
    expect(
      tester
          .widget<AccountingInformationRows>(
            find.byType(AccountingInformationRows),
          )
          .rows,
      contains(('Default Expense Category', 'Not Set')),
    );
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pumpAndSettle();
    expect(saved?['Default Expense Category'], '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal fields never inherit narrative wrapping or lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: FrontendFormDialog(
            form: DesignForm('Field Roles', [
              DesignField('Document Number'),
              DesignField('Reference'),
              DesignField('Amount'),
              DesignField('Description'),
              DesignField('Memo Reference'),
              DesignField('Narrative Description', multiline: true),
              DesignField('Memo', multiline: true),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Document Number',
      'Reference',
      'Amount',
      'Description',
      'Memo Reference',
    ]) {
      final input = find.byKey(ValueKey('design-field-$label'));
      final field = tester.widget<TextField>(
        find.descendant(of: input, matching: find.byType(TextField)),
      );
      expect(field.maxLines, 1);
      expect(field.expands, isFalse);
      final originalHeight = tester.getSize(input).height;
      await tester.ensureVisible(input);
      await tester.enterText(
        input,
        label == 'Amount'
            ? '123456789.99'
            : '1. ${List.filled(20, 'ordinary field text').join(' ')}',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, originalHeight);
      expect(
        find.descendant(
          of: input,
          matching: find.byType(AccountingDescriptionField),
        ),
        findsNothing,
      );
    }
    for (final label in ['Narrative Description', 'Memo']) {
      expect(
        tester.widget(find.byKey(ValueKey('design-field-$label'))),
        isA<AccountingDescriptionField>(),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit amount currency uses the standard money field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: const Scaffold(
          body: FrontendFormDialog(
            form: DesignForm('Currency Check', [
              DesignField('Amount Received for Invoice 1', currencyCode: 'USD'),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'Amount Received For Invoice 1 ($)'), findsOneWidget);
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(
          const ValueKey('design-field-Amount Received for Invoice 1'),
        ),
        matching: find.byType(TextField),
      ),
    );
    expect(input.decoration!.prefixIcon, isNull);
  });

  for (final width in [720.0, 1224.0]) {
    testWidgets('account preview uses full-width facts at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(20),
                child: SingleChildScrollView(child: AccessDesignPanel()),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('access-preview-state')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Signed In'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows,
        [
          ('User', 'Preview User'),
          ('Email', 'preview@example.com'),
          ('Business', 'Example Business'),
          ('Role', 'Owner'),
          ('Device', 'This Mac'),
          ('Session', 'Current Session (Preview)'),
        ],
      );
      expect(find.text('Your Session'), findsOneWidget);
      expect(
        find.textContaining('Previously authorised local work'),
        findsNothing,
      );
      await captureUi(tester, 'Account Preview Facts ${width.toInt()}');
      await tester.tap(find.text('Sign Out Of Preview'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountingInformationRows), findsNothing);
      expect(tester.takeException(), isNull);
    });
    for (final count in [2, 3]) {
      testWidgets('$count review facts use the accepted layout at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 580);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        var commits = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => FrontendFormDialog(
                        form: DesignForm('Review Example', [
                          const DesignField('Name'),
                          const DesignField('Reference'),
                          if (count == 3)
                            const DesignField('Memo', multiline: true),
                        ]),
                        initial: const {
                          'Name': 'Meridian Trading',
                          'Reference': 'REVIEW-EXAMPLE-001',
                          'Memo': 'Actual entered details remain readable and keep the full right edge when they wrap in the supported short desktop window.',
                        },
                        onCommit: (_) async {
                          commits++;
                        },
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('design-review')));
        await tester.pumpAndSettle();
        if (count == 3) {
          final facts = tester.widget<AccountingInformationRows>(
            find.byType(AccountingInformationRows),
          );
          expect(facts.rows, [
            ('Name', 'Meridian Trading'),
            ('Reference', 'REVIEW-EXAMPLE-001'),
            (
              'Memo',
              'Actual entered details remain readable and keep the full right edge when they wrap in the supported short desktop window.',
            ),
          ]);
          await captureUi(tester, 'Three Fact Review ${width.toInt()}');
        } else {
          expect(
            tester
                .widget<AccountingInformationRows>(
                  find.byType(AccountingInformationRows),
                )
                .rows,
            [('Name', 'Meridian Trading'), ('Reference', 'REVIEW-EXAMPLE-001')],
          );
        }
        await tester.tap(find.bySemanticsLabel('Close').last);
        await tester.pumpAndSettle();
        expect(commits, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'identity choices display names and save IDs, rejecting removed choices',
    (tester) async {
      Map<String, Object?>? saved;
      Future<void> open(String selected) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => FrontendFormDialog(
                      form: const DesignForm(
                        'Invoices',
                        [
                          DesignField(
                            'Counterparty',
                            required: true,
                            choiceLabels: {
                              'customer-a': 'Same Name',
                              'customer-b': 'Same Name',
                            },
                          ),
                        ],
                        lines: true,
                        lineChoiceLabels: {
                          'Account': {'income-a': 'Sales'},
                        },
                      ),
                      initial: {
                        'Counterparty': selected,
                        '_lines': [
                          {'Account': 'income-a', '_lineId': 'stable-line'},
                        ],
                      },
                      onCommit: (values) async {
                        saved = values;
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
      }

      await open('customer-b');
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingInformationRows>(
              find.byType(AccountingInformationRows),
            )
            .rows,
        contains(('Customer', 'Same Name')),
      );
      expect(find.textContaining('customer-b'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      expect(saved?['Counterparty'], 'customer-b');
      expect((saved?['_lines'] as List).single['Account'], 'income-a');
      expect((saved?['_lines'] as List).single['_lineId'], 'stable-line');
      saved = null;
      await open('removed-customer');
      await tester.tap(find.byKey(const ValueKey('design-review')));
      await tester.pumpAndSettle();
      expect(find.text('Choose an available Counterparty.'), findsOneWidget);
      expect(saved, isNull);
    },
  );
  testWidgets('durable form awaits commit and retains values after failure', (
    tester,
  ) async {
    var attempts = 0;
    var pending = Completer<void>();
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<Map<String, Object?>>(
                  context: context,
                  builder: (_) => FrontendFormDialog(
                    form: const DesignForm('Customers', [
                      DesignField('Name', required: true),
                      DesignField(
                        'Payment Terms',
                        options: ['Days After Issue', 'Day Of Month'],
                      ),
                    ]),
                    initial: const {
                      'Name': 'Retained Customer',
                      'Payment Terms': 'Day Of Month',
                      'Monthly Due Day': '15',
                      'Rollover Within Days': '3',
                    },
                    onCommit: (values) {
                      attempts++;
                      expect(values['Name'], 'Retained Customer');
                      return pending.future;
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pump();
    expect(attempts, 1);
    expect(
      tester
          .widget<AccountingInformationRows>(
            find.byType(AccountingInformationRows),
          )
          .rows,
      contains(('Monthly Due Day', '15')),
    );
    expect(
      tester
          .widget<AccountingInformationRows>(
            find.byType(AccountingInformationRows),
          )
          .rows,
      contains(('Rollover Within Days', '3')),
    );
    expect(find.text('Saving…'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('design-review')),
    );
    expect(button.onPressed, isNull);
    pending.completeError(StateError('storage unavailable'));
    await tester.pumpAndSettle();
    expect(find.textContaining('storage unavailable'), findsOneWidget);
    expect(saved, isNull);
    pending = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('design-review')));
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(saved?['Name'], 'Retained Customer');
    expect(saved?['_preview'], isFalse);
  });
}
