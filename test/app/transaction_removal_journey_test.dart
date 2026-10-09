import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/transaction_removal.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/transaction_removal_controls.dart';
import 'package:audyt/features/accounting/presentation/record_expense_page.dart';
import 'package:audyt/features/purchases/domain/claim.dart';
import 'package:audyt/features/purchases/presentation/payment_vouchers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../features/accounting/data/transaction_removal_test.dart'
    show fixture, visible;
import '../features/accounting/data/bill_posting_test.dart' show payableAccount;
import '../features/accounting/data/credit_posting_boundary_test.dart'
    show rawTables;
import '../support/accounting_test_finders.dart';
import 'journal_workspace_integration_test.dart' show captureUi;

String pagePath(TransactionRecordKind kind) => switch (kind) {
  TransactionRecordKind.claim => '/claims',
  TransactionRecordKind.paymentVoucher => '/payment-vouchers',
  TransactionRecordKind.bill => '/expenses-vendors',
  _ => '/sales-customers',
};
String? pageTab(TransactionRecordKind kind) => switch (kind) {
  TransactionRecordKind.bill => 'Bills',
  TransactionRecordKind.quotation => 'Quotations',
  TransactionRecordKind.invoiceCredit => 'Credit Notes',
  _ => null,
};

Future<void> openPage(
  WidgetTester tester,
  AccountingWorkspace w,
  TransactionRecordKind kind,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: AudytApp(
        workspace: w,
        initialPath: pagePath(kind),
        showInitialSetup: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final tab = pageTab(kind);
  if (tab != null) {
    await tester.tap(find.text(tab).first);
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [720.0, 1162.0]) {
    testWidgets('removed legacy credit retains unknown tax facts at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 809);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final w = await createDemoWorkspace(
        asOf: DateTime(2026, 10, 9),
        includeRowReview: true,
      );
      addTearDown(w.dispose);
      final credit = w.creditDrafts().first;
      final invoice = w
          .postedInvoices()
          .singleWhere((i) => i.sourceDraft.id == credit.invoiceId)
          .sourceDraft;
      expect(invoice.taxMode, isEmpty);
      expect(invoice.lines.single.taxRatePercent, isNull);
      final originalAttachments = credit.attachments
          .map((a) => a.toJson())
          .toList();
      final originalInvoice = invoice.draftSnapshot();
      final journalIds = (await w.journals()).map((j) => j.entry.id).toList();
      w.setTransactionRemoved(
        reviewed: w.reviewTransactionRemoval(
          TransactionRecordKind.invoiceCredit,
          credit.id.value,
        ),
        removed: true,
        changedAt: DateTime.now().toUtc(),
      );
      await openPage(tester, w, TransactionRecordKind.invoiceCredit);
      await tap(
        tester,
        find.byKey(const ValueKey('removed-invoiceCredit-open')),
      );
      await tap(
        tester,
        find.byKey(ValueKey('removed-view-${credit.id.value}')),
      );
      expect(
        find.text('Legacy / Review Required · Not Retained'),
        findsOneWidget,
      );
      expect(find.textContaining('null%'), findsNothing);
      expect(find.text('RM 100.00'), findsWidgets);
      expect(find.byType(AccountingInformationRows), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Save Draft'), findsNothing);
      final retained = w
          .creditDrafts(includeRemoved: true)
          .singleWhere((d) => d.id == credit.id);
      expect(retained.invoiceId, credit.invoiceId);
      expect(retained.revision, credit.revision);
      expect(retained.savedAt, credit.savedAt);
      expect(retained.reason, credit.reason);
      expect(retained.date, credit.date);
      expect(retained.lineCredits, credit.lineCredits);
      expect(
        retained.attachments.map((a) => a.toJson()).toList(),
        originalAttachments,
      );
      expect(
        w
            .postedInvoices()
            .singleWhere((i) => i.sourceDraft.id == credit.invoiceId)
            .sourceDraft
            .draftSnapshot(),
        originalInvoice,
      );
      expect((await w.journals()).map((j) => j.entry.id).toList(), journalIds);
      await captureUi(tester, 'Removed Credit Missing Tax ${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [720.0, 1224.0]) {
    for (final state in [
      'claim returned',
      'claim declined',
      'quotation shared',
      'quotation declined',
      'quotation closed',
    ]) {
      testWidgets(
        '$state can be removed and restored without losing history at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          final kind = state.startsWith('claim')
              ? TransactionRecordKind.claim
              : TransactionRecordKind.quotation;
          final f = await fixture(kind, pending: true);
          if (kind == TransactionRecordKind.claim) {
            final id = EntityId.parse(f.id);
            if (state.endsWith('returned')) {
              f.w.claims.returnForCorrection(id);
            } else {
              f.w.claims.decline(id);
            }
          } else {
            final revision = f.w.changeQuotationState(
              EntityId.parse(f.id),
              expectedRevision: 1,
              action: QuotationAction.shared,
              changedAt: DateTime.utc(2026, 9, 2),
            );
            if (!state.endsWith('shared')) {
              f.w.changeQuotationState(
                EntityId.parse(f.id),
                expectedRevision: revision,
                action: state.endsWith('declined')
                    ? QuotationAction.declined
                    : QuotationAction.closed,
                changedAt: DateTime.utc(2026, 9, 3),
              );
            }
          }
          final raw = sqlite3.open(f.path);
          addTearDown(raw.dispose);
          final original = rawTables(raw);
          final reviewed = f.w.reviewTransactionRemoval(kind, f.id);
          expect(reviewed.canRemove, isTrue);
          await openPage(tester, f.w, kind);
          final remove = find.byKey(ValueKey('remove-${kind.name}-${f.id}'));
          expect(tester.widget<IconButton>(remove).onPressed, isNotNull);
          await tap(tester, remove);
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-cancel-removal')),
          );
          expect(rawTables(raw), original);
          await tap(tester, remove);
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-confirm-removal')),
          );
          expect(visible(f.w, kind, f.id), isFalse);
          expect(
            f.w.removedTransactionPage(kind).records.single.status,
            reviewed.status,
          );
          await tap(tester, find.byKey(ValueKey('removed-${kind.name}-open')));
          final restore = find.byKey(ValueKey('removed-restore-${f.id}'));
          expect(tester.widget<IconButton>(restore).onPressed, isNotNull);
          await tap(tester, restore);
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-confirm-removal')),
          );
          expect(visible(f.w, kind, f.id), isTrue);
          expect(
            f.w.reviewTransactionRemoval(kind, f.id).status,
            reviewed.status,
          );
          final restored = rawTables(raw);
          for (final table in original.keys.where(
            (t) => !{
              'transaction_record_removals',
              'ledger_audit',
              'sqlite_sequence',
            }.contains(t),
          )) {
            expect(restored[table], original[table], reason: '$state: $table');
          }
          final reopened = await AccountingWorkspace.open(f.path);
          addTearDown(reopened.dispose);
          expect(visible(reopened, kind, f.id), isTrue);
          expect(
            reopened.reviewTransactionRemoval(kind, f.id).status,
            reviewed.status,
          );
          expect(reopened.removedTransactionPage(kind).total, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final kind in [
    TransactionRecordKind.claim,
    TransactionRecordKind.paymentVoucher,
  ]) {
    testWidgets('${kind.name} draft has an enabled real removal control', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      final f = await fixture(kind);
      await openPage(tester, f.w, kind);
      await captureUi(tester, 'Removal ${removalFamilyLabel(kind)} Active 800');
      final remove = find.byKey(ValueKey('remove-${kind.name}-${f.id}'));
      expect(tester.widget<IconButton>(remove).onPressed, isNotNull);
      await tap(tester, remove);
      await tap(
        tester,
        find.byKey(const ValueKey('transaction-confirm-removal')),
      );
      expect(visible(f.w, kind, f.id), isFalse);
      expect(f.w.removedTransactionPage(kind).records.single.status, 'Draft');
      await captureUi(
        tester,
        'Removal ${removalFamilyLabel(kind)} Removed 800',
      );
    });
  }

  testWidgets(
    'Removed Claims uses five bounded rows, clamps after restoring the final page, and hides controls below six',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await fixture(TransactionRecordKind.claim);
      final original = f.w.claims.all.single;
      for (var i = 1; i < 6; i++) {
        f.w.claims.saveDraft(
          Claim.fromJson({
            ...original.toJson(),
            'id': EntityId.random().value,
            'vendorName': 'Paging Claim $i',
          }),
        );
      }
      for (final c in f.w.claims.all.toList()) {
        f.w.setTransactionRemoved(
          reviewed: f.w.reviewTransactionRemoval(
            TransactionRecordKind.claim,
            c.id.value,
          ),
          removed: true,
          changedAt: DateTime.now().toUtc(),
        );
      }
      await openPage(tester, f.w, TransactionRecordKind.claim);
      await tap(tester, find.byKey(const ValueKey('removed-claim-open')));
      expect(find.byType(AccountingRecordRow), findsNWidgets(5));
      expect(
        find.byKey(const ValueKey('removed-claim-page-size')),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const ValueKey('removed-claim-page-next')));
      expect(find.byType(AccountingRecordRow), findsOneWidget);
      final last = f.w
          .removedTransactionPage(TransactionRecordKind.claim, offset: 5)
          .records
          .single;
      await tap(
        tester,
        find.byKey(ValueKey('removed-restore-${last.recordId}')),
      );
      await tap(
        tester,
        find.byKey(const ValueKey('transaction-confirm-removal')),
      );
      expect(
        find.byType(AccountingRecordRow),
        findsNWidgets(6),
      ); // Five removed rows plus the restored active row behind the modal.
      expect(
        find.byKey(const ValueKey('removed-claim-page-size')),
        findsNothing,
      );
      expect(f.w.removedTransactionPage(TransactionRecordKind.claim).total, 5);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [720.0, 1224.0]) {
    for (final kind in TransactionRecordKind.values) {
      testWidgets(
        '${kind.name} actual route remove/cancel/view/restore/restart at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await (FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
              .load();
          final f = await fixture(kind, pending: true);
          var w = f.w;
          final raw = sqlite3.open(f.path);
          addTearDown(raw.dispose);
          final original = rawTables(raw);
          final originalReview = w.reviewTransactionRemoval(kind, f.id);
          await openPage(tester, w, kind);
          final remove = find.byKey(ValueKey('remove-${kind.name}-${f.id}'));
          expect(tester.widget<IconButton>(remove).onPressed, isNotNull);
          await captureUi(
            tester,
            'Removal ${removalFamilyLabel(kind)} Active ${width.toInt()}',
          );
          await tap(tester, remove);
          if (kind == TransactionRecordKind.bill) {
            await captureUi(
              tester,
              'Removal Bill Confirmation ${width.toInt()}',
            );
          }
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-cancel-removal')),
          );
          expect(rawTables(raw), original);
          await tap(tester, remove);
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-confirm-removal')),
          );
          expect(visible(w, kind, f.id), isFalse);
          final removed = rawTables(raw);
          for (final table in original.keys.where(
            (t) => !{
              'transaction_record_removals',
              'ledger_audit',
              'sqlite_sequence',
            }.contains(t),
          )) {
            expect(removed[table], original[table], reason: table);
          }
          final removedOpen = find.byKey(ValueKey('removed-${kind.name}-open'));
          await tap(tester, removedOpen);
          expect(
            find.text('Removed ${removalFamilyLabel(kind, plural: true)}'),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('removed-${kind.name}-page-size')),
            findsNothing,
          );
          await captureUi(
            tester,
            'Removal ${removalFamilyLabel(kind)} Retained ${width.toInt()}',
          );
          await tap(tester, find.byKey(ValueKey('removed-view-${f.id}')));
          if (kind == TransactionRecordKind.claim) {
            expect(
              tester
                  .widget<RecordExpensePage>(find.byType(RecordExpensePage))
                  .readOnly,
              isTrue,
            );
          } else if (kind == TransactionRecordKind.paymentVoucher) {
            expect(
              tester
                  .widget<PaymentVoucherEditorDialog>(
                    find.byType(PaymentVoucherEditorDialog),
                  )
                  .readOnly,
              isTrue,
            );
          } else {
            expect(find.byType(AccountingInformationRows), findsWidgets);
          }
          expect(find.widgetWithText(TextButton, 'Save Draft'), findsNothing);
          expect(find.widgetWithText(TextButton, 'Submit'), findsNothing);
          expect(rawTables(raw), removed);
          await captureUi(
            tester,
            'Removal ${removalFamilyLabel(kind)} Read Only ${width.toInt()}',
          );
          await tap(tester, accountingCloseIcon().last);
          await tap(tester, find.byKey(ValueKey('removed-restore-${f.id}')));
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-cancel-removal')),
          );
          expect(rawTables(raw), removed);
          await tap(tester, find.byKey(ValueKey('removed-restore-${f.id}')));
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-confirm-removal')),
          );
          expect(visible(w, kind, f.id), isTrue);
          expect(
            w.reviewTransactionRemoval(kind, f.id).status,
            originalReview.status,
          );
          expect(
            w.reviewTransactionRemoval(kind, f.id).amount,
            originalReview.amount,
          );
          await tap(tester, accountingCloseIcon().last);
          await captureUi(
            tester,
            'Removal ${removalFamilyLabel(kind)} Restored ${width.toInt()}',
          );
          await tap(tester, remove);
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-confirm-removal')),
          );
          final archive = w.database.exportDataArchive(
            w.identity.businessId,
            DateTime.now().toUtc(),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          w.dispose();
          w = await AccountingWorkspace.open(f.path);
          await openPage(tester, w, kind);
          expect(visible(w, kind, f.id), isFalse);
          await tap(tester, removedOpen);
          expect(
            find.byKey(ValueKey('removed-restore-${f.id}')),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          w.dispose();
          w = await AccountingWorkspace.emptyRestore(
            '${f.path}.recovered',
            archive,
          );
          addTearDown(() => w.dispose());
          await openPage(tester, w, kind);
          await tap(tester, removedOpen);
          await tap(tester, find.byKey(ValueKey('removed-restore-${f.id}')));
          await tap(
            tester,
            find.byKey(const ValueKey('transaction-confirm-removal')),
          );
          expect(visible(w, kind, f.id), isTrue);
          expect(
            w.reviewTransactionRemoval(kind, f.id).amount,
            originalReview.amount,
          );
          expect(
            w.reviewTransactionRemoval(kind, f.id).status,
            originalReview.status,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'open Remove confirmation rechecks concurrent Bill posting without deleting its history',
    (tester) async {
      tester.view.physicalSize = const Size(1224, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await fixture(TransactionRecordKind.bill);
      final payable = await payableAccount(f.w);
      await openPage(tester, f.w, TransactionRecordKind.bill);
      await tap(tester, find.byKey(ValueKey('remove-bill-${f.id}')));
      f.w.postBill(
        requestId: EntityId.random(),
        billId: EntityId.parse(f.id),
        expectedRevision: 1,
        payableAccountId: payable.account.id,
        approvedAt: DateTime.utc(2026, 9, 29),
      );
      final raw = sqlite3.open(f.path);
      addTearDown(raw.dispose);
      final posted = rawTables(raw);
      await tap(
        tester,
        find.byKey(const ValueKey('transaction-confirm-removal')),
      );
      expect(find.text('Record Action Failed'), findsOneWidget);
      expect(rawTables(raw), posted);
      expect(f.w.removedTransactionPage(TransactionRecordKind.bill).total, 0);
      await tap(tester, accountingCloseIcon().last);
      final remove = find.byKey(ValueKey('remove-bill-${f.id}'));
      expect(tester.widget<IconButton>(remove).onPressed, isNull);
    },
  );
}
