import '../support/accounting_text_input.dart';

import 'dart:io';

import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/app.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/naming_setup.dart' show namingSettingsChannel;
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/presentation/pay_bills_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/bill_settlement_test.dart'
    show settlementFixture, allocation;
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, (call) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(namingSettingsChannel, null),
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual Pay Bills route cancels, validates, settles, rejects stale review and survives restore at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = Directory.systemTemp.createTempSync('audyt-pay-bills-ui-');
        addTearDown(() => root.deleteSync(recursive: true));
        final now = DateTime.now().toUtc();
        final (source, ids, bank, payable) = await settlementFixture(
          '${root.path}/source.sqlite',
          createdAt: now.subtract(const Duration(days: 2)),
          approvedAt: now.subtract(const Duration(days: 1)),
        );
        final initial = tables(source);
        final archive = source.database.exportDataArchive(
          source.identity.businessId,
          now,
        );
        source.dispose();
        final sourceHash = sha256
            .convert(File('${root.path}/source.sqlite').readAsBytesSync())
            .toString();
        final w = await AccountingWorkspace.emptyRestore(
          '${root.path}/restored.sqlite',
          archive,
        );
        addTearDown(w.dispose);
        expect(tables(w), initial);
        // Data-only restore changes evidence availability, not purchase facts.
        // Payments must preserve this recovered source snapshot unchanged.
        final originalSources = [
          for (final id in ids)
            w.database.readBillDraft(w.identity.businessId, id)!.toJson(),
        ];
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: AudytApp(workspace: w, initialPath: '/expenses-vendors'),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        Future<void> text(String label, String value) async {
          final f = find.byKey(ValueKey('design-field-$label'));
          await tester.ensureVisible(f);
          await enterAccountingText(tester, f, value);
          await tester.pumpAndSettle();
        }

        final tabs = tester.widget<AccountingTabs>(
          find.byKey(const ValueKey('area-tabs-expenses-vendors')),
        );
        await tap(
          find.byKey(
            ValueKey(
              'preview-tab-expenses-vendors-${tabs.labels.indexOf('Pay Bills')}',
            ),
          ),
        );
        expect(find.byType(PayBillsPage), findsOneWidget);
        expect(find.byType(AccountingRecordRow), findsNWidgets(2));
        await captureUi(tester, 'Pay Bills Records ${width.toInt()}');
        var before = tables(w);
        await tap(find.byKey(ValueKey('view-pay-bill-${ids[0]}')));
        expect(find.byType(AccountingInformationRows), findsWidgets);
        await tap(accountingCloseIcon().last);
        expect(tables(w), before);
        for (final id in ids) {
          await tap(find.byKey(ValueKey('select-pay-bill-$id')));
        }
        await tap(find.byKey(const ValueKey('pay-selected-bills')));
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        await text('Reference', 'Cancelled fictional payment');
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-discard-changes')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tables(w), before);
        await tap(find.byKey(const ValueKey('pay-selected-bills')));
        await text('Reference', 'Fictional first UI payment');
        await text('Date', '15-09-2026');
        expect(find.text('Amount Paid For Bill 1 (RM)'), findsOneWidget);
        await text('Amount Paid for Bill 1', '999999');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(
          find.textContaining('Each payment must be positive'),
          findsOneWidget,
        );
        expect(tables(w), before);
        await text('Amount Paid for Bill 1', '60');
        await text('Amount Paid for Bill 2', '40');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(AccountingInformationRows), findsWidgets);
        await captureUi(tester, 'Pay Bills Review ${width.toInt()}');
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(
          w.database.billOutstanding(w.identity.businessId, ids[0]),
          Money.fromMinor(9120, 'MYR'),
        );
        expect(
          w.database.billOutstanding(w.identity.businessId, ids[1]),
          Money.fromMinor(11120, 'MYR'),
        );
        var report = await w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(report.periodProfit, BigInt.from(-30240));
        expect(report.assets, BigInt.from(-10000));
        expect(report.liabilities, BigInt.from(20240));
        expect(report.isBalanced, isTrue);

        await tap(find.byKey(ValueKey('select-pay-bill-${ids[0]}')));
        await tap(find.byKey(const ValueKey('pay-selected-bills')));
        await text('Reference', 'Stale fictional payment');
        await tap(find.byKey(const ValueKey('design-review')));
        final competing = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        competing.settleRecognizedBills(
          requestId: EntityId.random(),
          allocations: [allocation(ids[0], 9120, 120)],
          paymentAccountId: 'fictional-bank',
          paymentReference: 'Fictional concurrent payment',
          paidOn: DateTime.utc(2026, 9, 16),
          approvedAt: DateTime.now().toUtc(),
        );
        competing.dispose();
        before = tables(w);
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsOneWidget);
        expect(find.textContaining('Could not save:'), findsOneWidget);
        expect(tables(w), before);
        await tap(accountingCloseIcon().last);
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(find.byKey(const ValueKey('design-discard-changes')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tables(w), before);
        await tap(find.byKey(const ValueKey('clear-pay-bill-selection')));
        for (final id in ids) {
          await tap(find.byKey(ValueKey('select-pay-bill-$id')));
        }
        await tap(find.byKey(const ValueKey('pay-selected-bills')));
        await text('Reference', 'Fictional final UI payment');
        await text('Date', '28-09-2026');
        await tap(find.byKey(const ValueKey('design-review')));
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        for (final id in ids) {
          expect(
            w.database.billOutstanding(w.identity.businessId, id),
            Money.zero('MYR'),
          );
        }
        report = await w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(report.periodProfit, BigInt.from(-30240));
        expect(report.assets, BigInt.from(-30240));
        expect(report.liabilities, BigInt.zero);
        expect(report.isBalanced, isTrue);
        expect(
          find.byKey(const ValueKey('clear-pay-bill-filter')),
          findsNothing,
        );
        expect(find.text('Paid'), findsNWidgets(2));
        before = tables(w);
        await tap(find.byKey(ValueKey('pay-bill-history-${ids[0]}')));
        final payments = w.database.billSettlementsForBill(
          w.identity.businessId,
          ids[0],
        );
        expect(payments, hasLength(3));
        await tap(
          find.byKey(ValueKey('view-bill-payment-${payments.first.id}')),
        );
        expect(find.text('View Bill Payment'), findsOneWidget);
        await captureUi(tester, 'Bill Payment Saved Facts ${width.toInt()}');
        await tap(accountingCloseIcon().last);
        await tap(
          find.byKey(ValueKey('reverse-bill-payment-${payments.first.id}')),
        );
        await tap(find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsNothing,
        );
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(tables(w), before);
        await tap(
          find.byKey(ValueKey('reverse-bill-payment-${payments.first.id}')),
        );
        await text('Reason', 'Duplicate payment batch');
        await tap(find.byKey(const ValueKey('design-review')));
        await captureUi(
          tester,
          'Bill Payment Reversal Review ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('design-review')));
        expect(find.byType(FrontendFormDialog), findsNothing);
        expect(
          w.database
              .readBillPaymentReversal(w.identity.businessId, payments.first.id)
              ?.reason,
          'Duplicate payment batch',
        );
        expect(find.text('Reversed'), findsOneWidget);
        await captureUi(
          tester,
          'Bill Payment Reversed History ${width.toInt()}',
        );
        await tap(
          find.byKey(ValueKey('view-bill-payment-${payments.first.id}')),
        );
        expect(find.text('Duplicate payment batch'), findsOneWidget);
        await tap(accountingCloseIcon().last);
        await tap(accountingCloseIcon().last);
        before = tables(w);
        expect(
          w.database.billOutstanding(w.identity.businessId, ids[0]),
          Money.fromMinor(9000, 'MYR'),
        );
        expect(
          w.database.billOutstanding(w.identity.businessId, ids[1]),
          Money.fromMinor(11120, 'MYR'),
        );
        report = await w.report(
          from: DateTime.utc(2026),
          through: DateTime.utc(2026, 12, 31),
        );
        expect(report.isBalanced, isTrue);
        await captureUi(tester, 'Pay Bills Paid Records ${width.toInt()}');
        expect([
          for (final id in ids)
            w.database.readBillDraft(w.identity.businessId, id)!.toJson(),
        ], originalSources);
        final recovery = w.database.exportDataArchive(
          w.identity.businessId,
          DateTime.now(),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        w.dispose();
        final reopened = await AccountingWorkspace.open(
          '${root.path}/restored.sqlite',
        );
        expect(tables(reopened), before);
        reopened.dispose();
        final recovered = await AccountingWorkspace.emptyRestore(
          '${root.path}/again.sqlite',
          recovery,
        );
        expect(tables(recovered), before);
        recovered.dispose();
        expect(
          sha256
              .convert(File('${root.path}/source.sqlite').readAsBytesSync())
              .toString(),
          sourceHash,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
