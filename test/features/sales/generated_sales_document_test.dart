import 'dart:convert';
import 'dart:io';

import 'package:audyt/core/documents/generated_document.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/core/money/money.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/domain/payment_terms.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/domain/invoice.dart';
import 'package:audyt/features/sales/domain/product_catalogue.dart';
import 'package:audyt/features/sales/domain/sales_line_item.dart';
import 'package:audyt/features/sales/generated_sales_document_service.dart';
import 'package:audyt/features/sales/sales_document.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/filed_document_version_relocation_test.dart'
    show FiledFixture;
import '../../support/sales_report_fixture.dart';

class MemoryWriter implements GeneratedDocumentFileWriter {
  final versions = <String, Uint8List>{};
  bool fail = false;
  int writes = 0;
  @override
  Future<void> writeAndVerify(
    GeneratedDocumentDelivery delivery,
    ReceiptAttachment attachment,
  ) async {
    writes++;
    if (fail) throw StateError('Fictional destination unavailable');
    versions[delivery.sha256] = Uint8List.fromList(attachment.originalBytes);
  }
}

Invoice draft(
  SalesReportFixture fixture, {
  EntityId? id,
  int count = 1,
  String description = 'Corporate Video',
  List<ReceiptAttachment> attachments = const [],
  bool inclusive = false,
}) => Invoice.draft(
  id: id ?? EntityId.random(),
  customerId: fixture.customer.id,
  documentNumber: 'INV-PDF-REVIEW',
  issueDate: DateTime.utc(2026, 9, 1),
  dueDate: DateTime.utc(2026, 10, 1),
  terms: fixture.customer.paymentTerms,
  lines: [
    for (var i = 0; i < count; i++)
      SalesLineItem.category(
        id: EntityId.random(),
        categoryId: fixture.income,
        description: '$description ${i + 1}',
        quantity: SalesQuantity.fromDecimal('1.375'),
        rate: Money.fromMinor(12500, 'MYR'),
        discount: Money.fromMinor(123, 'MYR'),
        taxRatePercent: '6',
        taxInclusive: inclusive,
      ),
  ],
  attachments: attachments,
);

SalesDocumentSnapshot snapshot(SalesReportFixture f, Invoice i) =>
    SalesDocumentSnapshot.invoice(
      businessId: f.workspace.identity.businessId,
      invoice: i,
      customer: f.customer,
      preferences: f.workspace.preferences,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SalesReportFixture f;
  setUp(() async {
    f = await salesReportFixture();
  });
  tearDown(() => f.workspace.dispose());

  test('tax visibility changes Invoice and Quotation output while retaining exact tax facts', () async {
    final invoice = draft(f);
    final captures = Platform.environment['AUDYT_GENERATED_DOCUMENT_CAPTURE'];
    final signatures = <String>{};
    for (final show in [true, false]) {
      final preferences = f.workspace.preferences.change(
        'Numbering & Document Appearance',
        {'Show Tax Breakdown': show},
      );
      for (final isQuote in [false, true]) {
        final document = isQuote
            ? SalesDocumentSnapshot.quotation(
                businessId: f.workspace.identity.businessId,
                quotation: Estimate.draft(
                  id: invoice.id,
                  customerId: invoice.customerId,
                  lines: invoice.lines,
                  issueDate: invoice.issueDate,
                  validUntil: DateTime.utc(2026, 10, 1),
                  documentNumber: 'QT-TAX-VISIBILITY',
                ),
                customer: f.customer,
                preferences: preferences,
              )
            : SalesDocumentSnapshot.invoice(
                businessId: f.workspace.identity.businessId,
                invoice: invoice,
                customer: f.customer,
                preferences: preferences,
              );
        expect(document.content['showTaxBreakdown'], show);
        expect(document.content['totalMinor'], invoice.total.minorUnits);
        expect(
          (document.content['rows'] as List).single['taxMinor'],
          invoice.lines.single.tax.minorUnits,
        );
        signatures.add(document.signature);
        final filename =
            '${isQuote ? 'Quotation' : 'Invoice'} Tax ${show ? 'Shown' : 'Hidden'}.pdf';
        final pdf = await const SalesDocumentRenderer().render(
          document,
          filename: filename,
        );
        expect(ascii.decode(pdf.originalBytes.take(5).toList()), '%PDF-');
        if (captures != null) {
          Directory(captures).createSync(recursive: true);
          File('$captures/$filename').writeAsBytesSync(pdf.originalBytes);
        }
      }
    }
    expect(signatures.length, 4);
    // Older saved snapshots have no visibility key and retain their breakdown.
    expect(snapshot(f, invoice).content['showTaxBreakdown'], isTrue);
  });

  test('pricing inputs retain exact quantities, currency and tax with visible pricing columns', () async {
    for (final inclusive in [false, true]) {
      final i = draft(f, inclusive: inclusive);
      final s = snapshot(f, i);
      final row = (s.content['rows'] as List).single as Map;
      expect(row['quantityScaledUnits'], 1375);
      expect(row['quantityScale'], SalesQuantity.scale);
      expect(row['quantity'], '1.375');
      expect(row['rate'], '125.00');
      expect(s.content['showQuantity'], isTrue);
      expect(s.content['showRate'], isTrue);
      expect(row['rateMinor'], 12500);
      expect(row['discountMinor'], 123);
      expect(row['taxRatePercent'], '6');
      expect(row['taxInclusive'], inclusive);
      expect(row['totalMinor'], inclusive ? 17065 : 18089);
      expect(row['taxMinor'], inclusive ? 966 : 1024);
      expect(s.content['totalMinor'], i.total.minorUnits);
      expect(() => row['rateMinor'] = 1, throwsUnsupportedError);
      expect(() => (s.content['rows'] as List).clear(), throwsUnsupportedError);
      final restored = Invoice.fromDraftSnapshot(
        jsonDecode(jsonEncode(i.draftSnapshot())),
      );
      expect(snapshot(f, restored).signature, s.signature);
    }
  });

  test('actual A4 renderer handles many wrapped rows and outputs embedded text PDF', () async {
    final i = draft(
      f,
      count: 80,
      description: 'Fictional detailed service with enough words to wrap in the approved description column.',
    );
    final pdf = await const SalesDocumentRenderer().render(
      snapshot(f, i),
      filename: 'Invoice.pdf',
    );
    expect(ascii.decode(pdf.originalBytes.take(5).toList()), '%PDF-');
    final raw = latin1.decode(pdf.originalBytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, greaterThan(1));
    expect(raw, contains('/FontFile2'));
    expect(pdf.generated?.recordId, i.id);
    expect(
      ReceiptAttachment.fromJson(pdf.toJson()).originalBytes,
      pdf.originalBytes,
    );
    // Explicit capture runs write real renderer output for Poppler inspection.
    final capture = Platform.environment['AUDYT_GENERATED_DOCUMENT_CAPTURE'];
    if (capture != null) {
      Directory(capture).createSync(recursive: true);
      for (final long in [false, true]) {
        final data = long
            ? pdf
            : await const SalesDocumentRenderer().render(
                snapshot(f, draft(f, count: 2)),
                filename: 'Invoice.pdf',
              );
        File('$capture/Generated Invoice ${long ? 'Pagination' : 'Review'}.pdf')
            .writeAsBytesSync(data.originalBytes);
      }
    }
  });

  test('edit, Remove and repeated Save keep one generated PDF and preserve manual originals', () async {
    final writer = MemoryWriter();
    final service = GeneratedSalesDocumentService(writer: writer);
    final invoice = draft(f);
    Future<GeneratedSalesDocumentSaveResult> save(Invoice i, int rev) =>
        service.saveInvoice(
          workspace: f.workspace,
          invoice: i,
          customer: f.customer,
          filename: 'Invoice.pdf',
          expectedRevision: rev,
          savedAt: DateTime.utc(2026, 9, rev + 1),
        );
    expect((await save(invoice, 0)).isFiled, isTrue);
    Invoice saved() => f.workspace.invoiceDrafts().single.invoice;
    final first = saved().attachments.single;
    final manual = ReceiptAttachment.queued(
      ReceiptAttachmentInput(
        originalId: 'manual-original',
        batchId: 'manual-batch',
        filename: 'Manual.pdf',
        mimeType: 'application/pdf',
        bytes: first.originalBytes,
      ),
    );
    expect((await save(saved().withAttachments([manual]), 1)).revision, 2);
    final second = saved().attachments.singleWhere((a) => a.isGenerated);
    expect(second.originalSha256, first.originalSha256);
    expect(
      saved().attachments.where((a) => !a.isGenerated).single.toJson(),
      manual.toJson(),
    );
    expect((await save(saved(), 2)).revision, 3);
    expect(saved().attachments.where((a) => a.isGenerated), hasLength(1));
    expect(writer.versions, hasLength(1));
    final edited = draft(
      f,
      id: invoice.id,
      description: 'Edited service',
      attachments: saved().attachments,
    );
    expect((await save(edited, 3)).revision, 4);
    expect(
      saved().attachments.singleWhere((a) => a.isGenerated).originalSha256,
      isNot(first.originalSha256),
    );
    final history = f.workspace.database.generatedDocumentDeliveries(
      f.workspace.identity.businessId,
    );
    expect(history, hasLength(4));
    expect(
      f.workspace.database
          .generatedDocumentAttachment(history.first)
          .originalSha256,
      first.originalSha256,
    );
    expect(
      history.every((d) => d.status == GeneratedDocumentDeliveryStatus.filed),
      isTrue,
    );
  });

  test('filing failure leaves committed intent; retry uses exact history and survives reopen/restore', () async {
    final root = Directory.systemTemp.createTempSync(
      'audyt-generated-persistence-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final fixture = await salesReportFixture(path: '${root.path}/books.sqlite');
    var w = fixture.workspace;
    addTearDown(() => w.dispose());
    final writer = MemoryWriter()..fail = true;
    final service = GeneratedSalesDocumentService(writer: writer);
    final i = draft(fixture);
    final result = await service.saveInvoice(
      workspace: w,
      invoice: i,
      customer: fixture.customer,
      filename: 'Invoice.pdf',
      expectedRevision: 0,
      savedAt: DateTime.utc(2026, 9, 2),
    );
    expect(result.revision, 1);
    expect(result.isFiled, isFalse);
    expect(w.invoiceDrafts().single.invoice.attachments, hasLength(1));
    final company = w.identity.businessId;
    final before = w.database.generatedDocumentDeliveries(company).single;
    expect(before.status, GeneratedDocumentDeliveryStatus.failed);
    w.dispose();
    w = await AccountingWorkspace.open('${root.path}/books.sqlite');
    final reopened = w.database.generatedDocumentDeliveries(company).single;
    expect(reopened.sha256, before.sha256);
    writer.fail = false;
    expect(
      await service.retry(
        workspace: w,
        kind: GeneratedDocumentKind.invoice,
        recordId: i.id,
        revision: 1,
      ),
      isNull,
    );
    expect(
      writer.versions[before.sha256],
      w.database.generatedDocumentAttachment(before).originalBytes,
    );
    final archive = w.database.exportDataArchive(
      company,
      DateTime.utc(2026, 9, 3),
    );
    final restored = await AccountingWorkspace.emptyRestore(
      '${root.path}/restored.sqlite',
      archive,
    );
    addTearDown(restored.dispose);
    final recovered = restored.database
        .generatedDocumentDeliveries(company)
        .single;
    expect(recovered.status, GeneratedDocumentDeliveryStatus.filed);
    expect(
      restored
          .invoiceDrafts()
          .single
          .invoice
          .attachments
          .single
          .generated
          ?.recordId,
      i.id,
    );
    // Data-only archives preserve ownership/hash and intentionally omit bytes.
    expect(
      () => restored.database.generatedDocumentAttachment(recovered),
      throwsStateError,
    );
  });

  test(
    'stale revisions and foreign generated ownership cannot commit or file',
    () async {
      final writer = MemoryWriter();
      final service = GeneratedSalesDocumentService(writer: writer);
      final i = draft(f);
      await service.saveInvoice(
        workspace: f.workspace,
        invoice: i,
        customer: f.customer,
        filename: 'Invoice.pdf',
        expectedRevision: 0,
        savedAt: DateTime.utc(2026, 9, 1),
      );
      final altered = draft(f, id: i.id, description: 'Stale edit');
      await expectLater(
        service.saveInvoice(
          workspace: f.workspace,
          invoice: altered,
          customer: f.customer,
          filename: 'Invoice.pdf',
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 2),
        ),
        throwsStateError,
      );
      expect(writer.writes, 1);
      expect(
        f.workspace.database.generatedDocumentDeliveries(
          f.workspace.identity.businessId,
        ),
        hasLength(1),
      );
      final owned = f.workspace
          .invoiceDrafts()
          .single
          .invoice
          .attachments
          .single;
      await expectLater(
        service.saveInvoice(
          workspace: f.workspace,
          invoice: draft(f, attachments: [owned]),
          customer: f.customer,
          filename: 'Other.pdf',
          expectedRevision: 0,
          savedAt: DateTime.utc(2026, 9, 2),
        ),
        throwsStateError,
      );
      expect(f.workspace.invoiceDrafts(), hasLength(1));
      expect(writer.writes, 1);
    },
  );

  test(
    'quotation output stays with quotation when converting to invoice',
    () async {
      final i = draft(f);
      final q = Estimate.draft(
        id: i.id,
        customerId: i.customerId,
        lines: i.lines,
        issueDate: i.issueDate,
        validUntil: DateTime.utc(2026, 10, 1),
        documentNumber: 'QT-PDF-REVIEW',
        taxMode: 'Exclusive',
      );
      final result = await GeneratedSalesDocumentService(writer: MemoryWriter())
          .saveQuotation(
            workspace: f.workspace,
            quotation: q,
            customer: f.customer,
            filename: 'Quotation.pdf',
            expectedRevision: 0,
            savedAt: DateTime.utc(2026, 9, 2),
          );
      expect(result.isFiled, isTrue);
      final saved = f.workspace.quotations().single.quotation;
      expect(
        saved.attachments.single.generated?.kind,
        GeneratedDocumentKind.quotation,
      );
      final capture = Platform.environment['AUDYT_GENERATED_DOCUMENT_CAPTURE'];
      if (capture != null) {
        File('$capture/Generated Quotation Review.pdf')
            .writeAsBytesSync(saved.attachments.single.originalBytes);
      }
      final converted = saved.send().accept().convertToInvoice(
        invoiceId: EntityId.random(),
        invoiceLineIds: {
          for (final line in saved.lines) line.id: EntityId.random(),
        },
        issueDate: DateTime.utc(2026, 9, 3),
        dueDate: DateTime.utc(2026, 10, 3),
      );
      expect(converted.estimate.attachments, saved.attachments);
      expect(converted.invoice.attachments, isEmpty);
    },
  );

  group('native generated PDF delivery', () {
    late Directory compiler;
    late String binary;
    setUpAll(() async {
      if (!Platform.isMacOS) return;
      compiler = Directory.systemTemp.createTempSync(
        'audyt-generated-compiler-',
      );
      binary = '${compiler.path}/filed-document-bridge';
      final result = await Process.run('xcrun', [
        'swiftc',
        '-module-cache-path',
        '${compiler.path}/ModuleCache',
        '${Directory.current.path}/macos/Runner/ReceiptDestinationWriter.swift',
        '${Directory.current.path}/macos/Runner/DocumentPreviewRenderer.swift',
        '${Directory.current.path}/test/native/filed_document_versions/main.swift',
        '-o',
        binary,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
    tearDownAll(() {
      if (Platform.isMacOS) compiler.deleteSync(recursive: true);
    });

    test('missing file recreates, naming changes apply, altered bytes reject and manual missing stays unavailable', () async {
      final native = await FiledFixture.create(binary);
      addTearDown(native.close);
      const channel = MethodChannel('audyt/naming-settings');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, native.channel);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final i = draft(f);
      final service = GeneratedSalesDocumentService();
      Future<GeneratedSalesDocumentSaveResult> save(int rev, String filename) =>
          service.saveInvoice(
            workspace: f.workspace,
            invoice: rev == 0 ? i : f.workspace.invoiceDrafts().single.invoice,
            customer: f.customer,
            filename: filename,
            expectedRevision: rev,
            savedAt: DateTime.utc(2026, 9, rev + 1),
          );
      expect((await save(0, 'Invoice.pdf')).isFiled, isTrue);
      final filed = native.root
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('/Invoice.pdf'));
      filed.deleteSync();
      expect((await save(1, 'Invoice.pdf')).isFiled, isTrue);
      expect(filed.existsSync(), isTrue);
      expect((await save(2, 'Renamed Invoice.pdf')).isFiled, isTrue);
      final renamed = native.root
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('/Renamed Invoice.pdf'));
      expect(filed.readAsBytesSync(), renamed.readAsBytesSync());
      renamed.writeAsStringSync('tampered');
      expect((await save(3, 'Renamed Invoice.pdf')).isFiled, isFalse);
      expect(renamed.readAsStringSync(), 'tampered');
      final bytes = filed.readAsBytesSync();
      final manualPath = await native.request('saveDocument', {
        'kind': 'invoice',
        'attachmentId': 'manual-pdf',
        'year': 2026,
        'month': 9,
        'filename': 'Manual.pdf',
        'bytes': base64Encode(bytes),
      }) as String;
      File(manualPath).deleteSync();
      await expectLater(
        native.request('saveDocument', {
          'kind': 'invoice',
          'attachmentId': 'manual-pdf',
          'year': 2026,
          'month': 9,
          'filename': 'Manual.pdf',
          'bytes': base64Encode(bytes),
        }),
        throwsA(isA<PlatformException>()),
      );
    }, skip: !Platform.isMacOS);

    test(
      'PDF optional pricing fits large values and omits single-page counter',
      () async {
        final native = await FiledFixture.create(binary);
        addTearDown(native.close);
        for (final mode in ['Hidden', 'Quantity', 'Rate', 'Large']) {
          final quantity = SalesQuantity.fromDecimal(
            mode == 'Large' ? '1234.567' : '1',
          );
          final invoice = Invoice.draft(
            id: EntityId.random(),
            customerId: f.customer.id,
            issueDate: DateTime.utc(2026, 10, 1),
            dueDate: DateTime.utc(2026, 10, 31),
            lines: [
              SalesLineItem.category(
                id: EntityId.random(),
                categoryId: f.income,
                description: 'First paragraph keeps every word.\nSecond paragraph retains its ending.',
                quantity: quantity,
                rate: Money.fromMinor(mode == 'Large' ? 1234567 : 12500, 'MYR'),
                rateEnabled: mode == 'Rate' || mode == 'Large',
                manualAmount: mode == 'Hidden' || mode == 'Quantity'
                    ? Money.fromMinor(12500, 'MYR')
                    : null,
                catalogue: CatalogueLineSnapshot(
                  itemId: EntityId.random(),
                  itemName: 'Corporate Video And Event Photography',
                  categoryId: f.income,
                  categoryName: 'Filming',
                  itemRevision: 1,
                ),
              ),
            ],
            terms: PaymentTerms.netDays(30),
          );
          final preferences = f.workspace.preferences.change(
            'Sales Preferences',
            {
              'Show Quantity': mode == 'Quantity',
              'Show Rate': mode == 'Rate' || mode == 'Large',
            },
          );
          final doc = SalesDocumentSnapshot.invoice(
            businessId: f.workspace.identity.businessId,
            invoice: invoice,
            customer: f.customer,
            preferences: preferences,
          );
          final attachment = await const SalesDocumentRenderer().render(
            doc,
            filename: '$mode.pdf',
          );
          final pages = (await native.request('inspectPdf', {
            'bytes': base64Encode(attachment.originalBytes),
          }) as List).cast<Map>();
          expect(pages.length, 1);
          final text = pages.single['text'] as String;
          expect(text, isNot(contains('1/1')));
          expect(text.contains('Quantity'), mode != 'Hidden');
          expect(text.contains('Rate (RM)'), mode == 'Rate' || mode == 'Large');
          expect(
            text.replaceAll(RegExp(r'\s+'), ' '),
            contains('retains its ending.'),
          );
          if (mode == 'Large') {
            expect(text, contains('1234.567'));
            expect(text, contains('12,345.67'));
          }
          final capture = Platform.environment['AUDYT_PAYMENT_LAYOUT_CAPTURE'];
          if (capture != null && mode == 'Large') {
            File('$capture/Updated Pricing Large.pdf')
                .writeAsBytesSync(attachment.originalBytes);
          }
        }
      },
      skip: !Platform.isMacOS,
    );

    test(
      'Custom replaces preset and Memo with one hanging-list payment block',
      () async {
        final native = await FiledFixture.create(binary);
        addTearDown(native.close);
        final invoice = Invoice.draft(
          id: EntityId.random(),
          customerId: f.customer.id,
          issueDate: DateTime.utc(2026, 9, 1),
          dueDate: DateTime.utc(2026, 10, 1),
          lines: draft(f).lines,
          terms: PaymentTerms.custom(
            '1. First custom instalment after delivery.\n'
            '2. Balance after acceptance.\n- Keep the signed handover.',
          ),
          memo: 'Inactive saved Memo must not stack.',
        );
        final attachment = await const SalesDocumentRenderer().render(
          snapshot(f, invoice),
          filename: 'Custom.pdf',
        );
        final pages = (await native.request('inspectPdf', {
          'bytes': base64Encode(attachment.originalBytes),
        }) as List).cast<Map>();
        final text = pages.map((p) => p['text'] as String).join('\n');
        expect(text, contains('1. First custom instalment'));
        expect(text, contains('2. Balance after acceptance'));
        expect(text, contains('- Keep the signed handover'));
        expect(text, isNot(contains('Payment terms:')));
        expect(text, isNot(contains('Net 30')));
        expect(text, isNot(contains('Inactive saved Memo')));
      },
      skip: !Platform.isMacOS,
    );

    test('many items and a page-tall description preserve rows, final details and every page number', () async {
      final native = await FiledFixture.create(binary);
      addTearDown(native.close);
      for (final scenario in ['Many Items', 'Long Description', 'Quotation']) {
        final count = scenario == 'Long Description' ? 1 : 48;
        final lines = [
          for (var n = 1; n <= count; n++)
            SalesLineItem.category(
              id: EntityId.random(),
              categoryId: f.income,
              description:
                  'BEGIN$n ${List.filled(scenario == 'Long Description' ? 400 : 5, 'Filming preparation includes lighting sound interviews and final delivery.').join(' ')} END$n',
              quantity: SalesQuantity.fromInt(1),
              rate: Money.fromMinor(12500, 'MYR'),
              catalogue: CatalogueLineSnapshot(
                itemId: EntityId.random(),
                itemName: n.isEven ? 'Event Photography' : 'Corporate Video',
                categoryId: EntityId.random(),
                categoryName: 'Video',
                itemRevision: 1,
              ),
            ),
        ];
        final invoice = Invoice.draft(
          id: EntityId.random(),
          customerId: f.customer.id,
          documentNumber: scenario == 'Quotation'
              ? 'QT-OVERFLOW'
              : 'INV-OVERFLOW',
          issueDate: DateTime.utc(2026, 9, 1),
          dueDate: DateTime.utc(2026, 10, 1),
          lines: lines,
        );
        final doc = scenario == 'Quotation'
            ? SalesDocumentSnapshot.quotation(
                businessId: f.workspace.identity.businessId,
                quotation: Estimate.draft(
                  id: invoice.id,
                  customerId: invoice.customerId,
                  documentNumber: invoice.documentNumber,
                  issueDate: invoice.issueDate,
                  validUntil: invoice.dueDate,
                  lines: lines,
                ),
                customer: f.customer,
                preferences: f.workspace.preferences,
              )
            : snapshot(f, invoice);
        final attachment = await const SalesDocumentRenderer().render(
          doc,
          filename: '$scenario.pdf',
        );
        final pages = (await native.request('inspectPdf', {
          'bytes': base64Encode(attachment.originalBytes),
        }) as List).cast<Map>();
        expect(pages.length, greaterThan(1));
        final detail = scenario == 'Quotation'
            ? 'Quotation Details'
            : 'Payment Information';
        for (final (index, page) in pages.indexed) {
          final text = page['text'] as String;
          expect(text, contains('${index + 1}/${pages.length}'));
          expect(text, contains('Item'));
          expect(text, contains('No.'));
          expect(text.contains(detail), index == pages.length - 1);
          expect((page['width'] as num).toDouble(), closeTo(595.28, .1));
          expect((page['height'] as num).toDouble(), closeTo(841.89, .1));
          expect(text, isNot(contains('We look forward')));
        }
        for (var n = 1; n <= count; n++) {
          final begin = pages.indexWhere(
            (p) => RegExp('BEGIN$n(?![0-9])').hasMatch(p['text'] as String),
          );
          final end = pages.indexWhere(
            (p) => RegExp('END$n(?![0-9])').hasMatch(p['text'] as String),
          );
          expect(
            begin,
            greaterThanOrEqualTo(0),
            reason: '$scenario item $n start',
          );
          expect(
            end,
            greaterThanOrEqualTo(begin),
            reason: '$scenario item $n end',
          );
          if (scenario != 'Long Description') {
            expect(end, begin, reason: 'A row that fits stays intact.');
          }
        }
        expect(pages.last['text'], contains('END$count'));
        expect(doc.content['currency'], 'MYR');
        final storedTotal = doc.content['total'] as String;
        expect(storedTotal, startsWith('MYR '));
        expect(pages.last['text'], contains('RM ${storedTotal.substring(4)}'));
        expect(pages.last['text'], contains('Amount (RM)'));
        final capture = Platform.environment['AUDYT_PDF_OVERFLOW_CAPTURE'];
        if (capture != null) {
          Directory(capture).createSync(recursive: true);
          File('$capture/PDF $scenario Pagination.pdf')
              .writeAsBytesSync(attachment.originalBytes);
        }
      }
    }, skip: !Platform.isMacOS);
  });
}
