import 'package:audyt/app/app.dart';
import 'package:audyt/app/feature_registry.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/linked_record_review.dart';
import 'package:audyt/app/responsive.dart';
import 'package:audyt/features/accounting/presentation/accounting_home_page.dart';
import 'package:audyt/features/accounting/presentation/widgets/accounting_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  testWidgets('shared header keeps its action while subtitle wraps', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    const description =
        'Keep receipts and recorded expenses together, with their accounting status clearly visible to your whole team.';
    await tester.binding.setSurfaceSize(const Size(430, 700));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AccountingTheme.light(),
        home: Scaffold(
          body: AccountingPageHeader(
            routeLabel: 'Expenses',
            title: 'Expenses',
            description: description,
            action: SizedBox(
              key: const ValueKey('shared-header-action'),
              width: 180,
              height: 44,
              child: FilledButton(
                onPressed: () {},
                child: const Text('Record Expense'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final title = tester.getRect(find.text('Expenses'));
    final action = tester.getRect(
      find.byKey(const ValueKey('shared-header-action')),
    );
    final header = tester.getRect(
      find.byKey(const ValueKey('accounting-page-header')),
    );
    final subtitle = tester.getRect(find.text(description));
    expect(title.left - header.left, accountingContentInset);
    expect(subtitle.left, title.left);
    expect(action.top, closeTo(header.top, 0.1));
    expect(action.top, lessThan(title.bottom));
    expect(action.left - title.right, greaterThanOrEqualTo(20));
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(description))
          .didExceedMaxLines,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked-record popouts group their title and subtitle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LinkedRecordReview(workflow: 'Pay Bills')),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Pay Bills'));
    final subtitle = tester.getRect(
      find.text('Design preview · No live records are loaded or posted.'),
    );
    final section = tester.getRect(find.text('Select Existing Bill'));
    final dialog = tester.getRect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first,
    );
    final close = tester.getRect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(title.top - dialog.top, closeTo(24, 0.1));
    expect(title.left - dialog.left, closeTo(24, 0.1));
    expect(
      close.top - dialog.top,
      closeTo(AccountingPopoutTokens.closeInset, 0.1),
    );
    expect(
      dialog.right - close.right,
      closeTo(AccountingPopoutTokens.closeInset, 0.1),
    );
    expect(subtitle.top - title.bottom, closeTo(6, 0.1));
    expect(section.top - subtitle.bottom, closeTo(20, 0.1));
  });

  testWidgets('Home uses the shared heading gaps and mirrored header action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AccountingHomePage(
          data: AccountingHomeData.fromExpenses(
            currencyCode: 'MYR',
            asOf: DateTime(2026, 9, 23),
            expenses: const <AccountingExpense>[],
          ),
          titleKey: 'page-title-home',
          onRecordExpense: () {},
        ),
      ),
    );
    await tester.pump();

    final title = tester.getRect(find.byKey(const ValueKey('page-title-home')));
    final subtitle = tester.getRect(
      find.text('Track expenses and keep your records current.'),
    );
    final header = tester.getRect(
      find.byKey(const ValueKey('accounting-page-header')),
    );
    final action = tester.getRect(
      find.byKey(const ValueKey('home-record-expense-action')),
    );
    final actionText = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('home-record-expense-action')),
        matching: find.text('Record Expense'),
      ),
    );
    final kpiCard = tester.getRect(
      find
          .ancestor(of: find.text('This Month'), matching: find.byType(Card))
          .first,
    );
    final recentTitle = tester.getRect(find.text('Recent Expenses'));
    final recentSubtitle = tester.getRect(
      find.text(
        'Recent recorded expenses. Ledger totals include approved expense entries and adjustments.',
      ),
    );

    expect(subtitle.top - title.bottom, closeTo(6, 0.1));
    expect(title.left - header.left, accountingContentInset);
    expect(subtitle.left, title.left);
    expect(title.left - kpiCard.left, accountingContentInset);
    expect(kpiCard.top - subtitle.bottom, closeTo(34, 0.1));
    expect(action.top, closeTo(title.top, 0.1));
    expect(header.right - action.right, closeTo(0, 0.1));
    expect(action.right - actionText.right, closeTo(20, 0.1));
    expect(recentSubtitle.top - recentTitle.bottom, closeTo(6, 0.1));
    final kpiIcon = tester.getRect(find.byType(AccountingMetricIconBox).first);
    expect(kpiIcon.top - kpiCard.top, closeTo(20, 0.1));
    expect(kpiCard.bottom - kpiIcon.bottom, closeTo(20, 0.1));
  });

  for (final width in [1440.0, 960.0, 800.0]) {
    testWidgets('Home uses the same search and title insets at $width', (
      tester,
    ) async {
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const AudytApp(initialPath: '/home'));
      await tester.pumpAndSettle();

      final date = tester.getRect(
        find.byKey(const ValueKey('global-date-box')),
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('global-search-box')),
      );
      final searchField = tester.widget<TextField>(
        find.byKey(const ValueKey('global-search-field')),
      );
      final searchFrame =
          searchField.decoration!.enabledBorder! as OutlineInputBorder;
      expect(searchFrame.borderRadius, BorderRadius.circular(22));
      final focusedSearchFrame =
          searchField.decoration!.focusedBorder! as OutlineInputBorder;
      expect(focusedSearchFrame.borderSide.width, accountingFocusedBorderWidth);
      final searchIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('global-search-field')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AccountingIcon && widget.icon == Icons.search_rounded,
          ),
        ),
      );
      final searchTextArea = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('global-search-field')),
          matching: find.byType(EditableText),
        ),
      );
      final hint = tester.renderObject<RenderParagraph>(
        find.text('Search transactions and records'),
      );
      expect(hint.didExceedMaxLines, isFalse);
      expect(searchIcon.left - search.left, closeTo(20, 0.1));
      expect(searchTextArea.left - searchIcon.right, closeTo(20, 0.1));
      expect(search.right - searchTextArea.right, closeTo(20, 0.1));
      final hintBox = hint
          .getBoxesForSelection(
            const TextSelection(
              baseOffset: 0,
              extentOffset: 'Search transactions and records'.length,
            ),
          )
          .single;
      final hintRight = hint.localToGlobal(Offset(hintBox.right, 0)).dx;
      expect(search.right - searchTextArea.right, closeTo(20, 0.1));
      expect(search.right - hintRight, inInclusiveRange(20, 26));
      if (width >= 960) {
        final bell = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('global-notifications')),
            matching: find.byType(SvgPicture),
          ),
        );
        expect(
          bell.left - search.right,
          greaterThanOrEqualTo(AccountingResponsive.groupGap),
        );
      }
      final title = tester.getRect(
        find.byKey(const ValueKey('page-title-home')),
      );
      final topBar = tester.getRect(
        find.byKey(const ValueKey('global-top-bar')),
      );
      final lowerControlBottom = date.bottom > search.bottom
          ? date.bottom
          : search.bottom;

      final controlBottomGap = width < 580 ? 16.0 : 18.0;
      expect(
        topBar.bottom - lowerControlBottom,
        closeTo(controlBottomGap, 0.1),
      );
      if (width >= 960) {
        expect(search.top - topBar.top, closeTo(20, 0.1));
      }
      expect(title.top - topBar.bottom, closeTo(26, 0.1));
      expect(
        title.top - lowerControlBottom,
        closeTo(26 + controlBottomGap, 0.1),
      );
    });
  }

  testWidgets('search stays beside the date until its hint runs short', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(650, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp(initialPath: '/home'));
    await tester.pumpAndSettle();

    var date = tester.getRect(find.byKey(const ValueKey('global-date-box')));
    var search = tester.getRect(
      find.byKey(const ValueKey('global-search-box')),
    );
    expect(search.top, closeTo(date.top, 0.1));
    expect(
      search.left - date.right,
      greaterThanOrEqualTo(AccountingResponsive.groupGap),
    );
    expect(search.width, lessThan(283));

    await tester.binding.setSurfaceSize(const Size(540, 900));
    await tester.pumpAndSettle();
    date = tester.getRect(find.byKey(const ValueKey('global-date-box')));
    search = tester.getRect(find.byKey(const ValueKey('global-search-box')));
    expect(
      search.top - date.bottom,
      greaterThanOrEqualTo(AccountingResponsive.groupGap),
    );
  });

  testWidgets('search frame stays fixed when returning to Home', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp(initialPath: '/home'));
    await tester.pumpAndSettle();
    final homeSearch = tester.getRect(
      find.byKey(const ValueKey('global-search-box')),
    );
    await tester.tap(
      find.byKey(const ValueKey('navigation-item-expenses-vendors')),
    );
    await tester.pumpAndSettle();
    final expensesSearch = tester.getRect(
      find.byKey(const ValueKey('global-search-box')),
    );
    expect(expensesSearch.left, homeSearch.left);
    expect(expensesSearch.width, homeSearch.width);
    expect(expensesSearch.height, homeSearch.height);
    expect(expensesSearch.top - homeSearch.top, 0);
    await tester.tap(find.byKey(const ValueKey('navigation-item-home')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('global-search-box'))),
      homeSearch,
    );
  });

  testWidgets('tabbed page and sidebar headings use the same outer gap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AudytApp(initialPath: '/expenses-vendors'));
    await tester.pumpAndSettle();

    final tabs = tester.getRect(
      find.byKey(const ValueKey('area-tabs-expenses-vendors')),
    );
    final pageTitle = tester.getRect(
      find.byKey(const ValueKey('page-title-expenses-vendors')),
    );
    final company = tester.getRect(
      find.byKey(const ValueKey('company-switcher')),
    );
    final overview = tester.getRect(
      find.byKey(const ValueKey('navigation-group-Overview')),
    );

    expect(pageTitle.top - tabs.bottom, closeTo(34, 0.1));
    expect(overview.top - company.bottom, closeTo(34, 0.1));

    final groups = FeatureRegistry.navigationGroups;
    for (var index = 1; index < groups.length; index++) {
      final previousItem = tester.getRect(
        find.byKey(
          ValueKey('navigation-item-${groups[index - 1].features.last.id}'),
        ),
      );
      final nextHeading = tester.getRect(
        find.byKey(ValueKey('navigation-group-${groups[index].id}')),
      );
      expect(
        nextHeading.top - previousItem.bottom,
        closeTo(27, 0.1),
        reason: groups[index].label,
      );
    }
  });

  testWidgets('page action text aligns with the record trash button edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: DemoCompany(
          child: FrontendAreaPage(
            area: 'expenses-vendors',
            title: 'Expenses',
            initialPage: 'Purchase Orders',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = tester.getRect(
      find.byKey(const ValueKey('design-open-form')),
    );
    final actionText = tester.getRect(find.text('Create Purchase Order'));
    final actionIcon = find.descendant(
      of: find.byKey(const ValueKey('design-open-form')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AccountingIcon && widget.icon == Icons.add_rounded,
      ),
    );
    expect(actionIcon, findsNothing);
    final trash = tester.getRect(
      find.byKey(const ValueKey('delete-record-DEMO-PURCHASEORDERS-1')),
    );
    final header = tester.getRect(
      find.byKey(const ValueKey('accounting-page-header')),
    );

    expect(action.right, closeTo(header.right, 0.1));
    expect(actionText.right, closeTo(trash.right, 0.1));
    expect(action.right - actionText.right, closeTo(20, 0.1));
    expect(actionText.left - action.left, closeTo(20, 0.1));
    final actionButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('design-open-form')),
    );
    final trashButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('delete-record-DEMO-PURCHASEORDERS-1')),
    );
    expect(actionButton.style!.minimumSize!.resolve({})!.height, 44);
    expect(trashButton.style!.minimumSize!.resolve({})!.height, 32);
    expect(trash.size, const Size(32, 32));
  });
}
