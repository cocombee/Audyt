import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  testWidgets('action buttons share field height and button typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                AccountingButton.outline(
                  context,
                  key: const ValueKey('compact'),
                  onPressed: () {},
                  child: const Text('View'),
                ),
                AccountingButtonGroup(
                  compact: false,
                  child: AccountingButton.outline(
                    context,
                    key: const ValueKey('field'),
                    onPressed: () {},
                    child: const Text('Run Report'),
                  ),
                ),
                AccountingBadge.build(context, label: 'Ready'),
                AccountingBadge.build(context, label: 'Unpaid'),
              ],
            ),
          ),
        ),
      ),
    );
    final compact = tester.widget<IconButton>(
      find.byKey(const ValueKey('compact')),
    );
    final field = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('field')),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('compact'))),
      const Size(44, 44),
    );
    expect(find.byTooltip('View'), findsOneWidget);
    expect(field.style!.minimumSize!.resolve({})!.height, 44);
    expect(field.style!.textStyle!.resolve({})!.fontSize, 13);
    expect(compact.padding, EdgeInsets.zero);
    expect(field.style!.textStyle!.resolve({})!.fontWeight, FontWeight.w600);
    final ready = tester.widget<Text>(find.text('Ready'));
    final unpaid = tester.widget<Text>(find.text('Unpaid'));
    expect(ready.style!.color, AccountingTokens.light.foreground);
    expect(unpaid.style!.color, AccountingTokens.light.foreground);
    expect(ready.style!.fontSize, 11);
  });

  testWidgets('field text and record actions use their assigned size groups', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => SingleChildScrollView(
              child: Column(
                children: [
                  Text(
                    'Status',
                    style: AccountingTypography.fieldLabel(context),
                  ),
                  TextField(
                    key: const ValueKey('search-field'),
                    decoration: accountingSingleLineInputDecoration(
                      context,
                      hintText: 'Search Tax Overview',
                    ),
                  ),
                  AccountingSelector<String>(
                    value: 'All Dates',
                    options: const [
                      AccountingSelectorOption(
                        value: 'All Dates',
                        label: 'All Dates',
                      ),
                    ],
                    onChanged: (_) {},
                    hintText: 'Date',
                  ),
                  AccountingAddButton.compact(
                    context,
                    key: const ValueKey('add-payee'),
                    label: 'Add Payee',
                    onPressed: () {},
                  ),
                  AccountingRecordRow(
                    title: 'City Fuel',
                    details: const Text('RM 80.00'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('row-image'),
                          onPressed: () {},
                          child: const Text('EXP-002.png'),
                        ),
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('row-view'),
                          onPressed: () {},
                          child: const Text('View'),
                        ),
                        AccountingButton.iconOnly(
                          context,
                          key: const ValueKey('row-trash'),
                          onPressed: () {},
                          icon: Icons.delete_outline,
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                  AccountingRecordActions(
                    actions: [
                      AccountingButton.workflow(
                        context,
                        key: const ValueKey('row-submit'),
                        onPressed: () {},
                        child: const Text('Submit For Review'),
                      ),
                    ],
                    trailing: const [],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Status'));
    expect(title.style!.fontSize, 13);
    expect(title.style!.fontWeight, FontWeight.w600);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('search-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.style.fontSize, 13);
    final selection = tester.widget<Text>(find.text('All Dates'));
    expect(selection.style!.fontSize, 13);
    expect(selection.style!.fontWeight, FontWeight.w400);

    for (final key in ['add-payee', 'row-image']) {
      final button = tester.widget<OutlinedButton>(find.byKey(ValueKey(key)));
      expect(button.style!.minimumSize!.resolve({})!.height, 32);
      expect(tester.getSize(find.byKey(ValueKey(key))).height, 32);
      expect(button.style!.textStyle!.resolve({})!.fontSize, 12);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('row-trash'))),
      const Size(32, 32),
    );
    expect(
      tester.widget<IconButton>(find.byKey(const ValueKey('row-view'))),
      isNotNull,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('row-view'))),
      const Size(32, 32),
    );
    final submit = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('row-submit')),
    );
    expect(submit.style!.minimumSize!.resolve({})!.height, 32);
    expect(submit.style!.textStyle!.resolve({})!.fontSize, 12);
  });
}
