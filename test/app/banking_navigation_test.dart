import 'package:flutter_svg/flutter_svg.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/banking_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> snapshot(WidgetTester tester, GlobalKey key, String name) async {
  final path = Platform.environment['AUDYT_PREVIEW_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final width in [1440.0, 700.0, 390.0]) {
    testWidgets('document default, review/back and account scope at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final workspace = await createDemoWorkspace();
      addTearDown(workspace.dispose);
      workspace.savePaymentAccount(
        PaymentAccount.create(
          id: 'empty-bank',
          name: 'Empty Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
          bankName: 'Maybank',
        ),
      );
      final notifier = ValueNotifier<String?>(null);
      addTearDown(notifier.dispose);
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
                selectedStatementId: notifier,
                onReceivePayment: (row, bank) async {},
                onCreateInvoice: (row, bank) async {},
                onRecordExpense: (row, bank) async {},
                onPaymentVoucher: (row, bank) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('imported-statements-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statement-match-file-header')),
        findsNothing,
      );
      expect(find.text('Search imported statements'), findsNothing);
      expect(find.byKey(const ValueKey('match-page-size')), findsNothing);
      expect(find.text('Import Statement'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('banking-import-demo-bank')),
        findsNothing,
      );
      final csv = workspace.database
          .bankStatements(workspace.identity.businessId, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.csv');
      final pdf = workspace.database
          .bankStatements(workspace.identity.businessId, 'demo-bank')
          .singleWhere((item) => item.filename == 'Demo Bank.pdf');
      final csvPeriod = workspace.database
          .bankStatement(workspace.identity.businessId, csv.id)!
          .period;
      final pdfPeriod = workspace.database
          .bankStatement(workspace.identity.businessId, pdf.id)!
          .period;
      final first =
          csvPeriod.start.isBefore(pdfPeriod.start) ||
              (csvPeriod.start == pdfPeriod.start &&
                  !csvPeriod.end.isAfter(pdfPeriod.end))
          ? csv
          : pdf;
      final second = first.id == csv.id ? pdf : csv;
      expect(
        tester
            .getTopLeft(
              find.byKey(ValueKey('statement-filename-${first.id.value}')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(ValueKey('statement-filename-${second.id.value}')),
              )
              .dy,
        ),
      );
      final period = tester.getRect(
        find.byKey(ValueKey('statement-period-${csv.id.value}')),
      );
      final title = tester.getRect(
        find.byKey(ValueKey('statement-filename-${csv.id.value}')),
      );
      expect(period.left, closeTo(title.left, 0.1));
      final review = find.byKey(ValueKey('statement-matches-${csv.id.value}'));
      final reconcile = find.byKey(
        ValueKey('reconcile-statement-${csv.id.value}'),
      );
      expect(
        tester.getCenter(review).dx,
        lessThan(tester.getCenter(reconcile).dx),
      );
      await snapshot(tester, key, 'Documents ${width.toInt()}');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('statement-match-file-header')),
        findsOneWidget,
      );
      expect(notifier.value, csv.id.value);
      final mode = find.byKey(const ValueKey('matching-window-switch'));
      expect(find.byTooltip('Switch to 30 days'), findsOneWidget);
      void expectDateModeSize() {
        final svg = find.descendant(
          of: mode,
          matching: find.byType(SvgPicture),
        );
        expect(tester.getSize(svg).longestSide, closeTo(15.5, 0.01));
      }

      expectDateModeSize();
      await tester.ensureVisible(mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Switch to Search All'), findsOneWidget);
      expectDateModeSize();
      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Switch to 7 days'), findsOneWidget);
      expectDateModeSize();
      await tester.tap(mode);
      await tester.pumpAndSettle();
      await snapshot(tester, key, 'Connection Review ${width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('review-back-to-documents')));
      await tester.pumpAndSettle();
      expect(notifier.value, isNull);
      await tester.ensureVisible(reconcile);
      await tester.tap(reconcile);
      await tester.pumpAndSettle();
      final header = tester.getRect(
        find.byKey(const ValueKey('reconciliation-header-card')),
      );
      final form = tester.getRect(
        find.byKey(const ValueKey('reconciliation-form-card')),
      );
      expect(form.top - header.bottom, closeTo(10, 0.1));
      final startField = tester.getRect(
        find.byKey(const ValueKey('reconciliation-start')),
      );
      final startLabel = tester.getRect(find.text('Statement Start'));
      expect(startField.left, closeTo(startLabel.left, 0.1));
      await snapshot(tester, key, 'Reconciliation ${width.toInt()}');
      if (Platform.environment['AUDYT_PREVIEW_DIR'] != null) {
        // Render the calculated view too: its compact opening-item rows and
        // footer do not exist in the initial, empty-balance form above.
        final opening = find.byKey(const ValueKey('reconciliation-opening'));
        final closing = find.byKey(const ValueKey('reconciliation-closing'));
        final calculate = find.byKey(const ValueKey('review-reconciliation'));
        await tester.enterText(opening, '1000');
        await tester.enterText(closing, '1000');
        await tester.ensureVisible(calculate);
        await tester.tap(calculate);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Opening Outstanding Items'));
        await tester.pumpAndSettle();
        await snapshot(tester, key, 'Opening Items ${width.toInt()}');
        await tester.ensureVisible(calculate);
        await tester.pumpAndSettle();
        await snapshot(tester, key, 'Reconciliation Results ${width.toInt()}');
        await tester.enterText(opening, '');
        await tester.enterText(closing, '');
        await tester.pumpAndSettle();
      }
      for (final control in [
        'reconciliation-account-switcher',
        'reconciliation-statement-switcher',
        'reconciliation-review-connections',
        'back-to-matches',
      ]) {
        expect(find.byKey(ValueKey(control)), findsOneWidget);
        expect(tester.getSize(find.byKey(ValueKey(control))).height, 32);
      }
      if (width == 1440) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('review-reconciliation')),
        );
        await tester.tap(find.byKey(const ValueKey('review-reconciliation')));
        await tester.pumpAndSettle();
        final warning = find.byKey(const ValueKey('reconciliation-warning-1'));
        final surface = find
            .descendant(of: warning, matching: find.byType(Container))
            .first;
        expect(
          tester.getRect(surface).top -
              tester
                  .getRect(
                    find.byKey(const ValueKey('reconciliation-form-card')),
                  )
                  .bottom,
          closeTo(20, 0.1),
        );
        expect(
          find.text('Enter balances as exact decimal amounts.'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 10));
        expect(
          find.text('Enter balances as exact decimal amounts.'),
          findsNothing,
        );
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('approve-reconciliation')),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('reconciliation-statement-switcher')),
      );
      await tester.tap(
        find.byKey(const ValueKey('reconciliation-statement-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('reconciliation-statement-option-${second.id.value}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(notifier.value, second.id.value);
      await tester.tap(
        find.byKey(const ValueKey('reconciliation-statement-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('reconciliation-statement-option-${csv.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(notifier.value, csv.id.value);
      await tester.tap(
        find.byKey(const ValueKey('reconciliation-account-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('reconciliation-account-option-demo-savings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo Savings.csv'), findsOneWidget);
      final savings = workspace.database
          .bankStatements(workspace.identity.businessId, 'demo-savings')
          .single;
      expect(notifier.value, savings.id.value);
      await tester.tap(
        find.byKey(const ValueKey('reconciliation-account-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reconciliation-account-option-demo-bank')),
      );
      await tester.pumpAndSettle();
      expect(notifier.value, csv.id.value);
      expect(find.text('Demo Bank.csv'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('back-to-matches')));
      await tester.tap(find.byKey(const ValueKey('back-to-matches')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('imported-statements-header')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('banking-account-switcher')),
      );
      await tester.tap(find.byKey(const ValueKey('banking-account-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('banking-account-option-demo-savings')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo Bank.csv'), findsNothing);
      expect(find.text('Demo Savings.csv'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('banking-account-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('banking-account-option-empty-bank')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No statements imported yet.'), findsOneWidget);
      expect(find.text('Demo Savings.csv'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
