import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/frontend_review.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/core/documents/crop_edit.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/data/accounting_database.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:audyt/features/accounting/presentation/receipt_review_dialog.dart';
import 'package:audyt/features/purchases/presentation/bills_page.dart';
import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

import '../features/accounting/data/bill_draft_persistence_test.dart'
    show setupBill, billFixture;
import '../support/accounting_test_finders.dart';
import '../support/attachment_preview_pump.dart';
import '../support/receipt_editor_actions.dart';
import 'filed_document_version_relocation_test.dart'
    show FiledFixture, receiptImage;
import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;

void main() {
  late Directory compiler;
  late String binary;
  setUpAll(() async {
    if (!Platform.isMacOS) return;
    compiler = Directory.systemTemp.createTempSync('audyt-bill-compiler-');
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
      'Bills editor files exact originals and crops; relocated history survives recovery at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = (await tester.runAsync(
          () => FiledFixture.create(binary),
        ))!;
        addTearDown(() => tester.runAsync(fixture.close));
        final root = Directory.systemTemp.createTempSync(
          'audyt-bill-evidence-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final source = await AccountingWorkspace.open(
          '${root.path}/source.sqlite',
        );
        final (vendor, account) = await setupBill(source);
        final bill = billFixture(
          source,
          vendor,
          account.account.id,
          at: DateTime.utc(2026, 9, 1),
          attachments: const [],
        );
        source.saveBillDraft(bill, expectedRevision: 0);
        final originalBytes = receiptImage(72, 133, 237);
        final originalFile = File('${root.path}/Fictional Bill.png')
          ..writeAsBytesSync(originalBytes);
        final originalHash = sha256.convert(originalBytes).toString();
        final removedFile = File('${root.path}/Fictional Unused.png')
          ..writeAsBytesSync(receiptImage(237, 85, 101));
        final savedPaths = <String>[];
        final readChecksums = <String>[];
        Future<dynamic>? nativeRead;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async {
            if (call.method == 'readDocument') {
              readChecksums.add(
                (call.arguments as Map)['expectedSha256'] as String,
              );
              nativeRead = tester.runAsync(() => fixture.channel(call));
              return await nativeRead;
            }
            // Save/setup controls already run in realAction's real I/O zone.
            // Only readDocument starts from a normal preview tap above.
            final result = await fixture.channel(call);
            if (call.method == 'saveDocument') {
              expect((call.arguments as Map)['kind'], 'expense');
              savedPaths.add(result as String);
            }
            return result;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            namingSettingsChannel,
            null,
          ),
        );
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        Future<void> mount(AccountingWorkspace workspace) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AccountingTheme.light(),
                home: Scaffold(body: BillsPage(workspace: workspace)),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        Future<void> saveDraft() async {
          await tap(find.byKey(const ValueKey('design-review')));
          await tap(find.byKey(const ValueKey('design-review')));
          expect(find.byType(FrontendFormDialog), findsNothing);
        }

        Future<void> openEditor() async {
          final view = find.byKey(const ValueKey('edit-supporting-file-0'));
          expect(tester.widget(view), isA<IconButton>());
          expect(tester.getSize(view), const Size(32, 32));
          await tester.ensureVisible(view);
          await tester.pumpAndSettle();
          await realAction(tester, () => tester.tap(view));
          await pumpDecodedAttachment(tester);
          await captureUi(tester, 'Bill Native Open Editor ${width.toInt()}');
          expect(find.byType(ReceiptReviewDialog), findsOneWidget);
        }

        Future<void> fileAndClose() async {
          final expectedWrites = savedPaths.length + 1;
          await realAction(
            tester,
            () => tester.tap(find.byKey(const ValueKey('receipt-review-save'))),
          );
          final savedDeadline = DateTime.now().add(const Duration(seconds: 10));
          final close = find.byKey(const ValueKey('receipt-review-close'));
          while ((savedPaths.length != expectedWrites ||
                  tester.widget<IconButton>(close).onPressed == null) &&
              DateTime.now().isBefore(savedDeadline)) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump();
          }
          expect(savedPaths, hasLength(expectedWrites));
          expect(tester.widget<IconButton>(close).onPressed, isNotNull);
          await realAction(tester, () => tester.tap(close), closesEditor: true);
          expect(find.text('Discard unsaved changes?'), findsNothing);
        }

        await mount(source);
        await tap(find.byKey(ValueKey('edit-bill-${bill.id}')));
        await tap(find.byKey(const ValueKey('design-field-Tax Mode')));
        await tap(find.widgetWithText(MenuItemButton, 'Tax Exclusive').last);
        final drop = tester.widget<DropTarget>(find.byType(DropTarget));
        await realAction(tester, () async {
          drop.onDragDone!(
            DropDoneDetails(
              files: [
                DropItemFile(removedFile.path),
                DropItemFile(originalFile.path),
              ],
              localPosition: Offset.zero,
              globalPosition: Offset.zero,
            ),
          );
        });
        // DesktopDrop invokes the file reader through an async-void callback.
        // Wait for the saved-file row rather than assuming it finishes within
        // realAction's short delay on a busy native test runner.
        final importDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (find.text('Fictional Bill.png').evaluate().isEmpty &&
            DateTime.now().isBefore(importDeadline)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Fictional Bill.png'), findsOneWidget);
        expect(find.text('Preview unavailable · filename only'), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('preview-supporting-file-0')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('preview-supporting-file-1')),
              )
              .onPressed,
          isNotNull,
        );
        await tap(find.byKey(const ValueKey('remove-supporting-file-0')));
        expect(find.text('Fictional Unused.png'), findsNothing);
        expect(removedFile.existsSync(), true);
        expect(find.byType(AccountingAttachmentRecordRow), findsOneWidget);
        await tester.ensureVisible(find.byType(AccountingAttachmentRecordRow));
        await tester.pumpAndSettle();
        await captureUi(tester, 'Bill Uploaded Image Row ${width.toInt()}');
        await openEditor();
        await fileAndClose();
        expect(savedPaths, hasLength(1));
        expect(File(savedPaths.single).readAsBytesSync(), originalBytes);
        await saveDraft();
        final first = source.database.readBillDraft(
          source.identity.businessId,
          bill.id,
        )!;
        expect(first.metadata.revision, 2);
        expect(first.attachments.single.originalSha256, originalHash);
        final archives = <(String, Map<String, dynamic>, ReceiptAttachment)>[
          (
            source.database.exportDataArchive(
              source.identity.businessId,
              DateTime.now(),
            ),
            tables(source),
            first.attachments.single,
          ),
        ];

        await tap(find.byKey(ValueKey('edit-bill-${bill.id}')));
        await openEditor();
        final queue = tester
            .widget<ReceiptReviewDialog>(find.byType(ReceiptReviewDialog))
            .queue;
        queue.current.cropHistory.beginResize();
        queue.current.cropHistory.updateResize(
          CropHandle.right,
          deltaX: -.25,
          deltaY: 0,
        );
        queue.current.cropHistory.endResize();
        await tester.pump();
        await realAction(
          tester,
          () => tester.tap(
            find.byKey(const ValueKey('receipt-review-apply-crop')),
          ),
        );
        await pumpDecodedAttachment(tester);
        await captureUi(tester, 'Bill Actual Crop Editor ${width.toInt()}');
        await fileAndClose();
        await saveDraft();
        final second = source.database.readBillDraft(
          source.identity.businessId,
          bill.id,
        )!;
        final edited = second.attachments.single;
        expect(second.metadata.revision, 3);
        expect(edited.originalId, first.attachments.single.originalId);
        expect(edited.originalBytes, originalBytes);
        expect(edited.originalSha256, originalHash);
        expect(edited.filedSha256, isNot(first.attachments.single.filedSha256));
        expect(raster.decodeImage(edited.preferredBytes)!.width, 180);
        expect(savedPaths, hasLength(2));
        expect(savedPaths[1], isNot(savedPaths[0]));
        expect(File(savedPaths[0]).readAsBytesSync(), originalBytes);
        expect(File(savedPaths[1]).readAsBytesSync(), edited.preferredBytes);
        expect(originalFile.readAsBytesSync(), originalBytes);
        expect(await source.journals(), isEmpty);
        archives.add((
          source.database.exportDataArchive(
            source.identity.businessId,
            DateTime.now(),
          ),
          tables(source),
          edited,
        ));
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        final sourceHash = sha256
            .convert(File('${root.path}/source.sqlite').readAsBytesSync())
            .toString();
        final prepared =
            (await tester.runAsync(() => fixture.request('prepare')))! as Map;
        expect(prepared['files'], 2);

        Future<void> preview(ReceiptAttachment expected, String name) async {
          final button = find.byKey(
            ValueKey('bill-attachment-${bill.id}-${expected.originalId}'),
          );
          await tester.ensureVisible(button);
          nativeRead = null;
          await tester.tap(button);
          await tester.pump();
          await nativeRead;
          await pumpDecodedAttachment(tester);
          expect(find.byType(AttachmentPreviewDialog), findsOneWidget);
          expect(
            (tester.widget<Image>(find.byType(Image)).image as MemoryImage)
                .bytes,
            expected.preferredBytes,
          );
          expect(readChecksums.last, expected.filedSha256);
          await captureUi(tester, '$name ${width.toInt()}');
          await tap(accountingCloseIcon().last);
        }

        for (var i = 0; i < archives.length; i++) {
          var restored = await AccountingWorkspace.emptyRestore(
            '${root.path}/v$i.sqlite',
            archives[i].$1,
          );
          restored.dispose();
          restored = await AccountingWorkspace.open('${root.path}/v$i.sqlite');
          final before = tables(restored);
          expect(before, archives[i].$2);
          expect(
            restored.database
                .readBillDraft(restored.identity.businessId, bill.id)!
                .attachments
                .single
                .originalBytes,
            isEmpty,
          );
          await mount(restored);
          await tap(find.byKey(ValueKey('view-bill-${bill.id}')));
          await preview(archives[i].$3, 'Bill Relocated Native Evidence $i');
          await tap(accountingCloseIcon().last);
          if (i == 1) {
            await tap(find.byKey(ValueKey('bill-more-${bill.id}')));
            await tap(find.byKey(ValueKey('bill-history-${bill.id}')));
            await tap(find.byKey(ValueKey('view-bill-revision-${bill.id}-2')));
            await preview(
              first.attachments.single,
              'Bill Relocated Historical Original',
            );
            await tap(accountingCloseIcon().last);
            await tap(accountingCloseIcon().last);
          }
          expect(tables(restored), before);
          await tester.pumpWidget(const SizedBox());
          restored.dispose();
          restored = await AccountingWorkspace.open('${root.path}/v$i.sqlite');
          expect(tables(restored), before);
          restored.dispose();
        }
        final state =
            (await tester.runAsync(() => fixture.request('inspect')))! as Map;
        expect(state['pending'], false);
        expect(
          (state['roots'] as Map)['expense'],
          Directory('${fixture.root.path}/Destination')
              .resolveSymbolicLinksSync(),
        );
        expect(savedPaths.every((path) => !File(path).existsSync()), true);
        expect(originalFile.readAsBytesSync(), originalBytes);
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
