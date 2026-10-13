import 'package:audyt/app/responsive.dart';
import 'package:audyt/app/accounting_icons.dart';

import 'dart:io';

import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';

import 'journal_workspace_integration_test.dart'
    show captureUi, loadJournalLayoutFonts;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/chart_of_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'page title scope cannot leak icons, secondary face or stretched widths',
    (tester) async {
      await loadJournalLayoutFonts();
      await tester.binding.setSurfaceSize(const Size(460, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => AccountingPageControlScope(
                child: Column(
                  children: [
                    AccountingPageHeader(
                      routeLabel: 'Review',
                      title: 'Accounting Review',
                      description: 'Review records.',
                      action: AccountingButton.outline(
                        context,
                        key: const ValueKey('legacy-title-action'),
                        onPressed: () {},
                        leadingIcon: Icons.fact_check_outlined,
                        child: const Text('Prepare Closing'),
                      ),
                    ),
                    AccountingPageFilterBar(
                      actions: [
                        AccountingButton.outline(
                          context,
                          key: const ValueKey('secondary-icon-action'),
                          onPressed: () {},
                          leadingIcon: Icons.add_rounded,
                          child: const Text('New Journal'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final primary = find.byKey(const ValueKey('legacy-title-action'));
      final button = tester.widget<FilledButton>(primary);
      final rect = tester.getRect(primary);
      expect(rect.right, closeTo(460, 0.1));
      expect(
        rect.width,
        closeTo(
          tester.getRect(find.text('Prepare Closing')).width +
              accountingContentInset * 2,
          0.1,
        ),
      );
      expect(
        button.style!.backgroundColor!.resolve({}),
        AccountingTheme.of(tester.element(primary)).primary,
      );
      expect(
        find.descendant(
          of: primary,
          matching: find.byType(AccountingButtonIcon),
        ),
        findsNothing,
      );
      final secondary = find.byKey(const ValueKey('secondary-icon-action'));
      expect(tester.widget(secondary), isA<OutlinedButton>());
      expect(
        find.descendant(
          of: secondary,
          matching: find.byType(AccountingButtonIcon),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(secondary).width, lessThan(220));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'ordinary actions retain content width inside stretched containers',
    (tester) async {
      await loadJournalLayoutFonts();
      await tester.binding.setSurfaceSize(const Size(720, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('ordinary-stretched-action'),
                    onPressed: () {},
                    leadingIcon: Icons.add_rounded,
                    child: const Text('New Journal'),
                  ),
                  SizedBox(
                    width: 360,
                    child: AccountingButton.primary(
                      context,
                      key: const ValueKey('ordinary-fixed-parent-action'),
                      onPressed: () {},
                      child: const Text('Save Draft'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in [
        'ordinary-stretched-action',
        'ordinary-fixed-parent-action',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.width, lessThan(220));
        expect(rect.height, accountingControlHeight);
      }
      expect(find.byType(AccountingButtonIcon), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets('lone New Journal retains normal button width at $width', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('audyt-lone-journal-');
      final workspace = await AccountingWorkspace.open(
        '${root.path}/books.sqlite',
      );
      addTearDown(() {
        workspace.dispose();
        root.deleteSync(recursive: true);
      });
      await workspace.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      await workspace.createAccount(
        code: '3000',
        name: 'Capital',
        type: AccountType.equity,
      );
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadJournalLayoutFonts();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AccountingTheme.light(),
            home: Scaffold(body: ChartOfAccountsPage(workspace: workspace)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.getRect(find.byKey(const ValueKey('new-journal')));
      final normalButton = tester.getRect(
        find.byKey(const ValueKey('new-ledger-account')),
      );
      expect(button.height, normalButton.height);
      expect(button.width, lessThan(220));
      expect(
        button.width,
        greaterThan(tester.getRect(find.text('New Journal')).width),
      );
      expect(find.byKey(const ValueKey('account-search')), findsNothing);
      await captureUi(tester, 'Chart Lone Journal Button ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [460.0, 600.0, 1000.0]) {
    testWidgets(
      'account status stays on the right while type stays left at $width',
      (tester) async {
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: ChartOfAccountsPage(workspace: workspace, compact: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final card = tester.getRect(find.byType(Card).last);
        final search = tester.getRect(
          find.byKey(const ValueKey('account-search')),
        );
        expect(search.width, closeTo(240, 0.1));
        expect(search.left, closeTo(card.left, 0.1));
        expect(
          tester.getRect(find.text('Search Accounts')).left,
          closeTo(card.left + accountingContentInset, 0.1),
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('account-search')))
              .decoration
              ?.suffixIcon,
          isNull,
        );
        final journal = tester.getRect(
          find.byKey(const ValueKey('new-journal')),
        );
        final actionsFit =
            search.width + journal.width + accountingContentInset <= card.width;
        if (actionsFit) {
          expect(search.top, closeTo(journal.top, 0.1));
          expect(journal.left - search.right, accountingContentInset);
        } else {
          expect(journal.top - search.bottom, accountingContentInset);
        }
        final namedColumns = find
            .byKey(const ValueKey('account-name-cell-1000'))
            .evaluate()
            .isNotEmpty;
        final name = tester.getRect(
          find.text(namedColumns ? 'Demo Bank' : '1000 · Demo Bank'),
        );
        final type = tester.getRect(find.text('Asset').first);
        expect(find.byKey(const ValueKey('account-type-1000')), findsOneWidget);
        final status = tester.getRect(
          find.byKey(const ValueKey('account-status-1000')),
        );
        if (namedColumns) {
          for (final header in ['Code', 'Account', 'Type', 'Status']) {
            expect(find.text(header), findsWidgets);
          }
          final code = tester.getRect(find.text('1000'));
          expect(code.left, closeTo(card.left + accountingContentInset, 0.1));
          final cells = [
            for (final part in ['code', 'name', 'type', 'status'])
              tester.getRect(find.byKey(ValueKey('account-$part-cell-1000'))),
          ];
          final gaps = [
            for (var i = 0; i < cells.length - 1; i++)
              cells[i + 1].left - cells[i].right,
          ];
          expect(gaps[0], greaterThanOrEqualTo(accountingContentInset));
          expect(gaps[0], closeTo(gaps[1], 0.1));
          expect(gaps[1], closeTo(gaps[2], 0.1));
        } else {
          expect(find.text('Account / Type'), findsOneWidget);
          expect(find.text('Status'), findsOneWidget);
          expect(name.left, closeTo(card.left + accountingContentInset, 0.1));
        }
        expect(type.right, lessThan(status.left));
        expect(name.right, lessThan(status.left));
        expect(card.right - status.right, closeTo(accountingContentInset, 0.1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
