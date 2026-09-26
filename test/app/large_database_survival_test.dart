import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/app.dart';
import 'package:audyt/app/demo_company.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/core/money/currency.dart';
import 'package:audyt/core/storage/record_metadata.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/application/journal_entry_repository.dart';
import 'package:audyt/features/accounting/domain/account.dart';
import 'package:audyt/features/accounting/domain/journal_entry.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/purchases/domain/payment_voucher.dart';
import 'package:audyt/features/purchases/domain/payment_voucher_source.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/purchases/domain/vendor.dart';
import 'package:audyt/features/purchases/domain/purchase_bill_draft.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'journal_workspace_integration_test.dart' show captureUi;
import '../support/accounting_test_finders.dart';
import '../support/attachment_preview_pump.dart';
import '../features/accounting/data/bank_statement_import_test.dart' show parse;
import 'filed_document_version_relocation_test.dart'
    show FiledFixture, receiptImage;

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Independent, bounded row hashing of every app-owned table. No archive
/// encoder or restore decoder supplies these expected values.
Map<String, Object> _inspect(
  String path, {
  Map<String, String> expectedStatementRecovery = const {},
}) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    final result = <String, Object>{};
    String quote(String name) => '"${name.replaceAll('"', '""')}"';
    for (final table in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    )) {
      final name = table['name'] as String;
      final columns = db.select('PRAGMA table_info(${quote(name)})');
      final primary = columns.where((c) => c['pk'] as int > 0).toList()
        ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
      final order = (primary.isEmpty ? columns : primary)
          .map((c) => quote(c['name'] as String))
          .join(',');
      final sink = _DigestSink();
      final converter = sha256.startChunkedConversion(sink);
      converter.add(
        utf8.encode(jsonEncode(columns.map((c) => c['name']).toList())),
      );
      var count = 0;
      while (true) {
        final rows = db.select(
          'SELECT * FROM ${quote(name)} ORDER BY $order LIMIT 512 OFFSET ?',
          [count],
        );
        for (final row in rows) {
          converter.add(
            utf8.encode(
              '${jsonEncode([
                for (final column in columns) () {
                    final replacement = name == 'bank_statement_imports' ? expectedStatementRecovery[row['id']] : null;
                    final value = replacement != null && column['name'] == 'source'
                        ? Uint8List(0)
                        : replacement != null && column['name'] == 'parsed_rows'
                        ? replacement
                        : row[column['name'] as String];
                    return value is Uint8List ? {'blob': base64Encode(value)} : value;
                  }(),
              ])}\n',
            ),
          );
        }
        count += rows.length;
        if (rows.length < 512) break;
      }
      converter.close();
      result[name] = {'rows': count, 'sha256': sink.value.toString()};
    }
    return result;
  } finally {
    db.dispose();
  }
}

void main() {
  late Directory compiler;
  late String nativeBinary;
  setUpAll(() async {
    if (!Platform.isMacOS) return;
    compiler = Directory.systemTemp.createTempSync('audyt-volume-native-');
    nativeBinary = '${compiler.path}/filed-document-bridge';
    final result = await Process.run('xcrun', [
      'swiftc',
      '-module-cache-path',
      '${compiler.path}/ModuleCache',
      '${Directory.current.path}/macos/Runner/ReceiptDestinationWriter.swift',
      '${Directory.current.path}/macos/Runner/DocumentPreviewRenderer.swift',
      '${Directory.current.path}/test/native/filed_document_versions/main.swift',
      '-o',
      nativeBinary,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
  tearDownAll(() {
    if (Platform.isMacOS && compiler.existsSync()) {
      compiler.deleteSync(recursive: true);
    }
  });
  final transactionCount = int.parse(
    Platform.environment['AUDYT_VOLUME_TRANSACTIONS'] ?? '10000',
  );
  if (transactionCount != 10000 && transactionCount != 100000) {
    throw ArgumentError(
      'Volume fixture supports 10000 or 100000 transactions.',
    );
  }
  final transactionsPerYear = transactionCount ~/ 10;
  testWidgets(
    '$transactionCount postings preserve year-crossing Bill payments vouchers native files recovery and reminders',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'audyt-volume-${transactionCount ~/ 1000}k-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final path = '${root.path}/source.sqlite';
      final restoredPath = '${root.path}/restored.sqlite';
      final native = (await tester.runAsync(
        () => FiledFixture.create(nativeBinary),
      ))!;
      addTearDown(() => tester.runAsync(native.close));
      final evidenceBytes = receiptImage(72, 133, 237);
      final rawEvidence = ReceiptAttachment.queued(
        ReceiptAttachmentInput(
          originalId: EntityId.random().value,
          batchId: EntityId.random().value,
          filename: 'Fictional Volume Bill.png',
          mimeType: 'image/png',
          bytes: evidenceBytes,
        ),
      );
      // Data-only books retain an honest external-file reference, not embedded
      // original bytes. The production native writer owns the actual file.
      final evidence = ReceiptAttachment.fromJson({
        ...rawEvidence.toJson(),
        'originalBytes': null,
        '_evidenceUnavailable': true,
      });
      final nativePaths = (await tester.runAsync(
        () async => [
          await native.save('expense', evidence.originalId, evidenceBytes),
        ],
      ))!;
      Future<dynamic>? nativeRead;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        namingSettingsChannel,
        (call) async {
          if (call.method == 'readDocument') {
            expect(
              (call.arguments as Map)['expectedSha256'],
              evidence.originalSha256,
            );
            nativeRead = tester.runAsync<dynamic>(() => native.channel(call));
            return await nativeRead;
          }
          return await tester.runAsync<dynamic>(() => native.channel(call));
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          null,
        ),
      );
      var workspace = await AccountingWorkspace.open(path);
      addTearDown(() => workspace.dispose());
      final measurements = <String, Object>{
        'postedTransactions': transactionCount,
        'historyYears': 11,
        'journalHistoryYears': 10,
        'schemaVersion': 42,
        'nativeEvidenceSha256': evidence.originalSha256,
        'rssBeforeBytes': ProcessInfo.currentRss,
        'memoryScope': 'Flutter test process, including harness; not isolated release-app memory',
        'hardware': Process.runSync('/usr/sbin/sysctl', [
          '-n',
          'hw.model',
          'hw.memsize',
        ]).stdout.toString().trim(),
        'sqliteVersion': sqlite3.version.toString(),
        'sourceQueryShape': 'readReport/listJournals batch journal rows and lines in one snapshot; still reads the full company book, no bounded page contract',
      };
      final timings = <String, int>{};
      final expected = <int, (int, int)>{};
      final watch = Stopwatch()..start();
      final accounts = <AccountType, EntityId>{};
      for (final (type, code) in [
        (AccountType.asset, '1000'),
        (AccountType.income, '4000'),
        (AccountType.expense, '5000'),
        (AccountType.liability, '2100'),
      ]) {
        await workspace.createAccount(
          code: code,
          name: 'Fictional ${type.name}',
          type: type,
        );
        accounts[type] = (await workspace.accounts())
            .singleWhere((a) => a.account.code == code)
            .account
            .id;
      }
      workspace.savePreferences(
        workspace.preferences
            .change('Sales Preferences', {
              'Customer Message': 'Volume fixture survives recovery',
            })
            .change('Reminders & Approvals', {'Visible Reminders': '3'}),
      );
      workspace.database.savePaymentAccount(
        workspace.identity.businessId,
        PaymentAccount.create(
          id: 'fictional-volume-bank',
          name: 'Fictional Volume Bank',
          type: PaymentAccountType.bank,
          currencyCode: 'MYR',
        ),
      );
      workspace.database.linkPaymentLedgerAccount(
        workspace.identity.businessId,
        'fictional-volume-bank',
        accounts[AccountType.asset]!,
      );
      final now = DateTime.now();
      final vendorSnapshots = <Map<String, Object?>>[];
      for (final (index, type) in vendorPayeeTypes.indexed) {
        final id = EntityId.random();
        final first = Vendor(
          metadata: RecordMetadata.initial(
            recordId: id,
            businessId: workspace.identity.businessId,
            originDeviceId: workspace.identity.deviceId,
            createdAt: now,
          ),
          payeeId: id.value,
          name: 'Fictional Volume Supplier $index',
          type: type,
          details: VendorDetails(
            values: {
              'email': 'volume$index@example.invalid',
              'postcode': '00123 AB',
              'countryCode': 'MY',
              'tin': 'FICT-TIN-$index',
            },
            taxDetailsNeeded: false,
          ),
          currency: Currency.parse('MYR'),
          terms: PaymentTerms.daysAfterIssue(30 + index),
        );
        workspace.saveVendor(first, expectedRevision: 0);
        final updated = Vendor(
          metadata: first.metadata.nextRevision(
            updatedAt: now.add(const Duration(seconds: 1)),
          ),
          payeeId: first.payeeId,
          name: '${first.name} Updated',
          type: type,
          details: first.details,
          currency: first.currency,
          terms: first.terms,
        );
        workspace.saveVendor(updated, expectedRevision: 1);
        vendorSnapshots.add(updated.toJson());
      }
      measurements['savedVendorSnapshots'] = vendorSnapshots;
      final lastNumber = transactionCount - 3;
      final lastYear = 2017 + lastNumber ~/ transactionsPerYear;
      final lastYearDays = DateTime(lastYear + 1)
          .difference(DateTime(lastYear))
          .inDays;
      final billDate = DateTime(
        lastYear,
      ).add(Duration(days: (lastNumber % transactionsPerYear) % lastYearDays));
      final payableMinor = 3000 + lastNumber % 43;
      final savedBills = <PurchaseBillDraft>[];
      for (final (index, supplier) in vendorSnapshots.indexed) {
        final vendor = Vendor.fromJson(supplier);
        final id = EntityId.random();
        final metadata = RecordMetadata.initial(
          recordId: id,
          businessId: workspace.identity.businessId,
          originDeviceId: workspace.identity.deviceId,
          createdAt: now,
        );
        PurchaseBillDraft draft(RecordMetadata revision, String memo) =>
            PurchaseBillDraft(
              metadata: revision,
              vendorSnapshot: vendor,
              documentNumber: workspace.database.allocateDocumentNumber(
                businessId: workspace.identity.businessId,
                actorId: workspace.identity.ownerId,
                recordId: id,
                documentType: 'bill',
                allocatedAt: now,
              ),
              issueDate: billDate,
              dueDate: vendor.terms.dueOn(billDate),
              terms: vendor.terms,
              lines: [
                SalesLineItem.category(
                  id: id,
                  categoryId: accounts[AccountType.expense]!,
                  description: 'Fictional volume purchase $index',
                  quantity: SalesQuantity.fromDecimal('1'),
                  rate: Money.fromMinor(
                    index == 2 ? payableMinor : 1234 + index,
                    'MYR',
                  ),
                ),
              ],
              supplierReference: 'VOLUME-SUP-$index',
              memo: memo,
              classification: 'Saved Class',
              location: 'Saved Branch',
              attachments: index == 2 ? [evidence] : const [],
            );
        workspace.saveBillDraft(
          draft(metadata, 'First bill memo'),
          expectedRevision: 0,
        );
        final updated = draft(
          metadata.nextRevision(updatedAt: now.add(const Duration(seconds: 2))),
          'Revised bill memo',
        );
        workspace.saveBillDraft(updated, expectedRevision: 1);
        savedBills.add(updated);
      }
      final postedBill = savedBills.last;
      final payments = <StoredBillSettlement>[];
      final paymentDates = [DateTime.utc(2027, 1, 1), DateTime.utc(2027, 1, 2)];
      final paymentAmounts = [1000, 500];
      final voucherSnapshots = <Map<String, Object?>>[];
      measurements['savedBillSnapshots'] = savedBills
          .map((b) => b.toJson())
          .toList();
      measurements['postedBillId'] = postedBill.id.value;
      void verifyBills() {
        for (final bill in savedBills) {
          expect(
            workspace.database
                .readBillDraft(workspace.identity.businessId, bill.id)!
                .toJson(),
            bill.toJson(),
          );
          expect(
            workspace.database.billDraftHistory(
              workspace.identity.businessId,
              bill.id,
            ),
            hasLength(2),
          );
        }
        expect(
          workspace.database
              .billDraftPage(businessId: workspace.identity.businessId)
              .total,
          2,
        );
        expect(
          workspace.database
              .billDraftPage(
                businessId: workspace.identity.businessId,
                posted: true,
              )
              .total,
          1,
        );
        final posting = workspace.database.readBillPosting(
          workspace.identity.businessId,
          postedBill.id,
        )!;
        expect(posting.source.toJson(), postedBill.toJson());
        expect(posting.payableAccountId, accounts[AccountType.liability]);
      }

      void verifyVendors() {
        for (final snapshot in vendorSnapshots) {
          final id = EntityId.parse(snapshot['id'] as String);
          expect(
            workspace.database
                .readVendor(workspace.identity.businessId, id)!
                .toJson(),
            snapshot,
          );
          expect(
            workspace.database
                .vendorHistory(workspace.identity.businessId, id)
                .length,
            2,
          );
          expect(
            workspace.payees.byId(snapshot['payeeId'] as String)!.name,
            snapshot['name'],
          );
        }
      }

      workspace.saveReminders([
        for (final (index, title) in [
          'Annual Return',
          'Income Tax',
          'SST Return',
        ].indexed)
          WorkspaceReminder(
            id: EntityId.random(),
            title: title,
            obligation: [
              'SSM Annual Return',
              'Income Tax Return',
              'SST Return',
            ][index],
            agency: ['SSM', 'LHDN / HASiL', 'Kastam / RMCD'][index],
            legalSource: 'Fictional volume-test dates; not statutory guidance',
            dueDate: now.add(Duration(days: 20 + index * 10)),
            icon: 'Calendar',
          ),
      ]);
      await tester.runAsync(() async {
        for (var n = 0; n < transactionCount; n++) {
          final year = 2017 + n ~/ transactionsPerYear;
          final days = DateTime(year + 1).difference(DateTime(year)).inDays;
          final date = DateTime(year)
              .add(Duration(days: (n % transactionsPerYear) % days));
          final sale = n.isEven;
          final minor = sale ? 10000 + n % 97 : 3000 + n % 43;
          final previous = expected[year] ?? (0, 0);
          if (n <= lastNumber) {
            expected[year] = sale
                ? (previous.$1 + minor, previous.$2)
                : (previous.$1, previous.$2 + minor);
          }
          final id = EntityId.parse(
            '018f0c4e-56f1-7d4a-b9bb-${(n + 1).toString().padLeft(12, '0')}',
          );
          if (n == lastNumber) {
            workspace.postBill(
              requestId: id,
              billId: postedBill.id,
              expectedRevision: 2,
              payableAccountId: accounts[AccountType.liability]!,
              approvedAt: postedBill.metadata.updatedAt.add(
                const Duration(seconds: 1),
              ),
            );
          } else if (n > lastNumber) {
            final index = n - lastNumber - 1;
            final remaining =
                payableMinor - (index == 0 ? 0 : paymentAmounts[0]);
            payments.add(
              workspace.settleRecognizedBills(
                requestId: id,
                allocations: [
                  BillSettlementAllocation(
                    billId: postedBill.id,
                    revision: 2,
                    expectedRemaining: Money.fromMinor(remaining, 'MYR'),
                    amount: Money.fromMinor(paymentAmounts[index], 'MYR'),
                  ),
                ],
                paymentAccountId: 'fictional-volume-bank',
                paymentReference:
                    'Fictional year-crossing payment ${index + 1}',
                paidOn: paymentDates[index],
                approvedAt: paymentDates[index].add(const Duration(hours: 1)),
              ),
            );
          } else {
            await workspace.database.save(
              StoredJournalEntry(
                entry: JournalEntry.draft(
                  id: id,
                  date: date,
                  memo: 'Fictional volume ${n + 1}',
                  lines: [
                    JournalLine.debit(
                      accountId:
                          accounts[sale
                              ? AccountType.asset
                              : AccountType.expense]!,
                      amount: Money.fromMinor(minor, 'MYR'),
                    ),
                    JournalLine.credit(
                      accountId:
                          accounts[sale
                              ? AccountType.income
                              : AccountType.asset]!,
                      amount: Money.fromMinor(minor, 'MYR'),
                    ),
                  ],
                ),
                metadata: RecordMetadata.initial(
                  recordId: id,
                  businessId: workspace.identity.businessId,
                  originDeviceId: workspace.identity.deviceId,
                  createdAt: date.toUtc(),
                ),
              ),
            );
            await workspace.approveJournal(
              JournalApproval(
                requestId: id,
                businessId: workspace.identity.businessId,
                journalId: id,
                expectedRevision: 1,
                actorId: workspace.identity.ownerId,
                approvedAt: date.toUtc().add(const Duration(hours: 1)),
              ),
            );
          }
          if ((n + 1) % 1000 == 0) {
            stdout.writeln(
              'Volume fixture: ${n + 1}/$transactionCount posted; ${watch.elapsedMilliseconds}ms elapsed',
            );
          }
        }
      });
      timings['seedMs'] = watch.elapsedMilliseconds;
      expected[2027] = (0, 0);
      final openingMinor =
          expected.values.fold<int>(0, (sum, v) => sum + v.$1 - v.$2) +
          payableMinor;
      final sources = workspace.vouchers.sources;
      expect(sources, hasLength(2));
      for (final payment in payments) {
        final source = sources.singleWhere(
          (s) => s.id == '${postedBill.id.value}/${payment.id.value}',
        );
        PaymentVoucher voucher({
          List<ReceiptAttachment> attachments = const [],
        }) => PaymentVoucher.create(
          id: EntityId.random().value,
          sourceType: source.type,
          sourceId: source.id,
          payee: source.payee,
          amount: source.amount,
          paymentAccount: 'Fictional Volume Bank',
          paymentAccountId: source.paymentAccountId,
          paymentMethod: 'Bank Transfer',
          paymentDate: source.date,
          reference: payment.reference,
          attachments: attachments,
        );
        // A filed copy does not manufacture missing original evidence for a
        // new submission. The approved voucher links its Bill's retained file.
        expect(
          () => workspace.vouchers.saveAndSubmit(
            voucher(attachments: [evidence]),
          ),
          throwsStateError,
        );
        final v = voucher();
        workspace.vouchers.saveAndSubmit(v);
        workspace.vouchers.approve(v.id);
        final paid = workspace.vouchers.recordPayment(v.id);
        expect(paid.paymentEvidence!.journalId, payment.journalId);
        expect(paid.paymentEvidence!.movementAmount, payment.total);
        expect(paid.paidAt, payment.paidOn);
      }
      final statementInput = parse(
        'Date,Description,Amount\n2027-01-01,Fictional year-crossing payment 1,-10.00\n2027-01-02,Fictional year-crossing payment 2,-5.00',
      );
      final statement = workspace.database.importBankStatement(
        id: EntityId.random(),
        businessId: workspace.identity.businessId,
        paymentAccountId: 'fictional-volume-bank',
        importedAt: DateTime.utc(2027, 2, 1),
        statement: statementInput,
      );
      for (final (index, payment) in payments.indexed) {
        workspace.database.acceptStatementMatch(
          businessId: workspace.identity.businessId,
          statementId: statement,
          sourceRow: index + 2,
          journalId: payment.journalId,
          lineIndex: 1,
          actorId: workspace.identity.ownerId,
          acceptedAt: DateTime.utc(2027, 2, 1),
        );
      }
      final completion = EntityId.random();
      workspace.database.approveStatementReconciliation(
        requestId: completion,
        businessId: workspace.identity.businessId,
        statementId: statement,
        actorId: workspace.identity.ownerId,
        approvedAt: DateTime.utc(2027, 2, 2),
        startsOn: DateTime.utc(2027, 1, 1),
        endsOn: DateTime.utc(2027, 1, 31),
        openingBalance: Money.fromMinor(openingMinor, 'MYR'),
        closingBalance: Money.fromMinor(openingMinor - 1500, 'MYR'),
        expectedAcceptanceIds: {
          for (final row in [2, 3])
            row: workspace.database.statementMatchAcceptanceId(
              workspace.identity.businessId,
              statement,
              row,
            )!,
        },
        expectedPreviousId: null,
        firstOpeningEvidence: 'Fictional full ledger carried balance through 2026 verified independently',
      );
      for (final v in workspace.vouchers.all) {
        final reconciled = workspace.vouchers.reconcile(v.id);
        expect(reconciled.reconciliationEvidence!.completionId, completion);
        voucherSnapshots.add(reconciled.toJson());
      }
      measurements['yearCrossingPayments'] = payments
          .map(
            (p) => {
              'id': p.id.value,
              'journalId': p.journalId.value,
              'amountMinor': p.total.minorUnits,
              'date': p.paidOn.toIso8601String(),
            },
          )
          .toList();
      measurements['voucherSnapshots'] = voucherSnapshots;
      measurements['bankOpeningMinor'] = openingMinor;
      measurements['bankClosingMinor'] = openingMinor - 1500;
      measurements['completionId'] = completion.value;
      void verifyPayments() {
        final savedStatement = workspace.database.bankStatement(
          workspace.identity.businessId,
          statement,
        )!;
        expect(savedStatement.digest, statementInput.digest);
        expect(savedStatement.parsedRowsJson, statementInput.parsedRowsJson);
        if (savedStatement.sourceAvailable) {
          expect(savedStatement.sourceBytes, statementInput.sourceBytes);
        } else {
          expect(savedStatement.sourceBytes, isEmpty);
        }
        expect(
          workspace.database.billOutstanding(
            workspace.identity.businessId,
            postedBill.id,
          ),
          Money.fromMinor(payableMinor - 1500, 'MYR'),
        );
        expect(
          workspace.database.billOutstanding(
            workspace.identity.businessId,
            postedBill.id,
            asOf: DateTime.utc(2026, 12, 31),
          ),
          Money.fromMinor(payableMinor, 'MYR'),
        );
        for (final snapshot in voucherSnapshots) {
          final v = workspace.vouchers.byId(snapshot['id'] as String)!;
          expect(v.toJson(), snapshot);
          expect(
            workspace.vouchers.verification(v).status,
            PaymentVoucherStatus.reconciled,
          );
          expect(v.sourceId.startsWith('${postedBill.id.value}/'), true);
        }
        for (final p in payments) {
          final saved = workspace.database.readBillSettlement(
            workspace.identity.businessId,
            p.id,
          )!;
          expect(saved.journalId, p.journalId);
          expect(saved.total, p.total);
          expect(saved.paidOn, p.paidOn);
        }
      }

      verifyPayments();
      watch.reset();
      measurements['rssAfterSeedBytes'] = ProcessInfo.currentRss;
      final readOnly = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        measurements['storedJournalMode'] =
            readOnly.select('PRAGMA journal_mode').single.values.single
                as String;
        measurements['reportJournalQueryPlan'] = readOnly
            .select(
              'EXPLAIN QUERY PLAN SELECT e.* FROM journal_entries e WHERE e.business_id=? ORDER BY e.entry_date,e.id',
              [workspace.identity.businessId.value],
            )
            .map((r) => r['detail'])
            .toList();
        // Inspect the production reader's actual SQL, not a hand-copied query.
        final ageingSql =
            RegExp(
                  r'SELECT l\.rowid AS scan_id.*?ORDER BY l\.rowid LIMIT 512',
                  dotAll: true,
                )
                .firstMatch(
                  File('lib/features/accounting/data/bill_ageing_database.dart')
                      .readAsStringSync(),
                )!
                .group(0)!;
        final ageingPlan = readOnly
            .select('EXPLAIN QUERY PLAN $ageingSql', [
              accounts[AccountType.liability]!.value,
              0,
              workspace.identity.businessId.value,
              '2027-12-31',
            ])
            .map((r) => r['detail'] as String)
            .toList();
        expect(
          ageingPlan.any((line) => line.contains('journal_lines_account')),
          true,
          reason: 'Payable account lines must seek the existing account index',
        );
        measurements['payablesAgeingControlQueryPlan'] = ageingPlan;
        for (final kind in ['bill.posted', 'bill.draft_saved']) {
          final plan = readOnly
              .select(
                "EXPLAIN QUERY PLAN SELECT * FROM ledger_audit WHERE business_id=? AND kind='$kind' AND subject_id=?",
                [workspace.identity.businessId.value, postedBill.id.value],
              )
              .map((r) => r['detail'] as String)
              .toList();
          expect(
            plan.any(
              (line) => line.contains('SEARCH ledger_audit USING INDEX'),
            ),
            true,
            reason: 'Bill history must seek its own audit evidence rather than scan the full book',
          );
          measurements['${kind}QueryPlan'] = plan;
        }
      } finally {
        readOnly.dispose();
      }
      final originalTables = _inspect(path);
      // Only the documented data-only statement transformation differs.
      // Expected parsed rows come from the supplied input, not the archive.
      final expectedRecoveryTables = _inspect(
        path,
        expectedStatementRecovery: {
          statement.value: statementInput.parsedRowsJson,
        },
      );
      for (final (table, count) in [
        ('journal_entries', transactionCount),
        ('journal_lines', transactionCount * 2),
        ('journal_approvals', transactionCount),
        ('vendor_profiles', 3),
        ('vendor_history', 6),
        ('bill_drafts', 3),
        ('bill_draft_history', 6),
        ('bill_postings', 1),
        ('bill_settlements', 2),
        ('bill_settlement_allocations', 2),
        ('payment_vouchers', 2),
        ('bank_reconciliations', 1),
      ]) {
        expect((originalTables[table] as Map)['rows'], count);
      }

      timings['allTableHashesMs'] = watch.elapsedMilliseconds;
      measurements['tableHashes'] = originalTables;
      measurements['databaseBytes'] = File(path).lengthSync();
      Future<void> reports(String phase) async {
        var accumulated = 0;
        final reportTimes = <int>[];
        final ageingTimes = <int>[];
        for (final year in expected.keys) {
          watch.reset();
          final report = await workspace.report(
            from: DateTime(year),
            through: DateTime(year, 12, 31),
          );
          reportTimes.add(watch.elapsedMilliseconds);
          final amounts = expected[year]!;
          accumulated += amounts.$1 - amounts.$2;
          expect(report.revenue, BigInt.from(amounts.$1));
          expect(report.expenses, BigInt.from(amounts.$2));
          expect(report.periodProfit, BigInt.from(amounts.$1 - amounts.$2));
          // The cost belongs to 2026; only the linked 2027 payments reduce
          // cash and Payables. They never change either year's P&L.
          final payable = year < lastYear
              ? 0
              : payableMinor - (year >= 2027 ? 1500 : 0);
          expect(report.assets, BigInt.from(accumulated + payable));
          expect(report.liabilities, BigInt.from(payable));
          expect(report.isBalanced, true);
          watch.reset();
          final ageing = workspace.database.payablesAgeing(
            businessId: workspace.identity.businessId,
            currency: workspace.identity.currency,
            asOf: DateTime.utc(year, 12, 31),
          );
          ageingTimes.add(watch.elapsedMilliseconds);
          expect(ageing.outstandingMinor, BigInt.from(payable));
          expect(ageing.controls.single.ledgerMinor, BigInt.from(payable));
          expect(ageing.controls.single.differenceMinor, BigInt.zero);
          expect(ageing.total, year < lastYear ? 0 : 1);
        }
        measurements['${phase}AnnualReportMs'] = reportTimes;
        measurements['${phase}PayablesAgeingMs'] = ageingTimes;
      }

      await reports('source');
      verifyBills();
      verifyPayments();
      watch.reset();
      final journals = await workspace.journals();
      timings['listAllJournalsMs'] = watch.elapsedMilliseconds;
      expect(journals, hasLength(transactionCount));
      expect(
        journals.map((j) => j.entry.id).toSet(),
        hasLength(transactionCount),
      );
      expect(
        journals.every(
          (j) =>
              j.entry.state == JournalEntryState.posted &&
              j.metadata.revision == 2,
        ),
        true,
      );
      watch.reset();
      measurements['rssBeforeExportBytes'] = ProcessInfo.currentRss;
      final archive = workspace.database.exportDataArchive(
        workspace.identity.businessId,
        DateTime.utc(2027, 2, 3),
      );
      timings['exportMs'] = watch.elapsedMilliseconds;
      measurements['rssAfterExportBytes'] = ProcessInfo.currentRss;
      measurements['archiveUtf8Bytes'] = utf8.encode(archive).length;
      final identity = workspace.identity;
      workspace.dispose();
      final sourceBytesHash = sha256
          .convert(File(path).readAsBytesSync())
          .toString();
      watch.reset();
      workspace = await AccountingWorkspace.open(path);
      timings['reopenMs'] = watch.elapsedMilliseconds;
      expect(workspace.identity.businessId, identity.businessId);
      expect(_inspect(path), originalTables);
      await reports('reopened');
      verifyVendors();
      verifyBills();
      verifyPayments();
      workspace.dispose();
      watch.reset();
      measurements['rssBeforeRestoreBytes'] = ProcessInfo.currentRss;
      workspace = await AccountingWorkspace.emptyRestore(restoredPath, archive);
      timings['restoreMs'] = watch.elapsedMilliseconds;
      measurements['rssAfterRestoreBytes'] = ProcessInfo.currentRss;
      verifyVendors();
      verifyBills();
      verifyPayments();
      expect(workspace.identity.businessId, identity.businessId);
      expect(workspace.identity.ownerId, identity.ownerId);
      expect(workspace.identity.deviceId, identity.deviceId);
      expect(_inspect(restoredPath), expectedRecoveryTables);
      expect(
        sha256.convert(File(path).readAsBytesSync()).toString(),
        sourceBytesHash,
      );
      await reports('restored');
      final originalReminders = workspace.reminders
          .map((r) => r.toJson())
          .toList();
      expect(
        workspace.preferences.text('Sales Preferences', 'Customer Message'),
        'Volume fixture survives recovery',
      );
      expect(workspace.reminders, hasLength(3));
      workspace.dispose();
      workspace = await AccountingWorkspace.open(restoredPath);
      expect(_inspect(restoredPath), expectedRecoveryTables);
      verifyPayments();
      await tester.runAsync(() async {
        final before = await native.request('inspect') as Map;
        expect(before['pending'], false);
        await native.request('prepare');
        // A new native reader process replays the durable proposal first.
        expect(
          await native.read(evidence.originalId, evidenceBytes),
          evidenceBytes,
        );
        final moved = await native.request('inspect') as Map;
        expect(moved['pending'], false);
        final destination = Directory('${native.root.path}/Destination')
            .resolveSymbolicLinksSync();
        expect((moved['roots'] as Map).length, 4);
        for (final root in (moved['roots'] as Map).values) {
          expect(
            Directory(root as String).resolveSymbolicLinksSync(),
            destination,
          );
        }
        for (final link in (moved['links'] as Map).values) {
          final file = File((link as Map)['path'] as String);
          expect(file.resolveSymbolicLinksSync(), startsWith('$destination/'));
          expect(file.readAsBytesSync(), evidenceBytes);
        }
        expect(nativePaths.any((path) => File(path).existsSync()), false);
        measurements['nativeRelocationRoots'] = moved['roots'];
        measurements['nativeRelocationLinkCount'] =
            (moved['links'] as Map).length;
      });
      expect(_inspect(restoredPath), expectedRecoveryTables);
      expect(
        workspace.reminders.map((r) => r.toJson()).toList(),
        originalReminders,
      );
      final damaged = jsonDecode(archive) as Map<String, dynamic>;
      damaged['sha256'] = '0' * 64;
      await expectLater(
        AccountingWorkspace.emptyRestore(
          '${root.path}/damaged.sqlite',
          jsonEncode(damaged),
        ),
        throwsFormatException,
      );
      expect(_inspect(restoredPath), expectedRecoveryTables);
      expect(
        sha256.convert(File(path).readAsBytesSync()).toString(),
        sourceBytesHash,
      );
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [720.0, 1224.0]) {
        tester.view.physicalSize = Size(width, 1200);
        final homeWatch = Stopwatch()..start();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                key: ValueKey(width),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/home',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        timings['homeFirstPaint${width.toInt()}Ms'] =
            homeWatch.elapsedMilliseconds;
        String metricValue(String label) {
          final group = find.ancestor(
            of: find.text(label),
            matching: find.byType(AccountingMetricTextGroup),
          );
          expect(group, findsOneWidget);
          return (tester.widget<AccountingMetricTextGroup>(group).value!
                  as Text)
              .data!;
        }

        final bankBalanceLabel = metricValue('All Balance');
        expect(bankBalanceLabel, startsWith('RM '));
        for (final title in ['Annual Return', 'Income Tax', 'SST Return']) {
          expect(find.text(title), findsOneWidget);
        }
        await captureUi(
          tester,
          '$transactionCount Transactions Home ${width.toInt()}',
        );
        for (final record in workspace.reminders) {
          final toggle = find.byKey(
            ValueKey('reminder-disclosure-${record.title}'),
          );
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('${record.obligation} · ${record.agency}'),
            findsOneWidget,
          );
          expect(
            find.byKey(
              ValueKey(
                'demo-reminder-complete-${workspace.reminders.indexWhere((r) => r.id == record.id)}',
              ),
            ),
            findsOneWidget,
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }
        expect(_inspect(restoredPath), expectedRecoveryTables);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                key: ValueKey('volume-reminders-$width'),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/taxes',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(Tab, 'Deadlines'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('new-reminder')), findsOneWidget);
        for (final record in workspace.reminders) {
          expect(
            find.byKey(ValueKey('reminder-row-${record.id.value}')),
            findsOneWidget,
          );
          final edit = find.byKey(ValueKey('edit-reminder-${record.id.value}'));
          await tester.ensureVisible(edit);
          await tester.pumpAndSettle();
          await tester.tap(edit);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('reminder-name')),
                )
                .controller!
                .text,
            record.title,
          );
          expect(find.byKey(const ValueKey('reminder-save')), findsOneWidget);
          await captureUi(
            tester,
            '$transactionCount Transactions Reminder ${record.title} ${width.toInt()}',
          );
          await tester.tap(accountingCloseIcon().last);
          await tester.pumpAndSettle();
          expect(_inspect(restoredPath), expectedRecoveryTables);
        }

        Future<void> tap(Finder target) async {
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        final bankWatch = Stopwatch()..start();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                key: ValueKey('volume-banking-$width'),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/banking',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        timings['bankingFirstPaint${width.toInt()}Ms'] =
            bankWatch.elapsedMilliseconds;
        expect(metricValue('Bank Balance'), bankBalanceLabel);
        bankWatch.reset();
        await openStatementReview(tester, statementId: statement.value);
        timings['bankingMatchReviewOpen${width.toInt()}Ms'] =
            bankWatch.elapsedMilliseconds;
        expect(find.byKey(const ValueKey('match-search')), findsOneWidget);
        expect(
          find.textContaining('Fictional year-crossing payment 1'),
          findsWidgets,
        );
        await captureUi(
          tester,
          '$transactionCount Transactions Banking Match ${width.toInt()}',
        );
        expect(_inspect(restoredPath), expectedRecoveryTables);

        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                key: ValueKey('volume-payments-$width'),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/expenses-vendors',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tabs = tester.widget<AccountingTabs>(
          find.byKey(const ValueKey('area-tabs-expenses-vendors')),
        );
        Future<void> tab(String label) => tap(
          find.byKey(
            ValueKey(
              'preview-tab-expenses-vendors-${tabs.labels.indexOf(label)}',
            ),
          ),
        );
        final uiWatch = Stopwatch()..start();
        await tab('Pay Bills');
        timings['payablesFirstPaint${width.toInt()}Ms'] =
            uiWatch.elapsedMilliseconds;
        expect(
          find.byKey(ValueKey('pay-bill-row-${postedBill.id}')),
          findsOneWidget,
        );
        expect(find.text('Partially Paid'), findsOneWidget);
        await captureUi(
          tester,
          '$transactionCount Transactions Pay Bills ${width.toInt()}',
        );
        await tap(find.byKey(ValueKey('view-pay-bill-${postedBill.id}')));
        expect(
          tester
              .widget<AccountingInformationRows>(
                find.byType(AccountingInformationRows),
              )
              .rows,
          contains((
            'Posting Journal',
            EntityId.parse(
              '018f0c4e-56f1-7d4a-b9bb-${(lastNumber + 1).toString().padLeft(12, '0')}',
            ).value,
          )),
        );
        final viewImage = find.byKey(
          ValueKey(
            'pay-bill-attachment-${postedBill.id}-${evidence.originalId}',
          ),
        );
        await tester.ensureVisible(viewImage);
        await tester.pumpAndSettle();
        nativeRead = null;
        await tester.tap(viewImage);
        await tester.pump();
        await nativeRead;
        await pumpDecodedAttachment(tester);
        expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
        expect(
          (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
          evidenceBytes,
        );
        expect(
          find.text(
            'Linked filed copy · original evidence remains outside this data archive.',
          ),
          findsOneWidget,
        );
        await captureUi(
          tester,
          '$transactionCount Transactions Relocated Bill File ${width.toInt()}',
        );
        await tap(accountingCloseIcon().last);
        await tap(accountingCloseIcon().last);
        uiWatch.reset();
        await tab('Payment Vouchers');
        timings['vouchersFirstPaint${width.toInt()}Ms'] =
            uiWatch.elapsedMilliseconds;
        final selectedVoucher = PaymentVoucher.fromJson(
          voucherSnapshots.first.cast<String, dynamic>(),
        );
        await tap(find.byKey(ValueKey('voucher-view-${selectedVoucher.id}')));
        final sourceSelector = tester
            .widget<AccountingSelector<PaymentVoucherSource>>(
              find.byType(AccountingSelector<PaymentVoucherSource>),
            );
        expect(sourceSelector.value!.id, selectedVoucher.sourceId);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('voucher-date')))
              .controller!
              .text,
          '01-01-2027',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('voucher-amount')),
              )
              .controller!
              .text,
          '10.00',
        );
        await captureUi(
          tester,
          '$transactionCount Transactions Voucher View ${width.toInt()}',
        );
        await tap(accountingCloseIcon().last);
        verifyPayments();
        expect(_inspect(restoredPath), expectedRecoveryTables);

        // Separate core data-read costs from the Accounting shell's first
        // paint so a large-book slowdown has an actionable owner.
        if (width == 720) {
          uiWatch.reset();
          workspace.database.readJournalPage(
            businessId: workspace.identity.businessId,
            state: JournalEntryState.draft,
            limit: 1,
          );
          timings['preMountDraftCountMs'] = uiWatch.elapsedMilliseconds;
          uiWatch.reset();
          workspace.database.readJournalPage(
            businessId: workspace.identity.businessId,
            state: JournalEntryState.posted,
            limit: 10,
          );
          timings['preMountPostedPageMs'] = uiWatch.elapsedMilliseconds;
          uiWatch.reset();
          await workspace.expenses();
          timings['preMountExpensesMs'] = uiWatch.elapsedMilliseconds;
          uiWatch.reset();
          await workspace.accounts();
          timings['preMountAccountsMs'] = uiWatch.elapsedMilliseconds;
          uiWatch.reset();
          workspace.bankReviewNotificationCount;
          timings['preMountBankNotificationsMs'] = uiWatch.elapsedMilliseconds;
          uiWatch.reset();
          workspace.invoiceDrafts();
          workspace.creditDrafts();
          timings['preMountSalesDraftsMs'] = uiWatch.elapsedMilliseconds;
        }
        uiWatch.reset();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: DemoCompany(
              child: AudytApp(
                key: ValueKey('volume-journals-$width'),
                workspace: workspace,
                showInitialSetup: false,
                initialPath: '/accounting',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        timings['journalShellMount${width.toInt()}Ms'] =
            uiWatch.elapsedMilliseconds;
        await tap(find.widgetWithText(Tab, 'Journal Review'));
        timings['journalTabOpen${width.toInt()}Ms'] =
            uiWatch.elapsedMilliseconds;
        await tap(find.byKey(const ValueKey('review-posted')));
        timings['journalPageFirstPaint${width.toInt()}Ms'] =
            uiWatch.elapsedMilliseconds;
        expect(find.byType(AccountingRecordRow), findsNWidgets(10));
        uiWatch.reset();
        await tester.enterText(
          find.byKey(const ValueKey('global-search-field')),
          'Fictional volume $lastNumber',
        );
        await tester.pumpAndSettle();
        timings['globalJournalFirstSearch${width.toInt()}Ms'] =
            uiWatch.elapsedMilliseconds;
        expect(
          find.widgetWithText(ListTile, 'Fictional volume $lastNumber'),
          findsOneWidget,
        );
        await captureUi(
          tester,
          '$transactionCount Transactions Global Journal Search ${width.toInt()}',
        );
        await tester.enterText(
          find.byKey(const ValueKey('global-search-field')),
          '',
        );
        await tester.pumpAndSettle();
        expect(find.text('1–10 of $transactionCount'), findsOneWidget);
        await captureUi(
          tester,
          '$transactionCount Transactions Journal Page ${width.toInt()}',
        );
        await tap(find.byKey(const ValueKey('journal-page-next')));
        expect(find.text('11–20 of $transactionCount'), findsOneWidget);
        await tap(find.byKey(const ValueKey('journal-page-previous')));
        final selectedJournal = workspace.database
            .readJournalPage(
              businessId: workspace.identity.businessId,
              state: JournalEntryState.posted,
              limit: 1,
            )
            .records
            .single;
        await tester.enterText(
          find.byKey(const ValueKey('journal-search')),
          selectedJournal.entry.id.value,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountingRecordRow), findsOneWidget);
        await tap(
          find.byKey(
            ValueKey('review-journal-${selectedJournal.entry.id.value}'),
          ),
        );
        expect(find.text('Posted Journal'), findsOneWidget);
        expect(find.byKey(const ValueKey('approve-journal')), findsNothing);
        await captureUi(
          tester,
          '$transactionCount Transactions Journal View ${width.toInt()}',
        );
        await tap(accountingCloseIcon().last);
        expect(_inspect(restoredPath), expectedRecoveryTables);
        expect(tester.takeException(), isNull);
      }
      expect(_inspect(restoredPath), expectedRecoveryTables);
      measurements['timings'] = timings;
      measurements['maxRssBytes'] = ProcessInfo.maxRss;
      measurements['rssAfterBytes'] = ProcessInfo.currentRss;
      measurements['independentAnnualExpectations'] = {
        for (final year in expected.keys)
          '$year': {
            'revenueMinor': expected[year]!.$1,
            'expenseMinor': expected[year]!.$2,
            'profitMinor': expected[year]!.$1 - expected[year]!.$2,
          },
      };
      measurements['archiveRestoreReopenAllTablesMatchExpectedRecovery'] = true;
      measurements['expectedRecoveryTableHashes'] = expectedRecoveryTables;
      measurements['statementSourceOmittedParsedRowsAndDigestPreserved'] = true;
      measurements['yearCrossingBillsPaymentsVouchersBankCompletionVerified'] =
          true;
      measurements['actualPayablesVoucherAndNativeFileControlsVerified'] = true;
      measurements['historicalPayablesAgeingControlComparisonVerified'] = true;
      measurements['actualBoundedJournalReviewSearchPagingAndViewVerified'] =
          true;
      measurements['nativeRelocationAndExactFileHashVerified'] = true;
      measurements['volumeLimits'] = '100000 ledger postings with 3 Bill drafts, 2 payments, 2 vouchers, 1 external image; not 100000 source options or physical files. Non-journal global/source/store/report full-list readers and in-memory archives remain explicit findings.';
      measurements['vendorProfilesHistoryAndSharedDirectoryVerified'] = true;
      measurements['damagedArchiveRejectedSourceUnchanged'] = true;
      final captureDirectory = Platform.environment['AUDYT_UI_CAPTURE_DIR'];
      if (captureDirectory != null) {
        File(
          '$captureDirectory/$transactionCount Transactions Measurements.json',
        ).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(measurements)}\n',
        );
      }
      stdout.writeln(
        '$transactionCount transaction survival measurements: ${jsonEncode(timings)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: !Platform.isMacOS,
  );
}
