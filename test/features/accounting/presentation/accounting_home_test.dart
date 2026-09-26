import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../app/journal_workspace_integration_test.dart' show captureUi;

void main() {
  for (final width in [720.0, 1224.0]) {
    testWidgets('Home empty expenses keeps its action reachable at $width', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var recorded = false;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            theme: AccountingTheme.light(),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: AccountingHomePage(
                data: AccountingHomeData.empty(currencyCode: 'MYR'),
                onRecordExpense: () => recorded = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.widgetWithText(OutlinedButton, 'Record Expense');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(find.text('No expenses recorded yet'), findsOneWidget);
      expect(find.bySemanticsLabel('Receipt'), findsOneWidget);
      final receipt = tester.widget<Icon>(
        find.byKey(const ValueKey('home-empty-expenses-icon')),
      );
      expect(receipt.icon, Icons.receipt_outlined);
      expect(receipt.size, 20);
      expect(
        receipt.color,
        AccountingTheme.of(
          tester.element(
            find.byKey(const ValueKey('home-empty-expenses-icon')),
          ),
        ).mutedForeground,
      );
      await captureUi(tester, 'Home Empty Expenses ${width.toInt()}');
      await tester.tap(action);
      await tester.pump();
      expect(recorded, isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets(
    'Home summary shares visible spare gaps including existing insets',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.binding.setSurfaceSize(const Size(1500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = AccountingHomeData(
        currencyCode: 'MYR',
        recentExpenses: const [],
        postedMonthSales: Money.fromMinor(592736518, 'MYR'),
        postedBankBalance: Money.fromMinor(134332000, 'MYR'),
        bankAccounts: [
          PaymentAccount.create(
            id: 'spacing-bank',
            name: 'Bank',
            type: PaymentAccountType.bank,
            currencyCode: 'MYR',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(body: AccountingHomePage(data: data, reviewCount: 36)),
        ),
      );
      await tester.pump();
      final strip = find.byKey(const ValueKey('home-kpi-strip'));
      double textRight(String label) {
        final metric = find.byKey(ValueKey('home-kpi-$label'));
        return find
            .descendant(of: metric, matching: find.byType(Text))
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)).right)
            .reduce((a, b) => a > b ? a : b);
      }

      final bankLeft = tester
          .getTopLeft(find.byKey(const ValueKey('home-kpi-All Balance')))
          .dx;
      final firstGap =
          bankLeft -
          AccountingResponsive.groupGap -
          1 -
          textRight('This Month');
      final bankGap =
          tester
              .getTopLeft(find.byKey(const ValueKey('home-bank-switcher')))
              .dx -
          textRight('All Balance');
      final lastGap = tester.getRect(strip).right - textRight('Needs Review');
      expect(firstGap, closeTo(bankGap, 1));
      expect(lastGap, closeTo(bankGap, 1));
      final trigger = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('home-bank-switcher')),
      );
      expect(
        trigger.style!.overlayColor!.resolve({WidgetState.hovered}),
        isNot(trigger.style!.overlayColor!.resolve({})),
      );
      await tester.tap(find.byKey(const ValueKey('home-bank-switcher')));
      await tester.pumpAndSettle();
      final triggerRect = tester.getRect(
        find.byKey(const ValueKey('home-bank-switcher')),
      );
      final chevronRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('home-bank-switcher')),
          matching: find.byType(AccountingSelectorChevron),
        ),
      );
      expect(triggerRect.size, const Size.square(accountingSmallControlHeight));
      expect(chevronRect.center.dx, closeTo(triggerRect.center.dx, 0.1));
      expect(chevronRect.center.dy, closeTo(triggerRect.center.dy, 0.1));
      expect(
        tester
                .getRect(find.byKey(const ValueKey('home-bank-option-all')))
                .right +
            4,
        closeTo(triggerRect.right, 0.1),
      );
      final bankOption = tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('home-bank-option-spacing-bank')),
      );
      expect(
        bankOption.style!.backgroundColor!.resolve({WidgetState.hovered}),
        AccountingTheme.of(
          tester.element(find.byKey(const ValueKey('home-bank-switcher'))),
        ).accent,
      );
      expect(find.text('Bank'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bank Balance follows posted movements in the linked bank ledger',
    (tester) async {
      final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
      addTearDown(workspace.dispose);
      final bankId = workspace.database.paymentLedgerAccount(
        workspace.identity.businessId,
        'demo-bank',
      )!;
      final capitalId = (await workspace.accounts())
          .firstWhere((record) => record.account.code == '3000')
          .account
          .id;
      final before = await workspace.report(
        from: DateTime.utc(1),
        through: DateTime.now(),
      );
      final expected = before.rows
          .firstWhere((row) => row.account.id == bankId)
          .endingNetDebit
          .toInt();
      expect(expected, greaterThanOrEqualTo(100000000));
      AccountingHomeData? shown;
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: WorkspaceAccountingHome(
            asOf: DateTime(2026, 9, 30),
            workspace: workspace,
            includeTopSafeArea: false,
            onRecordExpense: () {},
            onDataChanged: (data) => shown = data,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(shown!.bankAccountBalances['demo-bank']!.minorUnits, expected);
      final initialAllBalance = shown!.bankBalance.minorUnits;
      expect(find.text('All Balance'), findsOneWidget);

      await workspace.saveJournal(
        date: DateTime(2026, 9, 30),
        memo: 'Bank balance wiring check',
        lines: [
          JournalLine.debit(
            accountId: bankId,
            amount: Money.fromMinor(12345, 'MYR'),
          ),
          JournalLine.credit(
            accountId: capitalId,
            amount: Money.fromMinor(12345, 'MYR'),
          ),
        ],
      );
      final draft = (await workspace.journals()).firstWhere(
        (record) => record.entry.memo == 'Bank balance wiring check',
      );
      await workspace.approveJournal(
        JournalApproval(
          requestId: EntityId.random(),
          businessId: workspace.identity.businessId,
          journalId: draft.entry.id,
          expectedRevision: draft.metadata.revision,
          actorId: workspace.identity.ownerId,
          approvedAt: DateTime.now().toUtc(),
        ),
      );
      await tester.pumpAndSettle();
      expect(shown!.bankBalance.minorUnits, initialAllBalance + 12345);
    },
  );

  testWidgets('Home review count follows saved and posted journal drafts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1224, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
    addTearDown(workspace.dispose);
    final accounts = await workspace.accounts();
    final debit = accounts.firstWhere(
      (record) => record.account.type == AccountType.asset,
    );
    final credit = accounts.firstWhere(
      (record) => record.account.type == AccountType.equity,
    );
    AccountingHomeData? shown;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: WorkspaceAccountingHome(
          asOf: DateTime(2026, 9, 30),
          workspace: workspace,
          includeTopSafeArea: false,
          onRecordExpense: () {},
          onDataChanged: (data) => shown = data,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = shown!.needsReviewCount;
    await workspace.saveJournal(
      date: DateTime(2026, 9, 30),
      memo: 'Home bounded draft count',
      lines: [
        JournalLine.debit(
          accountId: debit.account.id,
          amount: Money.fromMinor(100, 'MYR'),
        ),
        JournalLine.credit(
          accountId: credit.account.id,
          amount: Money.fromMinor(100, 'MYR'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(shown!.needsReviewCount, baseline + 1);
    final draft = (await workspace.journals()).singleWhere(
      (record) => record.entry.memo == 'Home bounded draft count',
    );
    await workspace.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: workspace.identity.businessId,
        journalId: draft.entry.id,
        expectedRevision: draft.metadata.revision,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pumpAndSettle();
    expect(shown!.needsReviewCount, baseline);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home switches between all and real bank account balances', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workspace = await createDemoWorkspace(asOf: DateTime(2026, 9, 30));
    addTearDown(workspace.dispose);
    await workspace.createAccount(
      code: '1020',
      name: 'Savings Ledger',
      type: AccountType.asset,
    );
    final savingsLedger = (await workspace.accounts())
        .firstWhere((record) => record.account.code == '1020')
        .account
        .id;
    workspace.savePaymentAccount(
      PaymentAccount.create(
        id: 'savings',
        name: 'Savings Sdn Bhd',
        type: PaymentAccountType.bank,
        currencyCode: 'MYR',
      ),
    );
    workspace.database.linkPaymentLedgerAccount(
      workspace.identity.businessId,
      'savings',
      savingsLedger,
    );
    final capitalId = (await workspace.accounts())
        .firstWhere((record) => record.account.code == '3000')
        .account
        .id;
    await workspace.saveJournal(
      date: DateTime(2026, 9, 30),
      memo: 'Savings deposit',
      lines: [
        JournalLine.debit(
          accountId: savingsLedger,
          amount: Money.fromMinor(20000, 'MYR'),
        ),
        JournalLine.credit(
          accountId: capitalId,
          amount: Money.fromMinor(20000, 'MYR'),
        ),
      ],
    );
    final draft = (await workspace.journals()).firstWhere(
      (record) => record.entry.memo == 'Savings deposit',
    );
    await workspace.approveJournal(
      JournalApproval(
        requestId: EntityId.random(),
        businessId: workspace.identity.businessId,
        journalId: draft.entry.id,
        expectedRevision: draft.metadata.revision,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.now().toUtc(),
      ),
    );
    AccountingHomeData? shown;
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: WorkspaceAccountingHome(
          asOf: DateTime(2026, 9, 30),
          workspace: workspace,
          includeTopSafeArea: false,
          onRecordExpense: () {},
          onDataChanged: (data) => shown = data,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(shown!.bankAccountBalances['savings']!.minorUnits, 20000);
    expect(
      shown!.bankBalance.minorUnits,
      shown!.bankAccountBalances.values.fold<int>(
        0,
        (sum, amount) => sum + amount.minorUnits,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('home-bank-switcher')));
    await tester.pumpAndSettle();
    expect(find.text('Savings Sdn Bhd'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-bank-option-savings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-kpi-Savings')), findsOneWidget);
    expect(find.text('RM 200.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-bank-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-bank-option-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-kpi-All Balance')), findsOneWidget);
  });

  for (final width in [1200.0, 1400.0]) {
    testWidgets(
      'Recent Expenses divides spare width equally after content at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final expenses = [
          AccountingExpense(
            occurredOn: DateTime(2026, 9, 3),
            payee: 'Workspace Rental',
            category: 'Rent',
            amount: Money.fromMinor(120000, 'MYR'),
          ),
          AccountingExpense(
            occurredOn: DateTime(2026, 9, 2),
            payee: 'Northwind Office Supplies',
            category: 'Office Supplies',
            amount: Money.fromMinor(18500, 'MYR'),
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: AccountingHomePage(
              data: AccountingHomeData(
                currencyCode: 'MYR',
                recentExpenses: expenses,
                asOf: DateTime(2026, 9, 24),
              ),
            ),
          ),
        );
        await tester.pump();
        final tableFinder = find.byKey(const ValueKey('recent-expenses-table'));
        expect(tableFinder, findsOneWidget);
        final table = tester.widget<Table>(tableFinder);
        final context = tester.element(tableFinder);
        final textTheme = Theme.of(context).textTheme;
        final headerStyle = textTheme.bodySmall?.copyWith(
          color: AccountingTheme.of(context).mutedForeground,
          fontWeight: FontWeight.w600,
        );
        final values = [
          expenses.map((e) => formatAccountingDate(context, e.occurredOn)),
          expenses.map((e) => e.payee!),
          expenses.map((e) => e.category),
          expenses.map((e) => formatAccountingMoney(context, e.amount)),
        ];
        final headings = ['Date', 'Payee', 'Category/Account', 'Amount'];
        final minimums = [
          for (var i = 0; i < headings.length; i++)
            [
              AccountingResponsive.measuredTextWidth(
                context,
                headings[i],
                headerStyle,
              ),
              ...values[i].map(
                (text) => AccountingResponsive.measuredTextWidth(
                  context,
                  text,
                  textTheme.bodyMedium,
                ),
              ),
            ].reduce((a, b) => a > b ? a : b),
        ];
        final allocated = [
          for (var i = 0; i < 4; i++)
            (table.columnWidths![i]! as FixedColumnWidth).value,
        ];
        final gaps = [for (var i = 0; i < 3; i++) allocated[i] - minimums[i]];
        for (final gap in gaps) {
          expect(gap, closeTo(gaps.first, 0.1));
          expect(gap, greaterThanOrEqualTo(AccountingResponsive.groupGap));
        }
        expect(allocated[3], closeTo(minimums[3], 0.1));
        expect(
          allocated.reduce((a, b) => a + b),
          closeTo(tester.getRect(tableFinder).width, 0.1),
        );
        final dateHeader = tester.getRect(find.text('Date'));
        final firstDate = tester.getRect(
          find.text(formatAccountingDate(context, expenses.first.occurredOn)),
        );
        expect(
          firstDate.top - dateHeader.bottom,
          closeTo(accountingContentInset * 2, 1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Home summary uses the last available 20px gaps before splitting',
    (tester) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.binding.setSurfaceSize(const Size(1500, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = AccountingHomeData(
        currencyCode: 'MYR',
        recentExpenses: const [],
        postedMonthSales: Money.fromMinor(68291473, 'MYR'),
        postedYearSales: Money.fromMinor(429736518, 'MYR'),
        postedBankBalance: Money.fromMinor(429736518, 'MYR'),
      );

      for (final (extra, joined) in [(1.0, true), (-1.0, false)]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Builder(
              builder: (context) {
                final minimumWidth = homeKpiCombinedMinWidth(context, data, 36);
                final pageInset = AccountingResponsive.pageInsetFor(
                  MediaQuery.sizeOf(context).width,
                );
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: minimumWidth + pageInset * 2 + extra,
                    child: AccountingHomePage(data: data, reviewCount: 36),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('home-kpi-strip')),
          joined ? findsOneWidget : findsNothing,
        );
        if (joined) {
          for (final value in ['RM 682,914.73', 'RM 4,297,365.18']) {
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(value))
                  .didExceedMaxLines,
              isFalse,
            );
          }
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Home uses one of four shared value sizes for the sales digits', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final (month, year, monthLabel, yearLabel, expectedSize) in [
      (99999, 88888, 'RM 99,999.00', 'RM 88,888.00', 22.0),
      (123456, 99999, 'RM 123,456.00', 'RM 99,999.00', 20.0),
      (123456, 1234567, 'RM 123,456.00', 'RM 1,234,567.00', 18.0),
      (12345678, 1234567, 'RM 12,345,678.00', 'RM 1,234,567.00', 16.0),
    ]) {
      final data = AccountingHomeData(
        currencyCode: 'MYR',
        recentExpenses: const [],
        postedMonthSales: Money.fromMinor(month * 100, 'MYR'),
        postedBankBalance: Money.fromMinor(year * 100, 'MYR'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: AccountingHomePage(data: data, reviewCount: 36),
        ),
      );
      await tester.pump();

      expect(homeKpiValueFontSize(data), expectedSize);
      for (final (metric, value) in [
        ('This Month', monthLabel),
        ('All Balance', yearLabel),
        ('Needs Review', '36 Items'),
      ]) {
        final valueFinder = find.descendant(
          of: find.byKey(ValueKey('home-kpi-$metric')),
          matching: find.text(value),
        );
        expect(valueFinder, findsOneWidget);
        expect(tester.widget<Text>(valueFinder).style?.fontSize, expectedSize);
        expect(
          tester.renderObject<RenderParagraph>(valueFinder).didExceedMaxLines,
          isFalse,
        );
      }
      final monthCard = find.byKey(const ValueKey('home-kpi-This Month'));
      final labelRect = tester.getRect(
        find.descendant(of: monthCard, matching: find.text('This Month')),
      );
      final amountRect = tester.getRect(
        find.descendant(of: monthCard, matching: find.text(monthLabel)),
      );
      final iconRect = tester.getRect(
        find.descendant(
          of: monthCard,
          matching: find.byType(AccountingMetricIconBox),
        ),
      );
      expect(amountRect.top - labelRect.bottom, accountingMetricLineGap);
      expect(
        (labelRect.top + amountRect.bottom) / 2,
        closeTo(iconRect.center.dy, 0.1),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('renders the zero-safe Home anchor on a phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AudytApp());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('This Month'), findsWidgets);
    expect(find.text('Expenses This Year'), findsNothing);
    expect(find.text('Last Recorded'), findsNothing);
    expect(find.text('Recent Expenses'), findsOneWidget);
    expect(find.text('Record Expense'), findsWidgets);
  });

  testWidgets('preserves Home geometry with accessible loading skeletons', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AccountingHomePage(
          data: AccountingHomeData(
            currencyCode: 'USD',
            recentExpenses: const <AccountingExpense>[],
            status: AccountingHomeStatus.loading,
          ),
          includeTopSafeArea: false,
        ),
      ),
    );
    await tester.pump();

    final loading = find.byKey(const ValueKey('accounting-home-loading'));
    expect(loading, findsOneWidget);
    expect(
      tester.getSemantics(loading).label,
      contains('Loading accounting home'),
    );
    expect(
      find.byKey(const ValueKey('expense-overview-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recent-expenses-loading-skeletons')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow the Home loading row at the phone floor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AccountingHomePage(
          data: AccountingHomeData(
            currencyCode: 'USD',
            recentExpenses: const <AccountingExpense>[],
            status: AccountingHomeStatus.loading,
          ),
          includeTopSafeArea: false,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
