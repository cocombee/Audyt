import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim_store.dart';
import 'package:audyt/features/purchases/presentation/claims_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'enables trigger search when a selector has at least ten options',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: <AccountingSelectorOption<String>>[
                for (var index = 0; index < 10; index++)
                  AccountingSelectorOption<String>(
                    value: 'automatic-$index',
                    label: 'Automatic $index',
                    key: ValueKey<String>('automatic-$index'),
                  ),
              ],
              value: null,
              onChanged: (_) {},
              hintText: 'Choose a value',
              triggerKey: const ValueKey<String>('automatic-trigger'),
              menuKey: const ValueKey<String>('automatic-menu'),
              searchKey: const ValueKey<String>('automatic-search'),
              searchHintText: 'Search values',
            ),
          ),
        ),
      );

      final closedHeight = tester
          .getSize(find.byKey(const ValueKey<String>('automatic-trigger')))
          .height;
      await tester.tap(find.byKey(const ValueKey<String>('automatic-trigger')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('automatic-search')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('automatic-search')))
            .height,
        closeTo(closedHeight, 0.5),
      );
      final paintedFrame = find.descendant(
        of: find.byKey(const ValueKey<String>('automatic-search')),
        matching: find.byType(InputDecorator),
      );
      expect(tester.getSize(paintedFrame).height, closeTo(closedHeight, 0.5));
      final searchField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('automatic-search')),
      );
      expect(
        searchField.decoration!.contentPadding,
        const EdgeInsets.symmetric(
          horizontal: accountingFieldContentInset,
          vertical: 12,
        ),
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey<String>('automatic-search')),
            )
            .getSemanticsData()
            .flagsCollection
            .isTextField,
        isTrue,
      );
    },
  );
  testWidgets(
    'uses the selector trigger as the active search surface without a popup input',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: <AccountingSelectorOption<String>>[
                AccountingSelectorOption<String>(
                  value: 'alpha',
                  label: 'Alpha',
                  key: ValueKey<String>('selector-alpha'),
                ),
                AccountingSelectorOption<String>(
                  value: 'beta',
                  label: 'Beta',
                  key: ValueKey<String>('selector-beta'),
                ),
                AccountingSelectorOption<String>(
                  value: 'gamma',
                  label: 'Gamma',
                  key: ValueKey<String>('selector-gamma'),
                ),
                AccountingSelectorOption<String>(
                  value: 'delta',
                  label: 'Delta',
                  key: ValueKey<String>('selector-delta'),
                ),
                AccountingSelectorOption<String>(
                  value: 'epsilon',
                  label: 'Epsilon',
                  key: ValueKey<String>('selector-epsilon'),
                ),
                for (var index = 5; index < 10; index++)
                  AccountingSelectorOption<String>(
                    value: 'extra-$index',
                    label: 'Extra $index',
                  ),
              ],
              value: 'alpha',
              onChanged: (_) {},
              hintText: 'Choose account',
              triggerKey: const ValueKey<String>('selector-trigger'),
              menuKey: const ValueKey<String>('selector-menu'),
              searchable: true,
              searchKey: const ValueKey<String>('selector-search'),
              searchHintText: 'Search accounts',
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('selector-trigger')));
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey<String>('selector-menu'));
      expect(menu, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('selector-search')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.descendant(of: menu, matching: find.byType(TextField)),
        findsNothing,
      );
      final semantics = tester
          .getSemantics(find.byKey(const ValueKey<String>('selector-search')))
          .getSemanticsData();
      expect(semantics.label, contains('Search accounts'));
      expect(semantics.flagsCollection.isTextField, isTrue);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('selector-search')),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('selector-search')),
        'delta',
      );
      await tester.pump();
      expect(find.text('Delta'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    },
  );

  testWidgets(
    'does not show a search field when a selector has fewer than ten options',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: <AccountingSelectorOption<String>>[
                AccountingSelectorOption<String>(
                  value: 'one',
                  label: 'One',
                  key: ValueKey<String>('small-one'),
                ),
                AccountingSelectorOption<String>(
                  value: 'two',
                  label: 'Two',
                  key: ValueKey<String>('small-two'),
                ),
                AccountingSelectorOption<String>(
                  value: 'three',
                  label: 'Three',
                  key: ValueKey<String>('small-three'),
                ),
                AccountingSelectorOption<String>(
                  value: 'four',
                  label: 'Four',
                  key: ValueKey<String>('small-four'),
                ),
                for (var index = 5; index <= 9; index++)
                  AccountingSelectorOption<String>(
                    value: 'small-$index',
                    label: 'Small $index',
                  ),
              ],
              value: 'one',
              onChanged: (_) {},
              hintText: 'Choose tax treatment',
              triggerKey: const ValueKey<String>('small-trigger'),
              menuKey: const ValueKey<String>('small-menu'),
              searchable: true,
              searchKey: const ValueKey<String>('small-search'),
              searchHintText: 'Search tax treatments',
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('small-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('small-search')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      for (final key in <String>[
        'small-one',
        'small-two',
        'small-three',
        'small-four',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
      }
    },
  );

  testWidgets('the claims category filter keeps its ordinary dropdown', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 1200));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final store = ClaimStore.demo();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: ClaimsPage(store: store)));
    expect(find.byKey(const ValueKey('claims-second-filter')), findsNothing);
    while (store.all.length < 6) {
      store.saveDraft(
        Claim.draft(
          id: EntityId.random(),
          vendorName: 'Test Vendor',
          amount: Money.fromMinor(100, 'MYR'),
        ),
      );
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: ClaimsPage(store: store)));
    await tester.pumpAndSettle();
    final filter = find.byKey(const ValueKey('claims-second-filter'));
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: filter, matching: find.byType(OutlinedButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: filter, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(find.byType(MenuItemButton), findsWidgets);
  });

  testWidgets(
    'compacts selection rows while preserving accessible hit targets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: const <AccountingSelectorOption<String>>[
                AccountingSelectorOption<String>(
                  value: 'one',
                  label: 'One',
                  key: ValueKey<String>('compact-one'),
                ),
                AccountingSelectorOption<String>(
                  value: 'two',
                  label: 'Two',
                  key: ValueKey<String>('compact-two'),
                ),
              ],
              value: 'one',
              onChanged: (_) {},
              hintText: 'Choose an option',
              triggerKey: const ValueKey<String>('compact-trigger'),
              menuKey: const ValueKey<String>('compact-menu'),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('compact-trigger')));
      await tester.pumpAndSettle();

      final first = find.byKey(const ValueKey<String>('compact-one'));
      final second = find.byKey(const ValueKey<String>('compact-two'));
      final firstButton = tester.widget<MenuItemButton>(first);
      final padding = firstButton.style!.padding!
          .resolve(<WidgetState>{})!
          .resolve(TextDirection.ltr);
      expect(padding.vertical, closeTo(10, 0.5));
      expect(tester.getSize(first).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(second).height, greaterThanOrEqualTo(44));
      expect(
        tester.getRect(second).top - tester.getRect(first).bottom,
        closeTo(0, 0.5),
      );
    },
  );

  testWidgets(
    'scrolls long menus while hiding only the native scrollbar chrome',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      final options = <AccountingSelectorOption<String>>[
        for (var index = 0; index < 20; index++)
          AccountingSelectorOption<String>(
            value: 'option-$index',
            label: 'Option $index',
            key: ValueKey<String>('scroll-option-$index'),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: AccountingSelector<String>(
              options: options,
              value: options.first.value,
              onChanged: (_) {},
              hintText: 'Choose an option',
              triggerKey: const ValueKey<String>('scroll-trigger'),
              menuKey: const ValueKey<String>('scroll-menu'),
              menuMaxHeight: 180,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('scroll-trigger')));
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey<String>('scroll-menu'));
      final scroll = find.descendant(
        of: menu,
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroll, findsOneWidget);
      final configuration = find
          .ancestor(of: scroll, matching: find.byType(ScrollConfiguration))
          .first;
      final behavior =
          tester.widget<ScrollConfiguration>(configuration).behavior as dynamic;
      expect(behavior.scrollbars, isFalse);
      expect(
        find.descendant(of: menu, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      final popupScrollbar = find
          .ancestor(of: menu, matching: find.byType(Scrollbar))
          .first;
      expect(
        ScrollbarTheme.of(tester.element(popupScrollbar)).thumbColor
            ?.resolve(<WidgetState>{}),
        Colors.transparent,
      );
      expect(tester.getRect(menu).height, lessThanOrEqualTo(180));
      final lastOption = find.byKey(
        const ValueKey<String>('scroll-option-19'),
        skipOffstage: false,
      );
      await tester.drag(scroll, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getRect(lastOption).bottom, greaterThan(0));
    },
  );

  testWidgets(
    'filters from the trigger and commits the highlighted option with Enter',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      String selected = 'alpha';
      final options = <AccountingSelectorOption<String>>[
        AccountingSelectorOption<String>(
          value: 'alpha',
          label: 'Alpha',
          key: ValueKey<String>('keyboard-alpha'),
        ),
        AccountingSelectorOption<String>(
          value: 'beta',
          label: 'Beta',
          key: ValueKey<String>('keyboard-beta'),
        ),
        AccountingSelectorOption<String>(
          value: 'gamma',
          label: 'Gamma',
          key: ValueKey<String>('keyboard-gamma'),
        ),
        AccountingSelectorOption<String>(
          value: 'delta',
          label: 'Delta',
          key: ValueKey<String>('keyboard-delta'),
        ),
        AccountingSelectorOption<String>(
          value: 'epsilon',
          label: 'Epsilon',
          key: ValueKey<String>('keyboard-epsilon'),
        ),
        for (var index = 5; index < 10; index++)
          AccountingSelectorOption<String>(
            value: 'extra-$index',
            label: 'Extra $index',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AccountingSelector<String>(
                options: options,
                value: selected,
                onChanged: (value) => setState(() => selected = value!),
                hintText: 'Choose account',
                triggerKey: const ValueKey<String>('keyboard-trigger'),
                menuKey: const ValueKey<String>('keyboard-menu'),
                searchable: true,
                searchKey: const ValueKey<String>('keyboard-search'),
                searchHintText: 'Search accounts',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('keyboard-trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('keyboard-search')),
        'del',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(selected, 'delta');
      expect(find.byKey(const ValueKey<String>('keyboard-menu')), findsNothing);
      expect(find.text('Delta'), findsOneWidget);
    },
  );

  testWidgets(
    'uses field-specific search labels and applies the ten-option threshold globally',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1600));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: RecordExpensePage(
            paymentAccounts: <String>[
              'Cash',
              'Bank',
              'Card',
              'Wallet',
              'Reserve',
              'Savings',
              'Current',
              'Petty Cash',
              'Travel',
              'Operations',
            ],
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('expense-category-control')),
      );
      await tester.pumpAndSettle();
      final categorySearch = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('expense-category-search')),
      );
      expect(categorySearch.decoration!.hintText, 'Search categories');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('expense-category-menu')),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('expense-field-payment-account')),
      );
      await tester.pumpAndSettle();
      final accountSearch = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('payment-account-search')),
      );
      expect(accountSearch.decoration!.hintText, 'Search accounts');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('expense-tax-control')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('tax-search-field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('expense-tax-menu')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Payee suggestions use the shared rounded surface, badge rows, and Search payee hint',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      final payeeField = find.byKey(
        const ValueKey<String>('expense-field-payee'),
      );
      final decorator = tester.widget<InputDecorator>(
        find.descendant(of: payeeField, matching: find.byType(InputDecorator)),
      );
      expect(decorator.decoration.hintText, 'Search payee');
      final payeeSemantics = tester.getSemantics(payeeField).getSemanticsData();
      expect(payeeSemantics.label, contains('Search payee'));
      expect(payeeSemantics.flagsCollection.isTextField, isTrue);

      await tester.enterText(payeeField, 'Aina');
      await tester.pumpAndSettle();

      final menu = find.byKey(const ValueKey<String>('expense-payee-menu'));
      expect(menu, findsOneWidget);
      final material = tester.widget<Material>(menu);
      expect(material.borderRadius, BorderRadius.circular(10));
      expect(material.clipBehavior, Clip.antiAlias);
      final fieldRect = tester.getRect(payeeField);
      final menuRect = tester.getRect(menu);
      expect(menuRect.left, closeTo(fieldRect.left, 1));
      // The complete directory can widen the menu to preserve the label gap.
      expect(menuRect.width, greaterThanOrEqualTo(fieldRect.width));
      expect(menuRect.right, lessThanOrEqualTo(952));
      expect((menuRect.top - fieldRect.bottom).abs(), lessThanOrEqualTo(8));
      final option = find.byKey(
        const ValueKey<String>('expense-payee-option-demo-payee-aina-rahman'),
      );
      expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
      expect(option, findsOneWidget);
      expect(find.text('Employee'), findsOneWidget);
      final nameRect = tester.getRect(find.text('Aina Rahman'));
      final labelSurface = find
          .ancestor(
            of: find.text('Employee'),
            matching: find.byType(DecoratedBox),
          )
          .first;
      expect(
        tester.getRect(labelSurface).left - nameRect.right,
        greaterThanOrEqualTo(AccountingSelectionLabel.minimumTextGap - .5),
      );
      expect(find.text('Optional. Choose a payee.'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Optional. Choose a payee.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.byType(TextField)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Escape cancels active filtering without losing the committed selection or helper',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 480));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      String selected = 'alpha';
      final options = <AccountingSelectorOption<String>>[
        AccountingSelectorOption<String>(value: 'alpha', label: 'Alpha'),
        AccountingSelectorOption<String>(value: 'beta', label: 'Beta'),
        AccountingSelectorOption<String>(value: 'gamma', label: 'Gamma'),
        AccountingSelectorOption<String>(value: 'delta', label: 'Delta'),
        AccountingSelectorOption<String>(value: 'epsilon', label: 'Epsilon'),
        for (var index = 5; index < 10; index++)
          AccountingSelectorOption<String>(
            value: 'extra-$index',
            label: 'Extra $index',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AccountingSelector<String>(
                options: options,
                value: selected,
                onChanged: (value) => setState(() => selected = value!),
                hintText: 'Choose account',
                triggerKey: const ValueKey<String>('escape-trigger'),
                menuKey: const ValueKey<String>('escape-menu'),
                searchable: true,
                searchKey: const ValueKey<String>('escape-search'),
                searchHintText: 'Search accounts',
                helperText: 'Required. Choose an account.',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('escape-trigger')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('escape-search')),
        'delta',
      );
      await tester.pump();
      expect(find.text('Delta'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(selected, 'alpha');
      expect(find.byKey(const ValueKey<String>('escape-menu')), findsNothing);
      expect(find.byKey(const ValueKey<String>('escape-search')), findsNothing);
      expect(find.text('Required. Choose an account.'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
    },
  );

  testWidgets(
    'Record Expense does not expose a currency selector owned by account settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1200));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RecordExpensePage()));

      expect(
        find.byKey(const ValueKey<String>('expense-currency-selector')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('currency-search-field')),
        findsNothing,
      );
    },
  );
}
