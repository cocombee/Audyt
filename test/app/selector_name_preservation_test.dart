import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/transaction_form_layout.dart';

void main() {
  test('selector prompt threshold and first-two-word limit', () {
    expect(
      accountingSelectorHintText('Select Payment Method'),
      'Payment Method',
    );
    expect(
      accountingSelectorHintText('Select Funding Bank Account'),
      'Funding Bank',
    );
    expect(accountingSelectorHintText('Select Multiple ...'), 'Multiple ...');
    expect(
      accountingSelectorHintText('Select Default Tax Code For Purchase'),
      'Default Tax',
    );
    expect(accountingSelectorHintText('Select Tax'), 'Select Tax');
    expect(
      accountingSelectorHintText('Funding Bank Account'),
      'Funding Bank Account',
    );
  });
  testWidgets(
    'long actual selection and non-selector text retain Select prefix',
    (t) async {
      const name = 'Select Main Bank Account';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AccountingSelector<String>(
                  value: 'saved',
                  onChanged: (_) {},
                  hintText: 'Select Funding Bank Account',
                  triggerKey: const ValueKey('retained-long-name'),
                  options: const [
                    AccountingSelectorOption(
                      value: 'saved',
                      label: name,
                      preserveLabelCase: true,
                    ),
                  ],
                ),
                const TextField(decoration: InputDecoration(hintText: name)),
                ElevatedButton(onPressed: () {}, child: const Text(name)),
              ],
            ),
          ),
        ),
      );
      expect(find.text(name), findsNWidgets(3));
      expect(find.text('Main Bank'), findsNothing);
      await t.tap(find.byKey(const ValueKey('retained-long-name')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text(name),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );

  test('UI title casing keeps possessives and proper-case words intact', () {
    expect(accountingTitleCase("Owner's equity"), "Owner's Equity");
    expect(accountingTitleCase('Owner’s equity'), 'Owner’s Equity');
    expect(
      accountingTitleCase("don't change RM or eBay"),
      "Don't Change RM Or eBay",
    );
  });
  testWidgets(
    'selector prompts keep next two words without changing other controls or values',
    (tester) async {
      String? selected;
      late StateSetter update;
      late BuildContext fieldContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                fieldContext = context;
                update = setState;
                return Column(
                  children: [
                    AccountingSelector<String>(
                      value: selected,
                      onChanged: (value) => update(() => selected = value),
                      hintText: 'Select Payment Method',
                      triggerKey: const ValueKey('short-prompt-trigger'),
                      options: const [
                        AccountingSelectorOption(
                          value: 'stored-name',
                          label: 'Select Payment Method',
                          preserveLabelCase: true,
                        ),
                        AccountingSelectorOption(value: 'cash', label: 'Cash'),
                      ],
                    ),
                    AccountingSelector<String>(
                      value: null,
                      onChanged: (_) {},
                      hintText: 'Select Tax',
                      options: const [],
                    ),
                    AccountingSelector<String>(
                      value: null,
                      onChanged: (_) {},
                      hintText: 'Select Cash Back Account',
                      options: const [],
                    ),
                    TextField(
                      decoration: accountingInputDecoration(
                        context,
                        hintText: 'Select Payment Method',
                      ),
                    ),
                    AccountingButton.primary(
                      context,
                      key: const ValueKey('non-selector-button'),
                      onPressed: () {},
                      child: const Text('Select Payment Method'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Payment Method'), findsOneWidget);
      expect(find.text('Select Tax'), findsOneWidget);
      expect(find.text('Cash Back'), findsOneWidget);
      expect(find.text('Select Payment Method'), findsNWidgets(2));
      // Custom transaction columns must measure the shortened prompt too.
      expect(
        AccountingTransactionGridTokens.selectionWidth(
          fieldContext,
          'Select Payment Method',
        ),
        accountingSelectorMinimumWidth(fieldContext, [
          'Payment Method',
        ], stackedLine: true),
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Payment Method, selector'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('short-prompt-trigger')));
      await tester.pumpAndSettle();
      final option = find.byType(MenuItemButton).first;
      expect(
        find.descendant(
          of: option,
          matching: find.text('Select Payment Method'),
        ),
        findsOneWidget,
      );
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(selected, 'stored-name');
      expect(find.text('Payment Method'), findsNothing);
      expect(find.text('Select Payment Method'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets('selector preserves business names in both trigger and options', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountingSelector<String>(
            value: 'account',
            onChanged: (_) {},
            hintText: 'Select Account',
            triggerKey: const ValueKey('name-trigger'),
            options: const [
              AccountingSelectorOption(
                value: 'account',
                label: '1000 · bank eBay sdn bhd',
                preserveLabelCase: true,
              ),
              AccountingSelectorOption(
                value: 'builtin',
                label: 'category code',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('1000 · bank eBay sdn bhd'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('name-trigger')));
    await tester.pumpAndSettle();
    expect(find.text('1000 · bank eBay sdn bhd'), findsWidgets);
    expect(find.text('Category Code'), findsOneWidget);
    expect(find.text('1000 · Bank eBay Sdn Bhd'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
