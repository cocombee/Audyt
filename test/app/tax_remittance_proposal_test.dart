import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/company_tax_agency.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/tax_remittance.dart';
import 'package:audyt/features/accounting/presentation/tax_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/tax_remittance_wiring_test.dart'
    show Fixture, setup;
import '../support/accounting_test_finders.dart';
import '../support/accounting_text_input.dart';
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

Finder field(String name) => find.byKey(ValueKey('design-field-$name'));
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    for (final r in t.allRenderObjects) {
      r.markNeedsPaint();
    }
    await t.pump();
    await captureUi(t, name);
  } finally {
    debugDisableShadows = previous;
  }
}

Future<void> host(
  WidgetTester t,
  AccountingWorkspace w,
  double width, {
  bool proposal = true,
}) async {
  t.view.physicalSize = Size(width, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await (FontLoader(
    'Inter',
  )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('workspace-capture'),
      child: MaterialApp(
        theme: AccountingTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: TaxOverviewPage(workspace: w, taxPaymentsProposal: proposal),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> allocation(
  WidgetTester t,
  Fixture f,
  String agency,
  String amount, {
  String? captureName,
}) async {
  await tap(t, find.byKey(const ValueKey('tax-allocation-add')));
  await tap(t, field('Tax Agency'));
  await tap(t, find.text(agency).last);
  final account = f.w.taxRemittanceLiabilityAccounts.single.account.displayName;
  await tap(t, field('Tax Account'));
  await tap(t, find.text(account).last);
  await t.enterText(field('Period From'), '01-09-2026');
  await t.enterText(field('Period Through'), '31-10-2026');
  await t.enterText(field('Amount'), amount);
  if (captureName != null) await capture(t, captureName);
  await tap(t, find.byKey(const ValueKey('design-review')).last);
  await tap(t, find.byKey(const ValueKey('design-review')).last);
}

Future<StoredJournalEntry> posted(Fixture f, int minor) async {
  final w = f.w;
  await w.saveJournal(
    date: DateTime.utc(2026, 9, 21),
    memo: 'Fictional external SST payment',
    lines: [
      JournalLine.debit(
        accountId: f.sales.tax,
        amount: Money.fromMinor(minor, 'MYR'),
      ),
      JournalLine.credit(
        accountId: f.bank,
        amount: Money.fromMinor(minor, 'MYR'),
      ),
    ],
  );
  final draft = (await w.journals()).singleWhere(
    (j) => j.entry.state == JournalEntryState.draft,
  );
  return w.approveJournal(
    JournalApproval(
      requestId: EntityId.random(),
      businessId: w.identity.businessId,
      journalId: draft.entry.id,
      expectedRevision: draft.metadata.revision,
      actorId: w.identity.ownerId,
      approvedAt: DateTime.now().toUtc(),
    ),
  );
}

Future<void> selectPayment(WidgetTester t) async {
  await tap(t, field('Existing Payment'));
  await tap(t, find.textContaining('available').last);
}

void main() {
  for (final width in [720.0, 1162.0]) {
    for (final link in [false, true]) {
      testWidgets(
        'allocation-only dismissal guards ${link ? 'link' : 'record'} caller at $width',
        (t) async {
          final f = await setup(), w = f.w;
          addTearDown(w.dispose);
          await host(t, w, width);
          final before = tables(w);
          final caller = ValueKey(
            link ? 'tax-payment-link' : 'tax-payment-record',
          );
          await tap(t, find.byKey(caller));
          await allocation(t, f, 'RMCD', '10.00');
          await tap(t, accountingCloseIcon());
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsOneWidget,
          );
          await capture(
            t,
            'Tax Allocation Only Close ${link ? 'Link' : 'Record'} ${width.toInt()}',
          );
          await tap(t, find.text('Keep Editing'));
          expect(find.text('RM 10.00'), findsOneWidget);
          await tap(t, find.byKey(const ValueKey('tax-allocation-edit-0')));
          await t.enterText(field('Amount'), '20.00');
          await tap(t, find.byKey(const ValueKey('design-review')).last);
          await tap(t, find.byKey(const ValueKey('design-review')).last);
          await tap(t, accountingCloseIcon());
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsOneWidget,
          );
          await tap(t, find.text('Keep Editing'));
          expect(find.text('RM 20.00'), findsOneWidget);
          await capture(
            t,
            'Tax Allocation Kept Editing ${link ? 'Link' : 'Record'} ${width.toInt()}',
          );
          await tap(t, accountingCloseIcon());
          await tap(t, find.byKey(const ValueKey('design-discard-changes')));
          expect(tables(w), before);
          await tap(t, find.byKey(caller));
          expect(find.byKey(const ValueKey('tax-allocation-0')), findsNothing);
          await allocation(t, f, 'RMCD', '10.00');
          await tap(t, find.byKey(const ValueKey('tax-allocation-remove-0')));
          await tap(t, accountingCloseIcon());
          expect(
            find.byKey(const ValueKey('design-discard-changes')),
            findsNothing,
          );
          expect(find.byKey(caller), findsOneWidget);
          expect(tables(w), before);
        },
      );
    }
  }
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual record/multi-agency review/save/view/correction/cancel/restart at $width',
      (t) async {
        final dir = Directory.systemTemp.createTempSync(
          'audyt-tax-payment-ui-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/books.sqlite',
            f = await setup(path: path),
            w = f.w;
        addTearDown(w.dispose);
        w.saveTaxAgency(
          CompanyTaxAgency(
            id: EntityId.random(),
            name: 'RMCD Second Registration',
            registrationNumber: 'Fictional B',
          ),
        );
        await host(t, w, width);
        final before = (await w.journals()).length;
        await capture(t, 'Tax Payments Overview ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('tax-payment-record')));
        await tap(t, field('Bank Account'));
        await tap(t, find.text('Fictional Bank').last);
        await t.enterText(field('Payment Date'), '20-09-2026');
        await t.enterText(field('Reference'), 'FICTIONAL-SST-PAYMENT');
        await enterAccountingText(
          t,
          field('Memo'),
          'Fictional payment already made.',
        );
        await capture(t, 'Tax Payment Record ${width.toInt()}');
        await allocation(
          t,
          f,
          'RMCD',
          '3.00',
          captureName: 'Tax Payment Allocation ${width.toInt()}',
        );
        await allocation(t, f, 'RMCD Second Registration', '2.00');
        await tap(t, find.byKey(const ValueKey('tax-allocation-edit-0')));
        expect(find.text('Edit Tax Allocation'), findsOneWidget);
        expect(
          t.widget<TextFormField>(field('Amount')).controller!.text,
          '3.00',
        );
        await t.enterText(field('Amount'), '7.00');
        await tap(t, accountingCloseIcon().last);
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(t, find.byKey(const ValueKey('design-discard-changes')));
        expect(find.text('RM 3.00'), findsOneWidget);
        expect(find.text('RM 7.00'), findsNothing);
        await tap(t, find.byKey(const ValueKey('tax-allocation-remove-1')));
        expect(find.byKey(const ValueKey('tax-allocation-1')), findsNothing);
        expect((await w.journals()).length, before);
        await allocation(t, f, 'RMCD Second Registration', '2.00');
        await capture(t, 'Tax Payment Allocated ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(find.byKey(const ValueKey('tax-allocation-add')), findsNothing);
        expect(find.text('RMCD Second Registration'), findsOneWidget);
        await capture(t, 'Tax Payment Review ${width.toInt()}');
        expect((await w.journals()).length, before);
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect((await w.journals()).length, before + 1);
        final saved = w.taxRemittances().single;
        expect(saved.allocations, hasLength(2));
        expect(saved.total.minorUnits, 500);
        await capture(t, 'Tax Payment Saved List ${width.toInt()}');
        await tap(
          t,
          find.byKey(ValueKey('tax-payment-view-${saved.id.value}')),
        );
        expect(find.text('Recorded In Books'), findsOneWidget);
        await capture(t, 'Tax Payment View ${width.toInt()}');
        await tap(t, accountingCloseIcon());
        await tap(
          t,
          find.byKey(ValueKey('tax-payment-correct-${saved.id.value}')),
        );
        await t.enterText(field('Correction Date'), '22-09-2026');
        await enterAccountingText(
          t,
          field('Reason'),
          'Fictional payment correction.',
        );
        await capture(t, 'Tax Payment Reversal ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        await capture(t, 'Tax Payment Reversal Review ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(t, find.byKey(const ValueKey('design-discard-changes')));
        expect(w.taxRemittances(), hasLength(1));
        await tap(
          t,
          find.byKey(ValueKey('tax-payment-correct-${saved.id.value}')),
        );
        await t.enterText(field('Correction Date'), '22-09-2026');
        await enterAccountingText(
          t,
          field('Reason'),
          'Fictional payment correction.',
        );
        await tap(t, find.byKey(const ValueKey('design-review')));
        t.view.physicalSize = Size(width == 720 ? 900 : 720, 1400);
        await t.pumpAndSettle();
        expect(find.text('Fictional payment correction.'), findsOneWidget);
        t.view.physicalSize = Size(width, 1400);
        await t.pumpAndSettle();
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(w.taxRemittances(), isEmpty);
        expect((await w.journals()).length, before + 2);
        expect(
          w.taxRemittances(includeCorrected: true).single.toJson(),
          saved.toJson(),
        );
        final r = await w.taxActivity(
          from: DateTime.utc(2026, 9),
          through: DateTime.utc(2026, 10, 31),
        );
        expect(r.remittedTax, BigInt.zero);
        expect(r.ledger.periodProfit, BigInt.from(10000));
        await tap(
          t,
          find.byKey(ValueKey('tax-account-view-${f.sales.tax.value}')),
        );
        await capture(t, 'Tax Payment Ledger Trace ${width.toInt()}');
        expect(find.text('Unattributed Movement'), findsWidgets);
        await t.pumpWidget(const SizedBox.shrink());
        w.dispose();
        final reopened = await AccountingWorkspace.open(path);
        addTearDown(reopened.dispose);
        expect(
          reopened.taxRemittances(includeCorrected: true).single.toJson(),
          saved.toJson(),
        );
        expect(
          reopened.database
              .readTaxRemittanceCorrection(
                reopened.identity.businessId,
                saved.id,
              )!
              .kind,
          TaxRemittanceCorrectionKind.reversal,
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'actual link partial payment/unlink preserve journal and refresh remaining at $width',
      (t) async {
        final f = await setup();
        addTearDown(f.w.dispose);
        final source = await posted(f, 500), w = f.w;
        await host(t, w, width);
        final before = (await w.journals()).length;
        await tap(t, find.byKey(const ValueKey('tax-payment-link')));
        await selectPayment(t);
        await t.enterText(field('Reference'), 'FICTIONAL-LINK');
        await allocation(t, f, 'RMCD', '3.00');
        await capture(t, 'Tax Payment Link ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(
          find.text('Link attribution only; no new bank movement.'),
          findsOneWidget,
        );
        await capture(t, 'Tax Payment Link Review ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect((await w.journals()).length, before);
        final saved = w.taxRemittances().single;
        expect(saved.journalId, source.entry.id);
        expect(
          w
              .taxRemittanceCandidates('fictional-remittance-bank')
              .single
              .available
              .minorUnits,
          200,
        );
        await tap(
          t,
          find.byKey(ValueKey('tax-payment-correct-${saved.id.value}')),
        );
        await t.enterText(field('Correction Date'), '22-09-2026');
        await enterAccountingText(
          t,
          field('Reason'),
          'Fictional attribution correction.',
        );
        await capture(t, 'Tax Payment Unlink ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        await capture(t, 'Tax Payment Unlink Review ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect((await w.journals()).length, before);
        expect(
          w
              .taxRemittanceCandidates('fictional-remittance-bank')
              .single
              .available
              .minorUnits,
          500,
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'concurrent allocation fails Save without a new posting or lost reviewed facts at $width',
      (t) async {
        final f = await setup();
        addTearDown(f.w.dispose);
        final source = await posted(f, 500), w = f.w;
        await host(t, w, width);
        await tap(t, find.byKey(const ValueKey('tax-payment-link')));
        await selectPayment(t);
        await t.enterText(field('Reference'), 'FICTIONAL-CONFLICT');
        await allocation(t, f, 'RMCD', '3.00');
        await tap(t, find.byKey(const ValueKey('design-review')));
        w.linkTaxRemittance(
          requestId: EntityId.random(),
          reviewedJournal: source,
          paymentAccountId: 'fictional-remittance-bank',
          allocations: [f.allocation(500)],
          reference: 'FICTIONAL-OTHER-ALLOCATION',
          recordedAt: DateTime.now().toUtc(),
        );
        final before = tables(w);
        await tap(t, find.byKey(const ValueKey('design-review')));
        expect(find.textContaining('Could not save:'), findsOneWidget);
        expect(
          find.textContaining('already allocated or exceeds'),
          findsOneWidget,
        );
        expect(find.text('FICTIONAL-CONFLICT'), findsOneWidget);
        expect(tables(w), before);
        await capture(t, 'Tax Payment Stale Save ${width.toInt()}');
        await tap(t, find.byKey(const ValueKey('design-close')));
        expect(
          find.byKey(const ValueKey('design-discard-changes')),
          findsOneWidget,
        );
        await tap(t, find.byKey(const ValueKey('design-discard-changes')));
        expect(tables(w), before);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'payment View preserves original evidence and data-only restore exposes unavailable bytes',
    (t) async {
      final f = await setup(), w = f.w;
      addTearDown(w.dispose);
      final picture = img.Image(width: 4, height: 4)
        ..setPixelRgba(1, 1, 255, 0, 0, 255);
      final original = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: 'fictional-tax-proof',
          batchId: 'fictional-batch',
          filename: 'Fictional Bank Proof.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList(img.encodePng(picture)),
        ),
      );
      final payment = w.recordTaxRemittance(
        requestId: EntityId.random(),
        paymentAccountId: 'fictional-remittance-bank',
        allocations: [f.allocation(200)],
        paidOn: DateTime.utc(2026, 9, 20),
        reference: 'FICTIONAL-EVIDENCE',
        recordedAt: DateTime.now().toUtc(),
        attachments: [original],
      );
      await host(t, w, 720);
      await tap(
        t,
        find.byKey(ValueKey('tax-payment-view-${payment.id.value}')),
      );
      expect(find.text(original.filename), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      await capture(t, 'Tax Payment Evidence 720');
      final view = find.byKey(
        ValueKey('tax-payment-evidence-${original.originalId}'),
      );
      await t.ensureVisible(view);
      await t.runAsync(() async {
        await t.tap(view);
        await t.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        w.taxRemittances().single.attachments.single.originalBytes,
        original.originalBytes,
      );
      final archive = w.database.exportDataArchive(
        w.identity.businessId,
        DateTime.now().toUtc(),
      );
      await t.pumpWidget(const SizedBox.shrink());
      final restored = await AccountingWorkspace.emptyRestore(
        ':memory:',
        archive,
      );
      addTearDown(restored.dispose);
      final recovered = restored.taxRemittances().single;
      expect(recovered.attachments.single.originalBytes, isEmpty);
      expect(
        recovered.attachments.single.originalSha256,
        original.originalSha256,
      );
      await host(t, restored, 720);
      await tap(
        t,
        find.byKey(ValueKey('tax-payment-view-${payment.id.value}')),
      );
      expect(find.textContaining('Reconnect'), findsWidgets);
      await capture(t, 'Tax Payment Recovered Evidence 720');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'empty eligible choices and missing allocation stay explicit with no write',
    (t) async {
      final f = await setup();
      addTearDown(f.w.dispose);
      await host(t, f.w, 720);
      final before = tables(f.w);
      await tap(t, find.byKey(const ValueKey('tax-payment-link')));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is AccountingFieldHelp &&
              w.label == 'Tax Allocations' &&
              w.message.contains('No eligible unallocated payments.'),
        ),
        findsOneWidget,
      );
      await tap(t, find.byKey(const ValueKey('design-close')));
      expect(
        find.byKey(const ValueKey('design-discard-changes')),
        findsNothing,
      );
      await tap(t, find.byKey(const ValueKey('tax-payment-record')));
      await tap(t, field('Bank Account'));
      await tap(t, find.text('Fictional Bank').last);
      await t.enterText(field('Payment Date'), '20-09-2026');
      await t.enterText(field('Reference'), 'FICTIONAL-NO-ALLOCATION');
      await tap(t, find.byKey(const ValueKey('design-review')));
      expect(
        find.textContaining('Add at least one tax allocation.'),
        findsOneWidget,
      );
      expect(tables(f.w), before);
      await capture(t, 'Tax Payment Missing Allocation 720');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'proposal default off keeps canonical page and scoped extension absent',
    (t) async {
      final f = await setup();
      addTearDown(f.w.dispose);
      await host(t, f.w, 720, proposal: false);
      expect(find.byKey(const ValueKey('tax-payment-record')), findsNothing);
      expect(find.byKey(const ValueKey('tax-payment-link')), findsNothing);
      expect(find.text('Tax Payments'), findsNothing);
      expect(
        find.text('Recorded Tax Payments — Net of Reversals'),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
}
