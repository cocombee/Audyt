import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/sales/domain/estimate.dart';
import 'package:audyt/features/sales/quotation_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/accounting/data/quotation_persistence_test.dart'
    show quotationWorkspace, quotationDraft;
import '../support/accounting_test_finders.dart';
import '../support/attachment_preview_pump.dart';
import 'filed_document_version_relocation_test.dart'
    show FiledFixture, receiptImage;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  late Directory compiler;
  late String binary;
  setUpAll(() async {
    if (!Platform.isMacOS) return;
    compiler = Directory.systemTemp.createTempSync('audyt-quote-compiler-');
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
    if (Platform.isMacOS && compiler.existsSync()) {
      compiler.deleteSync(recursive: true);
    }
  });
  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'quotation attachment controls retain exact relocated historical versions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = (await tester.runAsync(
          () => FiledFixture.create(binary),
        ))!;
        addTearDown(() => tester.runAsync(fixture.close));
        final root = Directory.systemTemp.createTempSync(
          'audyt-quotation-evidence-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final (source, customer, account) = await quotationWorkspace(
          '${root.path}/source.sqlite',
        );
        final oldBytes = receiptImage(72, 133, 237),
            newBytes = receiptImage(26, 175, 135);
        final first = ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'quote-file',
            batchId: 'quote-batch',
            filename: 'Fictional Quote.png',
            mimeType: 'image/png',
            bytes: oldBytes,
          ),
        );
        final second = first.withDerivative(
          derivativeId: '${first.originalId}-derivative-edit-1',
          bytes: newBytes,
          mimeType: 'image/png',
          width: 240,
          height: 320,
          printReadyAt300Dpi: false,
        );
        expect(second.originalId, first.originalId);
        expect(second.originalBytes, first.originalBytes);
        expect(second.preferredBytes, newBytes);
        expect(second.filedSha256, isNot(first.filedSha256));
        final quote = quotationDraft(customer, account);
        final archives = <(String, Map<String, dynamic>)>[];
        final filedPaths = <String>[];
        for (final (version, attachment) in [first, second].indexed) {
          final snapshot =
              jsonDecode(jsonEncode(quote.snapshot())) as Map<String, dynamic>;
          snapshot['pricing']['attachments'] = [attachment.toJson()];
          source.saveQuotationDraft(
            Estimate.fromSnapshot(snapshot),
            expectedRevision: version,
            savedAt: DateTime.utc(2026, 9, 1, version),
          );
          final filedPath = await tester.runAsync(
            () => fixture.save(
              'invoice',
              first.originalId,
              attachment.preferredBytes,
            ),
          );
          filedPaths.add(filedPath!);
          archives.add((
            source.database.exportDataArchive(
              source.identity.businessId,
              DateTime.now(),
            ),
            tables(source),
          ));
        }
        expect(filedPaths[1], isNot(filedPaths[0]));
        expect(File(filedPaths[0]).readAsBytesSync(), first.preferredBytes);
        expect(File(filedPaths[1]).readAsBytesSync(), newBytes);
        source.dispose();
        final sourceHash = sha256
            .convert(File('${root.path}/source.sqlite').readAsBytesSync())
            .toString();
        await tester.runAsync(() => fixture.request('prepare'));
        Future<dynamic>? nativeRead;
        final requests = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async {
            if (call.method == 'readDocument') {
              requests.add((call.arguments as Map)['expectedSha256'] as String);
              nativeRead = tester.runAsync(() => fixture.channel(call));
              return await nativeRead;
            }
            return fixture.channel(call);
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            namingSettingsChannel,
            null,
          ),
        );
        // The single-line geometry requirement depends on the product font,
        // even when screenshots are disabled. Ahem is not the app's layout.
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        for (var version = 0; version < 2; version++) {
          var restored = await AccountingWorkspace.emptyRestore(
            '${root.path}/v$version.sqlite',
            archives[version].$1,
          );
          restored.dispose();
          restored = await AccountingWorkspace.open(
            '${root.path}/v$version.sqlite',
          );
          final before = tables(restored);
          expect(before, archives[version].$2);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: Scaffold(body: QuotationPage(workspace: restored)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('view-quotation-${quote.id}')));
          await tester.pumpAndSettle();
          final details = find.byKey(ValueKey('quotation-details-${quote.id}'));
          expectSingleLineText(
            tester,
            find.descendant(
              of: details,
              matching: find.text(customer.displayName),
            ),
          );
          final button = find.byKey(
            ValueKey('quotation-attachment-${quote.id}-${first.originalId}'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump();
          await nativeRead;
          await pumpDecodedAttachment(tester);
          expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
          final image = tester.widget<Image>(find.byType(Image));
          expect(
            (image.image as MemoryImage).bytes,
            version == 0 ? first.preferredBytes : newBytes,
          );
          expect(
            requests.last,
            version == 0 ? first.filedSha256 : second.filedSha256,
          );
          await captureUi(
            tester,
            'Quotation Native Evidence $version ${width.toInt()}',
          );
          await tester.tap(accountingCloseIcon().last);
          await tester.pumpAndSettle();
          await tester.tap(accountingCloseIcon().last);
          await tester.pumpAndSettle();
          expect(tables(restored), before);
          await tester.pumpWidget(const SizedBox());
          restored.dispose();
          restored = await AccountingWorkspace.open(
            '${root.path}/v$version.sqlite',
          );
          expect(tables(restored), before);
          restored.dispose();
        }
        final nativeState =
            (await tester.runAsync(() => fixture.request('inspect')))! as Map;
        expect(nativeState['pending'], false);
        expect(
          sha256
              .convert(File('${root.path}/source.sqlite').readAsBytesSync())
              .toString(),
          sourceHash,
        );
        expect(tester.takeException(), isNull);
      },
      skip: !Platform.isMacOS,
    );
  }
}
