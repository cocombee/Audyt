import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/matching_window_test.dart'
    show postMovement;
import '../features/accounting/data/combined_posted_match_test.dart'
    show importRow;

void main() {
  for (final width in [1224.0, 390.0]) {
    testWidgets(
      'one transaction searches and combines its posted records at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        final workspace = await createDemoWorkspace();
        addTearDown(workspace.dispose);
        final business = workspace.identity.businessId;
        final bank = workspace.database.paymentLedgerAccount(
          business,
          'demo-bank',
        )!;
        final first = await postMovement(
          workspace,
          bank,
          DateTime.utc(2026, 9, 25),
          Money.fromMinor(20000, 'MYR'),
          'Search payment 200',
        );
        final second = await postMovement(
          workspace,
          bank,
          DateTime.utc(2026, 9, 26),
          Money.fromMinor(30000, 'MYR'),
          'Search payment 300',
        );
        final statement = importRow(workspace, 50000);
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
                  onReceivePayment: (row, bank) async {},
                  onCreateInvoice: (row, bank) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final review = find.byKey(
          ValueKey('statement-matches-${statement.value}'),
        );
        await tester.ensureVisible(review);
        await tester.tap(review);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('match-search')),
          'Combine customer',
        );
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('search-or-combine-2'));
        final receive = find.byKey(const ValueKey('missing-receive-payment-2'));
        expect(
          tester.getCenter(search).dx,
          lessThan(tester.getCenter(receive).dx),
        );
        expect(
          tester.getCenter(search).dy,
          closeTo(tester.getCenter(receive).dy, 0.1),
        );
        await tester.ensureVisible(search);
        await tester.tap(search);
        await tester.pumpAndSettle();
        expect(find.text('Search or Combine'), findsWidgets);
        for (final field in ['search', 'from', 'through']) {
          final label = find
              .descendant(
                of: find.byKey(ValueKey('transaction-search-$field-label')),
                matching: find.byType(Text),
              )
              .first;
          expect(
            tester.getRect(label).left,
            closeTo(
              tester
                  .getRect(find.byKey(ValueKey('transaction-search-$field')))
                  .left,
              0.1,
            ),
          );
        }
        await tester.enterText(
          find.byKey(const ValueKey('transaction-search-search')),
          'Search payment',
        );
        await tester.pumpAndSettle();
        expect(find.text('Search payment 200'), findsOneWidget);
        expect(find.text('Search payment 300'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('transaction-search-from')),
          '26-09-2026',
        );
        await tester.enterText(
          find.byKey(const ValueKey('transaction-search-through')),
          '26-09-2026',
        );
        final run = find.byKey(
          const ValueKey('run-transaction-search-date-range'),
        );
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        expect(find.text('Search payment 200'), findsNothing);
        expect(find.text('Search payment 300'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('transaction-select-2-$second')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('confirm-transaction-match')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('transaction-search-from')),
          '25-09-2026',
        );
        await tester.ensureVisible(run);
        await tester.tap(run);
        await tester.pumpAndSettle();
        for (final movement in [first, second]) {
          final control = find.byKey(
            ValueKey('transaction-select-2-$movement'),
          );
          await tester.ensureVisible(control);
          await tester.tap(control);
          await tester.pumpAndSettle();
        }
        expect(find.text('Combine and Match'), findsOneWidget);
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('confirm-transaction-match')),
              )
              .onPressed,
          isNotNull,
        );
        final output = Platform.environment['AUDYT_PREVIEW_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$output/Search or Combine ${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(
          find.byKey(const ValueKey('confirm-transaction-match')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('transaction-search-dialog-2')),
          findsNothing,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('match-search')))
              .controller!
              .text,
          'Combine customer',
        );
        expect(find.text('Matched'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('match-search')),
          'Search payment 200',
        );
        await tester.pumpAndSettle();
        expect(find.text('Matched'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('match-search')),
          'Combine customer',
        );
        await tester.pumpAndSettle();
        final acceptance = workspace.database.statementMatchAcceptanceId(
          business,
          statement,
          2,
        )!;
        expect(
          workspace.database
              .statementMatchLedgerMembers(business, acceptance)
              .toSet(),
          {first, second},
        );
        expect(find.textContaining('Search payment 200'), findsOneWidget);
        expect(find.textContaining('Search payment 300'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
