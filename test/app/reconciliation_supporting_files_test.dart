import '../support/historical_sqlite_fixture.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_attachment_picker.dart';
import 'package:audyt/features/accounting/presentation/statement_reconciliation_dialog.dart';
import 'package:audyt/features/accounting/presentation/reconciliation_history_dialog.dart';

import 'claim_receipts_proposal_test.dart' show prepare, capture;
import '../support/attachment_preview_pump.dart';

import 'package:audyt/features/accounting/domain/statement_reconciliation.dart';

import 'reconciliation_list_scope_test.dart' show fixture, keyed, tap;

Uint8List pixels() => Uint8List.fromList(
  image.encodePng(
    image.Image(width: 64, height: 32)..clear(image.ColorRgb8(30, 170, 130)),
  ),
);
ReceiptAttachment file(String id) => ReceiptAttachment.queued(
  ReceiptAttachmentInput(
    originalId: id,
    batchId: 'fictional',
    filename: 'Fictional $id.png',
    mimeType: 'image/png',
    bytes: pixels(),
  ),
).withStatus(AttachmentProcessingStatus.ready);
void save(
  AccountingWorkspace w,
  EntityId statement,
  List<ReceiptAttachment> files, {
  int revision = 0,
  EntityId? actor,
  EntityId? business,
}) {
  w.database.saveReconciliationDraft(
    businessId: business ?? w.identity.businessId,
    statementId: statement,
    actorId: actor ?? w.identity.ownerId,
    expectedRevision: revision,
    startsOn: DateTime.utc(2026, 9, 1),
    endsOn: DateTime.utc(2026, 9, 30),
    openingBalance: Money.fromMinor(10000, 'MYR'),
    closingBalance: Money.fromMinor(9000, 'MYR'),
    openingEvidence: 'Fictional opening source verified.',
    savedAt: DateTime.utc(2026, 10, 3),
    attachments: files,
  );
}

StatementReconciliationSnapshot review(
  AccountingWorkspace w,
  EntityId statement,
) {
  return w.database.prepareStatementReconciliation(
    businessId: w.identity.businessId,
    statementId: statement,
    startsOn: DateTime.utc(2026, 9, 1),
    endsOn: DateTime.utc(2026, 9, 30),
    openingBalance: Money.fromMinor(10000, 'MYR'),
    closingBalance: Money.fromMinor(9000, 'MYR'),
  );
}

EntityId approve(
  AccountingWorkspace w,
  EntityId statement,
  List<ReceiptAttachment> files, {
  EntityId? request,
  StatementReconciliationSnapshot? reviewed,
  DateTime? at,
}) {
  final snapshot = reviewed ?? review(w, statement);
  final id = request ?? EntityId.random();
  w.database.approveStatementReconciliation(
    requestId: id,
    businessId: w.identity.businessId,
    statementId: statement,
    actorId: w.identity.ownerId,
    approvedAt: at ?? DateTime.utc(2026, 10, 3),
    startsOn: snapshot.startsOn,
    endsOn: snapshot.endsOn,
    openingBalance: snapshot.openingBalance,
    closingBalance: snapshot.closingBalance,
    expectedAcceptanceIds: snapshot.acceptanceIds,
    expectedPreviousId: snapshot.previousId,
    firstOpeningEvidence: 'Fictional opening source verified.',
    attachments: files,
  );
  return id;
}

void main() {
  test('supporting originals survive restart, approval retry and reopening without rewriting history', () async {
    final dir = Directory.systemTemp.createTempSync('reconciliation-files-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(1, path: path);
    var w = f.w;
    final files = [file('opening'), file('confirmation')];
    save(w, f.statement, files);
    final business = w.identity.businessId;
    w.dispose();
    w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    final restored = w.database.readReconciliationDraft(business, f.statement)!;
    expect(
      restored.attachments.map((f) => f.toJson()),
      files.map((f) => f.toJson()),
    );
    expect(() => restored.attachments.clear(), throwsUnsupportedError);
    final reviewed = review(w, f.statement);
    final request = approve(
      w,
      f.statement,
      restored.attachments,
      reviewed: reviewed,
    );
    approve(
      w,
      f.statement,
      restored.attachments,
      request: request,
      reviewed: reviewed,
    );
    expect(
      () => approve(
        w,
        f.statement,
        [file('different')],
        request: request,
        reviewed: reviewed,
      ),
      throwsStateError,
    );
    expect(w.database.readReconciliationDraft(business, f.statement), isNull);
    w.database.reopenStatementReconciliation(
      businessId: business,
      completionId: request.value,
      actorId: w.identity.ownerId,
      reopenedAt: DateTime.utc(2026, 10, 4),
      reason: 'Fictional corrected evidence.',
    );
    approve(w, f.statement, [
      file('new confirmation'),
    ], at: DateTime.utc(2026, 10, 5));
    expect(
      w.database
          .reconciliationEvidence(business, request.value)
          .attachments
          .map((f) => f.toJson()),
      files.map((f) => f.toJson()),
    );
    expect(
      w.database.bankStatement(business, f.statement)!.sourceBytes,
      f.original,
    );
    expect(await w.journals(), hasLength(2));
  });
  test('missing, duplicate, pending and checksum-altered files cannot enter draft or approval', () async {
    final f = await fixture(1);
    addTearDown(f.w.dispose);
    final good = file('original');
    final pending = good.withStatus(AttachmentProcessingStatus.queued);
    final empty = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'empty',
        batchId: 'fictional',
        filename: 'Empty.png',
        mimeType: 'image/png',
        bytes: Uint8List(0),
      ),
    ).withStatus(AttachmentProcessingStatus.ready);
    final changed = file('changed');
    changed.originalBytes[0] ^= 1;
    for (final (files, failure) in [
      ([pending], throwsStateError),
      ([empty], throwsStateError),
      ([good, good], throwsFormatException),
      ([changed], throwsFormatException),
    ]) {
      expect(() => save(f.w, f.statement, files), failure);
      expect(() => approve(f.w, f.statement, files), failure);
    }
    expect(
      f.w.database.readReconciliationDraft(
        f.w.identity.businessId,
        f.statement,
      ),
      isNull,
    );
    expect(
      f.w.database.reconciliationHistory(f.w.identity.businessId, f.statement),
      isEmpty,
    );
    expect(await f.w.journals(), hasLength(2));
  });
  test(
    'supporting file draft writes retain company, actor and revision checks',
    () async {
      final f = await fixture(1);
      addTearDown(f.w.dispose);
      final files = [file('original')];
      expect(
        () => save(f.w, f.statement, files, actor: EntityId.random()),
        throwsStateError,
      );
      expect(
        () => save(f.w, f.statement, files, business: EntityId.random()),
        throwsStateError,
      );
      save(f.w, f.statement, files);
      expect(() => save(f.w, f.statement, [file('stale')]), throwsStateError);
      expect(
        f.w.database.readReconciliationDraft(EntityId.random(), f.statement),
        isNull,
      );
      expect(
        f.w.database
            .readReconciliationDraft(f.w.identity.businessId, f.statement)!
            .attachments
            .single
            .originalId,
        'original',
      );
    },
  );
  test('schema 58 upgrade adds empty supporting files without changing statement or journals', () async {
    final dir = Directory.systemTemp.createTempSync(
      'reconciliation-files-upgrade-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/books.sqlite';
    final f = await fixture(1, path: path);
    save(f.w, f.statement, []);
    final business = f.w.identity.businessId;
    f.w.dispose();
    final old = sqlite3.open(path);
    dropCurrentQuotationFixtureOwner(old);
    old.execute(
      'ALTER TABLE bank_reconciliation_drafts DROP COLUMN attachments',
    );
    old.execute('DROP VIEW IF EXISTS current_expense_intakes');
    old.execute('DROP VIEW IF EXISTS financial_expense_intakes');
    old.execute('DROP TABLE IF EXISTS expense_revision_postings');
    old.execute('DROP TABLE IF EXISTS expense_revision_drafts');
    old.execute('PRAGMA user_version=58');
    old.dispose();
    final w = await AccountingWorkspace.open(path);
    addTearDown(w.dispose);
    expect(
      w.database.readReconciliationDraft(business, f.statement)!.attachments,
      isEmpty,
    );
    expect(
      w.database.bankStatement(business, f.statement)!.sourceBytes,
      f.original,
    );
    expect(await w.journals(), hasLength(2));
  });
  test('data-only recovery retains file identity and hash without fabricating original availability', () async {
    final f = await fixture(1);
    addTearDown(f.w.dispose);
    final original = file('original');
    save(f.w, f.statement, [original]);
    final archive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 10, 3),
    );
    final restored = LocalAccountingDatabase.inMemory();
    addTearDown(restored.close);
    restored.restoreDataArchive(archive);
    final draft = restored.readReconciliationDraft(
      f.w.identity.businessId,
      f.statement,
    )!;
    expect(draft.attachments.single.originalSha256, original.originalSha256);
    expect(draft.attachments.single.originalBytes, isEmpty);
    expect(draft.attachments.single.status, AttachmentProcessingStatus.failed);
    final request = approve(f.w, f.statement, [original]);
    final approvedArchive = f.w.database.exportDataArchive(
      f.w.identity.businessId,
      DateTime.utc(2026, 10, 3),
    );
    final approved = LocalAccountingDatabase.inMemory();
    addTearDown(approved.close);
    approved.restoreDataArchive(approvedArchive);
    final recovered = approved
        .reconciliationEvidence(f.w.identity.businessId, request.value)
        .attachments
        .single;
    expect(recovered.originalId, original.originalId);
    expect(recovered.originalSha256, original.originalSha256);
    expect(recovered.originalBytes, isEmpty);
  });
  test(
    'malformed supporting evidence makes archive recovery fail atomically',
    () async {
      final f = await fixture(1);
      addTearDown(f.w.dispose);
      save(f.w, f.statement, [file('original')]);
      final envelope = jsonDecode(
        f.w.database.exportDataArchive(
          f.w.identity.businessId,
          DateTime.utc(2026, 10, 3),
        ),
      ) as Map<String, dynamic>;
      final data =
          jsonDecode(envelope['data'] as String) as Map<String, dynamic>;
      final table = data['tables']['bank_reconciliation_drafts'];
      final index = (table['columns'] as List).indexOf('attachments');
      final files = jsonDecode(table['rows'][0][index]);
      files[0]['originalSha256'] = 'invalid';
      table['rows'][0][index] = jsonEncode(files);
      envelope['data'] = jsonEncode(data);
      envelope['sha256'] = sha256
          .convert(utf8.encode(envelope['data']))
          .toString();
      final restored = LocalAccountingDatabase.inMemory();
      addTearDown(restored.close);
      expect(
        () => restored.restoreDataArchive(jsonEncode(envelope)),
        throwsFormatException,
      );
      restored.restoreDataArchive(
        f.w.database.exportDataArchive(
          f.w.identity.businessId,
          DateTime.utc(2026, 10, 3),
        ),
      );
      expect(
        restored.readReconciliationDraft(f.w.identity.businessId, f.statement),
        isNotNull,
      );
    },
  );
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual uploader saves, removes and approves supporting originals at $width',
      (tester) async {
        await prepare(tester, width);
        final f = await fixture(1);
        addTearDown(f.w.dispose);
        var selections = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      TextButton(
                        key: const ValueKey('open-support'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => StatementReconciliationDialog(
                            workspace: f.w,
                            statementId: f.statement,
                            currency: 'MYR',
                            onAttachmentsPick: (_) async {
                              selections++;
                              if (selections == 2) return [];
                              if (selections == 3) {
                                return [
                                  PickedExpenseAttachment(
                                    name: "Empty.png",
                                    mimeType: "image/png",
                                    bytes: Uint8List(0),
                                  ),
                                ];
                              }
                              return [
                                PickedExpenseAttachment(
                                  name: 'Fictional opening.png',
                                  mimeType: 'image/png',
                                  bytes: pixels(),
                                ),
                                PickedExpenseAttachment(
                                  name: 'Fictional confirmation.png',
                                  mimeType: 'image/png',
                                  bytes: pixels(),
                                ),
                              ];
                            },
                          ),
                        ),
                        child: const Text('Reconciliation'),
                      ),
                      TextButton(
                        key: const ValueKey('open-history'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ReconciliationHistoryDialog(
                            workspace: f.w,
                            statementId: f.statement,
                          ),
                        ),
                        child: const Text('History'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, keyed('open-support'));
        await tester.enterText(keyed('reconciliation-start'), '01-09-2026');
        await tester.enterText(keyed('reconciliation-end'), '30-09-2026');
        await tester.enterText(keyed('reconciliation-opening'), '100.00');
        await tester.enterText(keyed('reconciliation-closing'), '90.00');
        await tap(tester, keyed('reconciliation-file-choose'));
        expect(find.byType(AccountingAttachmentDropzone), findsOneWidget);
        expect(find.byType(AccountingAttachmentRecordRow), findsNWidgets(2));
        final remove = find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'reconciliation-attachment-remove-',
                  ),
            )
            .last;
        await tap(tester, remove);
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        await capture(
          tester,
          'Reconciliation Supporting Files ${width.toInt()}',
        );
        await tap(tester, keyed('reconciliation-file-choose'));
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        await tap(tester, keyed('reconciliation-file-choose'));
        expect(
          find.text('Choose a supported, nonempty document.'),
          findsOneWidget,
        );
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        await capture(
          tester,
          'Reconciliation Supporting File Warning ${width.toInt()}',
        );
        await tap(tester, keyed('save-reconciliation-draft'));
        final draft = f.w.database.readReconciliationDraft(
          f.w.identity.businessId,
          f.statement,
        )!;
        expect(draft.attachments.single.originalBytes, pixels());
        await tap(tester, find.bySemanticsLabel('Close').last);
        await tap(tester, keyed('open-support'));
        expect(find.text('Fictional opening.png'), findsOneWidget);
        await tap(tester, keyed('review-reconciliation'));
        await tester.enterText(
          keyed('reconciliation-evidence'),
          'Fictional opening source verified.',
        );
        await tap(tester, keyed('approve-reconciliation'));
        expect(
          f.w.database.isStatementReconciled(
            f.w.identity.businessId,
            f.statement,
          ),
          isTrue,
        );
        expect(keyed('reconciliation-file-choose'), findsNothing);
        expect(keyed('review-reconciliation'), findsNothing);
        await capture(
          tester,
          'Reconciliation Approved Supporting Files ${width.toInt()}',
        );
        await tap(tester, find.bySemanticsLabel('Close').last);
        await tap(tester, keyed('open-history'));
        final approval = f.w.database
            .reconciliationHistory(f.w.identity.businessId, f.statement)
            .single;
        await tap(tester, keyed('reconciliation-evidence-${approval.id}'));
        final previewAction = keyed(
          'reconciliation-history-attachment-view-${draft.attachments.single.originalId}',
        );
        await tester.ensureVisible(previewAction);
        await tester.tap(previewAction);
        await pumpDecodedAttachment(tester);
        expect(
          (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
          pixels(),
        );
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        await capture(
          tester,
          'Reconciliation Supporting Original Preview ${width.toInt()}',
        );
        await tap(tester, find.bySemanticsLabel('Close').last);
        expect(
          f.w.database
              .reconciliationEvidence(f.w.identity.businessId, approval.id)
              .attachments
              .single
              .originalBytes,
          pixels(),
        );
        expect(
          f.w.database
              .bankStatement(f.w.identity.businessId, f.statement)!
              .sourceBytes,
          f.original,
        );
        expect(await f.w.journals(), hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
