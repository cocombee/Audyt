import 'dart:convert';
import 'dart:io';

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/app/naming_setup.dart';
import 'package:audyt/app/receipt_destination.dart';
import 'package:audyt/core/documents/receipt_document.dart';
import 'package:audyt/core/ids/entity_id.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/expense_draft.dart';
import 'package:audyt/features/accounting/domain/payment_account.dart';
import 'package:audyt/features/accounting/presentation/attachment_preview_dialog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

import 'journal_workspace_integration_test.dart' show captureUi;
import 'restored_page_routes_test.dart' show tables;
import '../support/attachment_preview_pump.dart';

/// Transport only: every request starts the actual production Swift owner in a
/// new process, with real bookmarks/files and an explicitly disposable domain.
class FiledFixture {
  FiledFixture(this.binary, this.root, this.suite);
  final String binary;
  final Directory root;
  final String suite;

  static Future<FiledFixture> create(String binary) async {
    final root = Directory.systemTemp.createTempSync('audyt-filed-native-');
    final suite =
        'com.audyt.disposable-filed-versions.${EntityId.random().value}';
    File('${root.path}/.disposable-suite').writeAsStringSync(suite);
    final fixture = FiledFixture(binary, root, suite);
    try {
      await fixture.request('configure');
      return fixture;
    } catch (_) {
      await fixture.close();
      rethrow;
    }
  }

  Future<dynamic> request(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    final process = await Process.start(binary, []);
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(
      jsonEncode({
        ...args,
        'fixtureRoot': root.path,
        'suite': suite,
        'method': method,
      }),
    );
    await process.stdin.close();
    final code = await process.exitCode;
    final output = await out;
    final error = await err;
    if (code != 0) {
      throw PlatformException(code: 'native_filed_document', message: error);
    }
    return jsonDecode(output);
  }

  Future<String> save(
    String kind,
    String id,
    Uint8List bytes, {
    bool legacy = false,
  }) async => await request(legacy ? 'legacy' : 'saveDocument', {
    'kind': kind,
    'attachmentId': id,
    'year': 2026,
    'month': 9,
    'filename': 'Receipt.png',
    'bytes': base64Encode(bytes),
  }) as String;

  Future<Uint8List> read(String id, Uint8List bytes) async {
    final result = await request('readDocument', {
      'attachmentId': id,
      'expectedSha256': sha256.convert(bytes).toString(),
    }) as Map;
    return base64Decode(result['bytes'] as String);
  }

  Future<dynamic> channel(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map);
    if (args['bytes'] case final Uint8List bytes) {
      args['bytes'] = base64Encode(bytes);
    }
    final result = await request(call.method, args);
    if (call.method == 'readDocument' || call.method == 'pdfPage') {
      return {
        ...result as Map,
        'bytes': base64Decode(result['bytes'] as String),
      };
    }
    return result;
  }

  Future<void> close() async {
    // Leave the marker available until the guarded native domain is removed.
    await request('cleanup');
    root.deleteSync(recursive: true);
  }
}

Uint8List receiptImage(int red, int green, int blue) {
  final image = raster.Image(width: 240, height: 320);
  raster.fill(image, color: raster.ColorRgb8(red, green, blue));
  raster.fillRect(
    image,
    x1: 24,
    y1: 30,
    x2: 216,
    y2: 290,
    color: raster.ColorRgb8(255, 255, 255),
  );
  for (var line = 0; line < 7; line++) {
    raster.fillRect(
      image,
      x1: 44,
      y1: 64 + line * 24,
      x2: 184,
      y2: 68 + line * 24,
      color: raster.ColorRgb8(red, green, blue),
    );
  }
  return Uint8List.fromList(raster.encodePng(image));
}

RecordExpenseDraft draft(ReceiptAttachment attachment) => RecordExpenseDraft(
  amount: '12.50',
  date: '01-09-2026',
  payee: 'Fictional Version Supplier',
  paymentAccount: 'Cash',
  paymentAccountId: 'filed-fixture-cash',
  category: 'Office Supplies',
  tax: 'No Tax',
  customer: '',
  billable: false,
  dimensions: '',
  itemOrSplitDetails: '',
  notes: 'Retained source and edited receipt versions',
  attachments: [attachment],
  submissionId: 'filed-version-intake',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory compiler;
  late String binary;
  setUpAll(() async {
    if (!Platform.isMacOS) return;
    compiler = Directory.systemTemp.createTempSync('audyt-filed-compiler-');
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

  test('all four native families retain exact versions through interrupted relocation and restart', () async {
    final fixture = await FiledFixture.create(binary);
    addTearDown(fixture.close);
    final old = receiptImage(72, 133, 237), edited = receiptImage(26, 175, 135);
    final paths = <String>[];
    for (final kind in ['expense', 'invoice', 'voucher', 'claims']) {
      final id = 'version-$kind';
      final first = await fixture.save(kind, id, old, legacy: kind == 'claims');
      final second = await fixture.save(kind, id, edited);
      paths.addAll([first, second]);
      expect(second, isNot(first));
      expect(File(first).readAsBytesSync(), old);
      expect(File(second).readAsBytesSync(), edited);
      expect(await fixture.save(kind, id, edited), second);
      expect(await fixture.save(kind, id, old), first);
      expect(await fixture.read(id, old), old);
      expect(await fixture.read(id, edited), edited);
    }
    final before = await fixture.request('inspect') as Map;
    expect((before['links'] as Map).length, 12);
    expect((before['roots'] as Map).length, 4);
    await fixture.request('prepare', {'omitVersions': true});
    await expectLater(
      fixture.read('version-expense', old),
      throwsA(isA<PlatformException>()),
    );
    final rejected = await fixture.request('inspect') as Map;
    expect(rejected['roots'], before['roots']);
    expect(rejected['links'], before['links']);
    expect(rejected['pending'], true);
    expect(paths.every((path) => File(path).existsSync()), true);

    final prepared = await fixture.request('prepare') as Map;
    expect(prepared['files'], 8);
    // A newly started reader must replay durable recovery before resolving links.
    expect(await fixture.read('version-expense', edited), edited);
    final moved = await fixture.request('inspect') as Map;
    expect(moved['pending'], false);
    final destination = Directory('${fixture.root.path}/Destination')
        .resolveSymbolicLinksSync();
    for (final value in (moved['roots'] as Map).values) {
      expect(
        Directory(value as String).resolveSymbolicLinksSync(),
        destination,
      );
    }
    for (final value in (moved['links'] as Map).values) {
      final file = File((value as Map)['path'] as String);
      expect(file.resolveSymbolicLinksSync(), startsWith('$destination/'));
      expect(file.existsSync(), true);
    }
    expect(paths.any((path) => File(path).existsSync()), false);
    for (final kind in ['expense', 'invoice', 'voucher', 'claims']) {
      expect(await fixture.read('version-$kind', old), old);
      expect(await fixture.read('version-$kind', edited), edited);
    }
    await expectLater(
      fixture.request('readDocument', {
        'attachmentId': 'version-expense',
        'expectedSha256': '0' * 64,
      }),
      throwsA(isA<PlatformException>()),
    );
    final oldKey =
        'audyt.document-version.expense.version-expense.${sha256.convert(old)}';
    final oldFile = File(
      ((moved['links'] as Map)[oldKey] as Map)['path'] as String,
    );
    oldFile.writeAsBytesSync([1, 2, 3]);
    await expectLater(
      fixture.read('version-expense', old),
      throwsA(isA<PlatformException>()),
    );
    expect(await fixture.read('version-expense', edited), edited);
  }, skip: !Platform.isMacOS);

  test(
    'a sibling save finishes a pending shared-root move before filing',
    () async {
      final fixture = await FiledFixture.create(binary);
      addTearDown(fixture.close);
      final before = receiptImage(72, 133, 237);
      final after = receiptImage(26, 175, 135);
      final original = await fixture.save('invoice', 'before-move', before);
      await fixture.request('prepare');

      // This is a fresh native request, as if another document family opened
      // first after a restart while the expense relocation was still pending.
      final filed = await fixture.save('invoice', 'after-move', after);
      final state = await fixture.request('inspect') as Map;
      final destination = Directory('${fixture.root.path}/Destination')
          .resolveSymbolicLinksSync();
      expect(state['pending'], false);
      expect(
        File(filed).resolveSymbolicLinksSync(),
        startsWith('$destination/'),
      );
      expect(File(original).existsSync(), false);
      expect(await fixture.read('before-move', before), before);
      expect(await fixture.read('after-move', after), after);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'a sibling folder load resumes the shared-root move after restart',
    () async {
      final fixture = await FiledFixture.create(binary);
      addTearDown(fixture.close);
      final bytes = receiptImage(72, 133, 237);
      await fixture.save('claims', 'saved-claim', bytes);
      await fixture.request('prepare');

      final loaded = await fixture.request('loadFolder', {'kind': 'claims'});
      final destination = Directory('${fixture.root.path}/Destination')
          .resolveSymbolicLinksSync();
      expect(
        Directory(loaded as String).resolveSymbolicLinksSync(),
        destination,
      );
      expect((await fixture.request('inspect') as Map)['pending'], false);
      expect(await fixture.read('saved-claim', bytes), bytes);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'a corrupt pending move blocks a sibling save and preserves links',
    () async {
      final fixture = await FiledFixture.create(binary);
      addTearDown(fixture.close);
      final bytes = receiptImage(72, 133, 237);
      final original = await fixture.save('expense', 'saved-expense', bytes);
      final before = await fixture.request('inspect') as Map;
      await fixture.request('prepare', {'omitVersions': true});

      await expectLater(
        fixture.save('invoice', 'must-not-file', receiptImage(26, 175, 135)),
        throwsA(isA<PlatformException>()),
      );
      final after = await fixture.request('inspect') as Map;
      expect(after['pending'], true);
      expect(after['roots'], before['roots']);
      expect(after['links'], before['links']);
      expect(File(original).readAsBytesSync(), bytes);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'production File Setup Save moves four family links and survives restart',
    () async {
      final fixture = await FiledFixture.create(binary);
      addTearDown(fixture.close);
      final saved = <String, Uint8List>{};
      final oldPaths = <String>[];
      for (final kind in ['expense', 'invoice', 'voucher', 'claims']) {
        final bytes = receiptImage(72, 133, 237);
        saved['saved-$kind'] = bytes;
        oldPaths.add(await fixture.save(kind, 'saved-$kind', bytes));
      }
      final destination = '${fixture.root.path}/Destination';
      final folder = await fixture.request('commitSetup', {
        'kind': 'expense',
        'folderPath': destination,
        'year': 2026,
        'month': 9,
        'format': '[{"type":"custom","text":"Filed"}]',
      }) as String;
      expect(folder, '$destination/2026/09. September 2026');
      final state = await fixture.request('inspect') as Map;
      final canonicalDestination = Directory(destination)
          .resolveSymbolicLinksSync();
      expect(state['pending'], false);
      expect((state['roots'] as Map).values.toSet(), {canonicalDestination});
      expect(oldPaths.every((path) => !File(path).existsSync()), true);
      for (final entry in saved.entries) {
        expect(await fixture.read(entry.key, entry.value), entry.value);
      }
      for (final value in (state['links'] as Map).values) {
        expect(
          File((value as Map)['path'] as String).resolveSymbolicLinksSync(),
          startsWith('$canonicalDestination/'),
        );
      }
      expect(
        await fixture.request('load', {'kind': 'expense'}),
        '[{"type":"custom","text":"Filed"}]',
      );
    },
    skip: !Platform.isMacOS,
  );

  test(
    'File Setup rejects a stale displayed path before any folder change',
    () async {
      final fixture = await FiledFixture.create(binary);
      addTearDown(fixture.close);
      final bytes = receiptImage(72, 133, 237);
      final original = await fixture.save('expense', 'stale-path', bytes);
      final before = await fixture.request('inspect') as Map;
      await expectLater(
        fixture.request('commitSetup', {
          'kind': 'expense',
          'folderPath': '${fixture.root.path}/Source',
          'year': 2026,
          'month': 9,
          'format': '[{"type":"custom","text":"Filed"}]',
        }),
        throwsA(isA<PlatformException>()),
      );
      final after = await fixture.request('inspect') as Map;
      expect(after, before);
      expect(File(original).readAsBytesSync(), bytes);
    },
    skip: !Platform.isMacOS,
  );

  test(
    'File Setup preserves original links when a saved source file changed',
    () async {
      final fixture = await FiledFixture.create(binary);
      addTearDown(fixture.close);
      final original = await fixture.save(
        'expense',
        'changed-source',
        receiptImage(72, 133, 237),
      );
      final before = await fixture.request('inspect') as Map;
      final changed = receiptImage(26, 175, 135);
      File(original).writeAsBytesSync(changed);

      await expectLater(
        fixture.request('commitSetup', {
          'kind': 'expense',
          'folderPath': '${fixture.root.path}/Destination',
          'year': 2026,
          'month': 9,
          'format': '[{"type":"custom","text":"Filed"}]',
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(await fixture.request('inspect'), before);
      expect(File(original).readAsBytesSync(), changed);
    },
    skip: !Platform.isMacOS,
  );

  for (final width in [720.0, 1224.0]) {
    testWidgets(
      'actual SQLite old and edited archives preview matching relocated bytes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = (await tester.runAsync(
          () => FiledFixture.create(binary),
        ))!;
        addTearDown(() => tester.runAsync(fixture.close));
        final databaseRoot = Directory.systemTemp.createTempSync(
          'audyt-filed-sqlite-',
        );
        addTearDown(() => databaseRoot.deleteSync(recursive: true));
        final firstBytes = receiptImage(72, 133, 237),
            secondBytes = receiptImage(26, 175, 135);
        final first = ReceiptAttachment.queued(
          ReceiptAttachmentInput(
            originalId: 'saved-receipt',
            batchId: 'saved-batch',
            filename: 'Fictional Receipt.png',
            mimeType: 'image/png',
            bytes: firstBytes,
          ),
        );
        final second = first.withDerivative(
          derivativeId: 'saved-receipt-derivative-edit-1',
          bytes: secondBytes,
          mimeType: 'image/png',
          width: 240,
          height: 320,
          printReadyAt300Dpi: false,
        );
        Future<dynamic>? nativeRead;
        final requests = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          namingSettingsChannel,
          (call) async {
            if (call.method == 'readDocument') {
              requests.add((call.arguments as Map)['expectedSha256'] as String);
              // Start native I/O outside Flutter's simulated async zone. Await
              // this same operation before pumping the platform reply/image.
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
        Future<String> file(ReceiptAttachment attachment) =>
            saveReceiptDestination(
              kind: SetupKind.expense,
              attachmentId: attachment.originalId,
              date: DateTime(2026, 9, 1),
              categoryCode: 'OFFICE',
              mimeType: attachment.preferredMimeType,
              bytes: attachment.preferredBytes,
            );
        final oldPath = (await tester.runAsync(() => file(first)))!;
        final workspace = await AccountingWorkspace.open(
          '${databaseRoot.path}/original.sqlite',
        );
        addTearDown(workspace.dispose);
        workspace.savePaymentAccount(
          PaymentAccount.create(
            id: 'filed-fixture-cash',
            name: 'Cash',
            type: PaymentAccountType.cash,
            currencyCode: 'MYR',
          ),
        );
        final id = await workspace.saveExpenseIntake(draft(first));
        final oldTables = tables(workspace);
        final oldArchive = workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.now(),
        );
        final newPath = (await tester.runAsync(() => file(second)))!;
        expect(oldPath, isNot(newPath));
        await workspace.updateExpenseIntake(
          id: id,
          expected: draft(first),
          replacement: draft(second),
        );
        final newTables = tables(workspace);
        final newArchive = workspace.database.exportDataArchive(
          workspace.identity.businessId,
          DateTime.now(),
        );
        workspace.dispose();
        final restored = <AccountingWorkspace>[];
        addTearDown(() {
          for (final workspace in restored) {
            workspace.dispose();
          }
        });
        for (final item in [
          (oldArchive, oldTables, 'old'),
          (newArchive, newTables, 'edited'),
        ]) {
          final path = '${databaseRoot.path}/${item.$3}.sqlite';
          final imported = await AccountingWorkspace.emptyRestore(
            path,
            item.$1,
          );
          expect(tables(imported), item.$2);
          imported.dispose();
          final reopened = await AccountingWorkspace.open(path);
          expect(tables(reopened), item.$2);
          restored.add(reopened);
        }
        final attachments = <ReceiptAttachment>[
          for (final restored in restored)
            (await restored.expense(id))!.draft.attachments.single,
        ];
        expect(attachments.map((a) => a.filedSha256), [
          first.filedSha256,
          second.filedSha256,
        ]);
        expect(attachments.every((a) => a.preferredBytes.isEmpty), true);
        await tester.runAsync(() => fixture.request('prepare'));
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        for (var index = 0; index < attachments.length; index++) {
          nativeRead = null;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('workspace-capture'),
              child: MaterialApp(
                theme: AccountingTheme.light(),
                home: Scaffold(
                  body: AttachmentPreviewDialog(
                    key: ValueKey(index),
                    attachment: attachments[index],
                  ),
                ),
              ),
            ),
          );
          expect(nativeRead, isNotNull);
          await nativeRead;
          await tester.pump();
          await pumpDecodedAttachment(tester);
          final shown = tester.widget<Image>(find.byType(Image));
          expect(
            (shown.image as MemoryImage).bytes,
            index == 0 ? firstBytes : secondBytes,
          );
          expect(find.textContaining('Unable to preview'), findsNothing);
          expect(tester.takeException(), isNull);
          await captureUi(
            tester,
            'Filed SQLite ${index == 0 ? 'Original' : 'Edited'} ${width.toInt()}',
          );
        }
        expect(requests, [first.filedSha256, second.filedSha256]);
        final finalState =
            await tester.runAsync(() => fixture.request('inspect')) as Map;
        expect(finalState['pending'], false);
        expect(File(oldPath).existsSync(), false);
        expect(File(newPath).existsSync(), false);
        for (var index = 0; index < restored.length; index++) {
          expect(tables(restored[index]), index == 0 ? oldTables : newTables);
        }
      },
      skip: !Platform.isMacOS,
    );
  }
}
