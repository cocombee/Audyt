import 'package:audyt/app/field_guidance.dart';
import 'package:audyt/app/field_row_trial.dart';
import 'package:audyt/app/transaction_form_layout.dart';

import '../support/accounting_test_finders.dart';
import '../support/accounting_text_input.dart';
import '../support/fixed_popout_host.dart';

import 'package:audyt/features/accounting/presentation/audit_log_dialog.dart';

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';

// Geometry always uses the installed app fonts. Capture flags control files,
// not font metrics or which field-fit rules the test exercises.
Future<void> loadJournalLayoutFonts() async {
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  await (FontLoader('Arial')..addFont(
        Future.value(
          ByteData.sublistView(
            File('/System/Library/Fonts/Supplemental/Arial.ttf')
                .readAsBytesSync(),
          ),
        ),
      ))
      .load();
}

Future<void> captureUi(WidgetTester tester, String name) async {
  final directory = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
  if (directory == null) {
    return;
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('workspace-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<int> paintedTextTop(WidgetTester tester, Rect text) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('workspace-capture')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final imageWidth = image.width;
    image.dispose();
    for (var y = text.top.ceil(); y < text.bottom.floor(); y++) {
      for (var x = text.left.ceil(); x < text.right.floor(); x++) {
        final offset = (y * imageWidth + x) * 4;
        if (bytes[offset] < 150 &&
            bytes[offset + 1] < 150 &&
            bytes[offset + 2] < 150) {
          return y;
        }
      }
    }
    throw StateError('No painted text inside $text');
  }))!;
}

void main() {
  testWidgets(
    'manual journal requires balance, saves for review and posts durably',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1224, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('audyt-journal-ui-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/ledger.sqlite';
      var workspace = await AccountingWorkspace.open(path);
      await workspace.createAccount(
        code: '1000',
        name: 'Cash',
        type: AccountType.asset,
      );
      await workspace.createAccount(
        code: '3000',
        name: 'Owner Capital',
        type: AccountType.equity,
      );
      await loadJournalLayoutFonts();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(initialPath: '/accounting', workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-journal')));
      await tester.pumpAndSettle();
      await enterAccountingText(
        tester,
        find.byKey(const ValueKey('journal-memo')),
        'Owner Contribution',
      );
      await tester.tap(find.byKey(const ValueKey('journal-account-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1000 · Cash').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('journal-debit-0')),
        '100.00',
      );
      await tester.tap(find.byKey(const ValueKey('journal-account-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3000 · Owner Capital').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('journal-credit-1')),
        '90.00',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AccountingMemoSummary>(find.byType(AccountingMemoSummary))
            .rows,
        [('Total Debit (RM)', '100.00'), ('Total Credit (RM)', '90.00')],
      );
      await tester.tap(find.byKey(const ValueKey('save-journal-draft')));
      await tester.pumpAndSettle();
      expect(
        find.text('Total debits must equal total credits.'),
        findsOneWidget,
      );
      expect(await workspace.journals(), isEmpty);
      await captureUi(tester, 'New Journal Unbalanced 1224');
      await tester.enterText(
        find.byKey(const ValueKey('journal-credit-1')),
        '100.00',
      );
      await tester.tap(find.byKey(const ValueKey('save-journal-draft')));
      await tester.pumpAndSettle();
      final draft = (await workspace.journals()).single;
      expect(draft.entry.state, JournalEntryState.draft);
      final navigation = find.byKey(
        const ValueKey('navigation-item-accounting'),
      );
      await tester.ensureVisible(navigation);
      await tester.tap(navigation);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Journal Review'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('review-journal-${draft.entry.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('journal-review-lines-table')),
          matching: find.text('100.00'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('Debit (RM)'), findsOneWidget);
      expect(find.text('Credit (RM)'), findsOneWidget);
      expect(find.text('Account 1'), findsNothing);
      await captureUi(tester, 'Journal Review 1224');
      await tester.tap(find.byKey(const ValueKey('approve-journal')));
      await tester.pumpAndSettle();
      expect(find.text('Owner Contribution'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-drafts')), findsNothing);
      expect(
        (await workspace.journals()).single.entry.state,
        JournalEntryState.posted,
      );
      expect(
        await workspace.database.auditEvents(workspace.identity.businessId),
        hasLength(1),
      );
      showDialog<void>(
        context: tester.element(find.byType(Scaffold).first),
        builder: (_) => AuditLogDialog(workspace: workspace),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audit-event-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('audit-open-journal-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audit-open-journal-1')));
      await tester.pumpAndSettle();
      expect(find.text('Posted Journal'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('journal-review-lines-table')),
          matching: find.text('100.00'),
        ),
        findsNWidgets(2),
      );
      expect(find.byKey(const ValueKey('approve-journal')), findsNothing);
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      await tester.tap(accountingCloseIcon().last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-posted')), findsNothing);
      expect(find.byKey(const ValueKey('journal-search')), findsNothing);

      expect(find.text('Owner Contribution'), findsOneWidget);
      await captureUi(tester, 'Posted Journals 1224');
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      workspace = await AccountingWorkspace.open(path);
      addTearDown(workspace.dispose);
      expect(
        (await workspace.journals()).single.entry.state,
        JournalEntryState.posted,
      );
      final report = await workspace.database.report(
        businessId: workspace.identity.businessId,
        from: DateTime.utc(2000),
        through: DateTime.utc(2100),
      );
      expect(report.isBalanced, isTrue);
      expect(report.assets, BigInt.from(10000));
      expect(report.totalEquity, BigInt.from(10000));
    },
  );
  for (final width in [390.0, 720.0, 900.0, 1224.0]) {
    testWidgets('manual journal editor fits width $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      installFixedPopoutHost(tester);
      final dir = Directory.systemTemp.createTempSync('audyt-journal-layout-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final workspace = await AccountingWorkspace.open(
        '${dir.path}/ledger.sqlite',
      );
      addTearDown(workspace.dispose);
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
      await loadJournalLayoutFonts();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('workspace-capture'),
          child: AudytApp(initialPath: '/accounting', workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();
      await captureUi(tester, 'Accounts ${width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('new-journal')));
      await tester.pumpAndSettle();
      await captureUi(tester, 'New Journal ${width.toInt()}');
      if (width >= 720) {
        Rect field(String key) => tester.getRect(find.byKey(ValueKey(key)));
        final account = field('journal-account-0');
        final debit = field('journal-debit-0');
        final credit = field('journal-credit-0');
        final description = field('journal-description-0');
        expect(debit.left - account.right, closeTo(10, .01));
        expect(credit.left - debit.right, closeTo(10, .01));
        expect(field('journal-account-1').width, closeTo(account.width, .01));
        expect(field('journal-debit-1').left, closeTo(debit.left, .01));
        expect(field('journal-credit-1').left, closeTo(credit.left, .01));
        final ordinaryWidth = tester
            .getSize(find.byType(AccountingOrdinaryFields).first)
            .width;
        expect(
          field('journal-date').width,
          closeTo((ordinaryWidth - 20) / 2, .01),
        );
        final amount = tester.widget<TextField>(
          find.byKey(const ValueKey('journal-debit-0')),
        );
        expect(amount.decoration!.prefix, isNull);
        expect(amount.decoration!.prefixText, isNull);
        expect(amount.textAlign, TextAlign.right);
        final memoBefore = field('journal-memo');
        final memoTitle = tester.getRect(find.text('Memo').last);
        final firstTotal = tester.getRect(find.text('Total Debit (RM)').last);
        final secondTotal = tester.getRect(find.text('Total Credit (RM)').last);
        expect(
          await paintedTextTop(tester, firstTotal),
          closeTo(await paintedTextTop(tester, memoTitle), 1),
        );
        expect(secondTotal.top - firstTotal.bottom, closeTo(16, .1));
        expect(memoBefore.height, greaterThan(70));
        await tester.enterText(
          find.byKey(const ValueKey('journal-debit-0')),
          '123456789012.34',
        );
        await tester.pumpAndSettle();
        expect(field('journal-debit-0').width, greaterThan(debit.width));
        expect(
          field('journal-debit-1').width,
          closeTo(field('journal-debit-0').width, .01),
        );
        expect(field('journal-account-0').width, closeTo(account.width, .01));
        expect(
          field('journal-description-0').width,
          lessThan(description.width),
        );
        expect(
          field('journal-debit-0').left - field('journal-account-0').right,
          closeTo(10, .01),
        );
        await enterAccountingText(
          tester,
          find.byKey(const ValueKey('journal-memo')),
          'Business account correction. This explanation wraps inside the existing Memo.\nSupporting details stay on the next line.',
        );
        await tester.pumpAndSettle();
        expect(field('journal-memo').height, closeTo(memoBefore.height, .01));
        expect(
          accountingDescriptionText(
            'Business account correction. This explanation wraps inside the existing Memo.\nSupporting details stay on the next line.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('New Journal').last);
        await tester.pumpAndSettle();
        await captureUi(tester, 'New Journal Entered ${width.toInt()}');
        await tester.enterText(
          find.byKey(const ValueKey('journal-debit-0')),
          '100.00',
        );
        await tester.enterText(
          find.byKey(const ValueKey('journal-credit-1')),
          '100.00',
        );
        await tester.pumpAndSettle();
        expect(
          field('journal-debit-0').width,
          closeTo(
            AccountingTransactionGridTokens.numericWidth(
              tester.element(find.byKey(const ValueKey('journal-debit-0'))),
              'Amount',
              ['100.00'],
              title: 'Debit (RM)',
              guidance: accountingFieldGuidance('Debit'),
            ),
            .01,
          ),
        );
        expect(field('journal-account-0').width, closeTo(account.width, .01));
        await tester.tap(find.text('New Journal').last);
        await tester.pumpAndSettle();
        await captureUi(tester, 'New Journal Balanced ${width.toInt()}');
      }
      if (Platform.environment['AUDYT_UI_CAPTURE_DIR'] != null) {
        for (final key in [
          'journal-account-0',
          'journal-account-1',
          'journal-debit-0',
          'journal-debit-1',
          'journal-credit-1',
        ]) {
          debugPrint(
            '$width $key ${tester.getRect(find.byKey(ValueKey(key)))}',
          );
        }
      }
      for (final key in [
        'journal-account-0',
        'journal-account-1',
        'journal-debit-0',
        'journal-credit-1',
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('add-journal-line')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('add-journal-line'))).right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      final accountRect = tester.getRect(
        find.byKey(const ValueKey('journal-account-0')),
      );
      final debitRect = tester.getRect(
        find.byKey(const ValueKey('journal-debit-0')),
      );
      expect(debitRect.center.dy, closeTo(accountRect.center.dy, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
