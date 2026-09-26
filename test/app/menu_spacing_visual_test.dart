import '../support/accounting_text_input.dart';
import '../support/accounting_test_finders.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_icons.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:audyt/features/accounting/presentation/customer_page.dart';
import 'package:audyt/features/sales/invoice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['AUDYT_VISUAL_OUTPUT'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final width in [1224.0, 720.0]) {
    testWidgets(
      'matched movement has a trailing green retract icon at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        final journalCount = (await workspace.journals()).length;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: BankingPage(
                  workspace: workspace,
                  compact: true,
                  onReceivePayment: (row, account) async {},
                  onCreateInvoice: (row, account) async {},
                  onRecordExpense: (row, account) async {},
                  onPaymentVoucher: (row, account) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final csv = workspace.database
            .bankStatements(workspace.identity.businessId, 'demo-bank')
            .singleWhere((item) => item.filename == 'Demo Bank.csv');
        await openStatementReview(tester, statementId: csv.id.value);
        final accept = find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key as ValueKey<String>).value.startsWith(
                    'accept-match-',
                  ),
            )
            .first;
        final value = (tester.widget(accept).key as ValueKey<String>).value;
        final sourceRow = RegExp(r'^accept-match-(\d+)-')
            .firstMatch(value)!
            .group(1)!;
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await tester.pumpAndSettle();
        final retract = find.byKey(ValueKey('retract-match-$sourceRow'));
        await tester.ensureVisible(retract);
        await tester.pumpAndSettle();
        final row = tester.getRect(
          find.byKey(ValueKey('accepted-match-row-$sourceRow')),
        );
        final details = tester.getRect(
          find.byKey(ValueKey('accepted-match-details-$sourceRow')),
        );
        final button = tester.getRect(retract);
        expect(button.size, const Size(32, 32));
        expect(button.right, closeTo(row.right, 0.1));
        expect(button.center.dy, closeTo(details.center.dy, 0.1));
        expect(
          button.left - details.right,
          closeTo(accountingContentInset, 0.1),
        );
        final icon = tester.widget<AccountingIcon>(
          find.descendant(of: retract, matching: find.byType(AccountingIcon)),
        );
        expect(icon.icon, Icons.link_outlined);
        expect(icon.smallAction, isTrue);
        expect(icon.color, AccountingTheme.of(tester.element(retract)).primary);
        expect(find.text('Matched'), findsOneWidget);
        expect(find.text('Unmatched'), findsWidgets);
        expect(find.text('Connected'), findsNothing);
        expect(find.text('Not Connected'), findsNothing);
        expect(find.text('Retract Match'), findsNothing);
        await capture(tester, key, 'Matched Movement ${width.toInt()}');
        await tester.tap(retract);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('match-correction-reason')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('confirm-match-retraction')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Enter a correction reason.'), findsOneWidget);
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('match-correction-reason')),
          'Wrong suggested movement',
        );
        await tester.tap(
          find.byKey(const ValueKey('confirm-match-retraction')),
        );
        await tester.pumpAndSettle();
        expect(retract, findsNothing);
        expect(find.text('Matched'), findsNothing);
        expect((await workspace.journals()).length, journalCount);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [1440.0, 900.0, 700.0, 500.0]) {
    testWidgets('Banking menu, search labels and arrow highlights at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: AccountingTheme.light(),
            home: Scaffold(
              body: BankingPage(
                workspace: workspace,
                compact: true,
                onReceivePayment: (row, account) async {},
                onCreateInvoice: (row, account) async {},
                onRecordExpense: (row, account) async {},
                onPaymentVoucher: (row, account) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final csv = workspace.database
          .bankStatements(workspace.identity.businessId, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.csv');
      await openStatementReview(tester, statementId: csv.id.value);
      final search = tester.getRect(find.byKey(const ValueKey('match-search')));
      final label = tester.getRect(
        find.byKey(const ValueKey('match-search-label')),
      );
      expect(search.height, accountingControlHeight);
      expect(search.top - label.bottom, closeTo(8, 0.1));
      final summaryCards = find.byWidgetPredicate(
        (widget) =>
            widget.key.toString().contains('banking-account-demo-bank-'),
      );
      final bottom = summaryCards
          .evaluate()
          .map(
            (element) => tester.getRect(find.byWidget(element.widget)).bottom,
          )
          .reduce((a, b) => a > b ? a : b);
      expect(summaryCards, findsNWidgets(width >= 900 ? 3 : 2));
      expect(
        find.byKey(const ValueKey('banking-account-demo-bank-2')),
        width >= 900 ? findsOneWidget : findsNothing,
      );
      expect(label.top - bottom, closeTo(20, 0.1));
      final controls = [
        'match-search',
        'match-from',
        'match-through',
        'run-match-date-range',
      ];
      final controlsBottom = controls
          .map((name) => tester.getRect(find.byKey(ValueKey(name))).bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(
        tester
                .getRect(
                  find.byKey(const ValueKey('statement-match-file-header')),
                )
                .top -
            controlsBottom,
        closeTo(accountingContentInset, 0.1),
      );
      final rowsLabel = find.byKey(const ValueKey('match-page-size-label'));
      await tester.ensureVisible(rowsLabel);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(rowsLabel).left,
        closeTo(
          tester.getRect(find.text('No Suggested Match').first).left,
          0.1,
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('match-page-size'))).left -
            tester.getRect(rowsLabel).right,
        closeTo(accountingContentInset, 0.1),
      );
      final noMatchRow = tester.getRect(
        find.byKey(const ValueKey('no-suggestion-row-4')),
      );
      final receiveAction = tester.getRect(
        find.byKey(const ValueKey('missing-receive-payment-4')),
      );
      final invoiceAction = tester.getRect(
        find.byKey(const ValueKey('missing-create-invoice-4')),
      );
      expect(invoiceAction.right, closeTo(noMatchRow.right, 0.1));
      expect(receiveAction.center.dy, closeTo(invoiceAction.center.dy, 0.1));
      final title = tester.getRect(
        find.byKey(const ValueKey('statement-match-title-2')),
      );
      final status = tester.getRect(
        find.byKey(const ValueKey('statement-match-status-2')),
      );
      if ((title.center.dy - status.center.dy).abs() < 2) {
        expect(
          status.left - title.right,
          closeTo(accountingRecordTitleLabelGap, 0.1),
        );
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('statement-match-file-header')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('transactions remaining'), findsNothing);
      expect(
        find.textContaining('awaiting reconciliation approval'),
        findsNothing,
      );
      await capture(tester, key, 'Banking ${width.toInt()}');
      final previous = find.byKey(const ValueKey('previous-candidates-3'));
      final next = find.byKey(const ValueKey('next-candidates-3'));
      if (next.evaluate().isNotEmpty) {
        expect(tester.widget<IconButton>(previous).onPressed, isNull);
        expect(tester.widget<IconButton>(next).onPressed, isNotNull);
        for (final direction in ['previous', 'next']) {
          final arrow = find.byKey(ValueKey('$direction-candidates-3'));
          final icon = tester.getRect(
            find
                .descendant(of: arrow, matching: find.byType(AccountingIcon))
                .first,
          );
          final halo = tester.getRect(
            find
                .descendant(
                  of: arrow,
                  matching: find.byType(AccountingMinorHoverHalo),
                )
                .first,
          );
          expect(halo.size, const Size(25, 25));
          expect(halo.center.dx, closeTo(icon.center.dx, 0.1));
          expect(halo.center.dy, closeTo(icon.center.dy, 0.1));
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: tester.getCenter(arrow));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<AccountingMinorHoverHalo>(
                  find.descendant(
                    of: arrow,
                    matching: find.byType(AccountingMinorHoverHalo),
                  ),
                )
                .highlighted,
            isTrue,
          );
          await capture(
            tester,
            key,
            'Banking $direction Arrow Hover ${width.toInt()}',
          );
          await mouse.removePointer();
          await tester.pumpAndSettle();
        }
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(previous).onPressed, isNotNull);
        expect(tester.widget<IconButton>(next).onPressed, isNull);
        await tester.tap(previous);
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(previous).onPressed, isNull);
        expect(tester.widget<IconButton>(next).onPressed, isNotNull);
      }
      await tester.tap(find.byKey(const ValueKey('review-more')));
      await tester.pumpAndSettle();
      final trigger = tester.getRect(find.byKey(const ValueKey('review-more')));
      final first = find.byKey(const ValueKey('show-match-history'));
      final panel = tester.getRect(
        find.ancestor(of: first, matching: find.byType(Material)).first,
      );
      expect(panel.top, closeTo(trigger.bottom + 4, 0.1));
      if (trigger.center.dx >= width / 2) {
        expect(panel.right, closeTo(trigger.right, 0.1));
      } else {
        expect(panel.left, closeTo(trigger.left, 0.1));
      }
      final assets = find.descendant(
        of: find.byKey(const ValueKey('review-add-bank-account')),
        matching: find.byType(AccountingSmallAssetIcon),
      );
      expect(
        tester.widget<AccountingSmallAssetIcon>(assets).asset,
        '075-account-grouping.svg',
      );
      expect(
        tester.widget<AccountingSmallAssetIcon>(assets).paintedSizeAdjustment,
        1,
      );
      // Measure the actual SVG render box, not just its requested size. The
      // wide eye previously grew to 26.3px when height won the aspect ratio.
      for (final entry in {
        '036-eye.svg': 16.5,
        '079-import-export.svg': 15.5,
        '075-account-grouping.svg': 16.5,
      }.entries) {
        final asset = find.byWidgetPredicate(
          (widget) =>
              widget is AccountingSmallAssetIcon && widget.asset == entry.key,
        );
        final svgSize = tester.getSize(
          find.descendant(of: asset, matching: find.byType(SvgPicture)),
        );
        expect(svgSize.longestSide, closeTo(entry.value, 0.01));
        expect(
          svgSize.longestSide -
              AccountingIcon.smallPaintedExtentForAsset(entry.key),
          closeTo(1, 0.01),
        );
      }
      final nearby = find.byKey(const ValueKey('show-match-history'));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: tester.getCenter(nearby));
      await tester.pumpAndSettle();
      await capture(tester, key, 'Banking Menu ${width.toInt()}');
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Banking hides approval before wrapping and restores it on grow',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      await tester.binding.setSurfaceSize(const Size(1224, 1100));
      await tester.pumpWidget(
        MaterialApp(
          theme: AccountingTheme.light(),
          home: Scaffold(
            body: BankingPage(workspace: workspace, compact: true),
          ),
        ),
      );
      for (final width in [1224.0, 700.0, 400.0, 1224.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        await tester.pumpAndSettle();
        final balance = find.byKey(
          const ValueKey('banking-account-demo-bank-0'),
        );
        final unresolved = find.byKey(
          const ValueKey('banking-account-demo-bank-1'),
        );
        expect(balance, findsOneWidget);
        expect(unresolved, findsOneWidget);
        expect(
          find.byKey(const ValueKey('banking-account-demo-bank-2')),
          width == 1224 ? findsOneWidget : findsNothing,
        );
        if (width == 700) {
          expect(tester.getRect(balance).top, tester.getRect(unresolved).top);
        }
        if (width == 400) {
          expect(
            tester.getRect(unresolved).top,
            greaterThan(tester.getRect(balance).bottom),
          );
        }
        // Hiding the summary never hides the document list or approval state.
        expect(
          find.byKey(const ValueKey('imported-statements-header')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final width in [1440.0, 500.0]) {
    for (final customer in [true, false]) {
      testWidgets(
        '${customer ? 'Customer' : 'Invoice'} search/filter rhythm at $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          final workspace = await createDemoWorkspace();
          addTearDown(workspace.dispose);
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: customer
                      ? CustomerPage(workspace: workspace)
                      : InvoicePage(workspace: workspace),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final prefix = customer ? 'customer' : 'invoice';
          final search = tester.getRect(find.byKey(ValueKey('$prefix-search')));
          final label = tester.getRect(
            find.byKey(ValueKey('$prefix-search-label')),
          );
          final header = tester.getRect(
            find.byKey(const ValueKey('accounting-page-header')),
          );
          expect(label.top - header.bottom, closeTo(20, 0.1));
          expect(search.top - label.bottom, closeTo(8, 0.1));
          expect(search.height, accountingControlHeight);
          await capture(
            tester,
            key,
            '${customer ? 'Customer' : 'Invoice'} ${width.toInt()}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
