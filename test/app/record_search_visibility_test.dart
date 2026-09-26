import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page({required bool demo}) {
    const content = Scaffold(
      body: FrontendAreaPage(
        area: 'taxes',
        title: 'Taxes',
        initialPage: 'Tax Overview',
      ),
    );
    return MaterialApp(
      theme: AccountingTheme.light(),
      home: demo ? const DemoCompany(child: content) : content,
    );
  }

  testWidgets('Tax search is 240px, iconless, and filters its own rows', (
    tester,
  ) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(page(demo: true));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('preview-record-search'));
    Finder record(String reference) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == reference,
    );
    expect(tester.getSize(search).width, closeTo(240, 0.1));
    expect(
      tester.getSize(search).height,
      closeTo(accountingControlHeight, 0.1),
    );
    final input = tester.widget<TextField>(search);
    expect(input.decoration?.prefixIcon, isNull);
    expect(input.decoration?.suffixIcon, isNull);
    expect(
      input.decoration?.contentPadding,
      const EdgeInsets.symmetric(
        horizontal: accountingFieldContentInset,
        vertical: 12,
      ),
    );
    final hint = tester.getRect(find.text('Search Tax Overview'));
    final firstTitle = tester.getRect(record('DEMO-TAXOVERVIEW-1'));
    expect(hint.left, closeTo(firstTitle.left, 0.1));
    expect(record('DEMO-TAXOVERVIEW-1'), findsOneWidget);
    expect(record('DEMO-TAXOVERVIEW-2'), findsOneWidget);
    await tester.enterText(search, 'DEMO-TAXOVERVIEW-2');
    await tester.pumpAndSettle();
    expect(record('DEMO-TAXOVERVIEW-1'), findsNothing);
    expect(record('DEMO-TAXOVERVIEW-2'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.tap(find.byKey(const ValueKey('preview-filter-Date Range')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    for (final field in ['from', 'through']) {
      final label = tester.getRect(
        find.byKey(ValueKey('preview-custom-$field-label')),
      );
      final control = tester.getRect(
        find.byKey(ValueKey('preview-custom-$field')),
      );
      expect(control.top - label.bottom, closeTo(accountingFieldLabelGap, 0.1));
      expect(
        control.width,
        closeTo(accountingCompactDateFieldWidth + accountingContentInset, 0.1),
      );
    }
    await tester.tap(find.byKey(const ValueKey('preview-filter-Date Range')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last Year').last);
    await tester.pumpAndSettle();
    expect(record('DEMO-TAXOVERVIEW-2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty preview has no record search or date finder', (
    tester,
  ) async {
    await tester.pumpWidget(page(demo: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-record-search')), findsNothing);
    expect(
      find.byKey(const ValueKey('preview-filter-Date Range')),
      findsNothing,
    );
    expect(find.textContaining('No preview records'), findsOneWidget);
  });
}
