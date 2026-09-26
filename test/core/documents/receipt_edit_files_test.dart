import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audyt/core/documents/receipt_edit_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleanup waits for successful destination acknowledgement', () async {
    final files = ReceiptEditFiles();
    addTearDown(files.discardAll);
    await files.update('a', Uint8List.fromList([1, 2, 3]));
    final temporary = File(files.temporaryPath('a'));
    final written = Completer<void>();
    final saving = files.save('a', (bytes) async {
      expect(bytes, [1, 2, 3]);
      await written.future;
    });
    await Future<void>.delayed(Duration.zero);
    expect(await temporary.exists(), true);
    written.complete();
    await saving;
    expect(await temporary.exists(), false);
  });
  test('save failure retains preview bytes and retry can finish', () async {
    final files = ReceiptEditFiles();
    addTearDown(files.discardAll);
    await files.update('a', Uint8List.fromList([4, 5]));
    await expectLater(files.save('a', (_) async => throw StateError('disk full')), throwsStateError);
    expect(await files.read('a'), [4, 5]);
    await files.save('a', (_) async {});
  });
  test('discard removes unsaved file without removing another receipt', () async {
    final files = ReceiptEditFiles();
    addTearDown(files.discardAll);
    await files.update('a', Uint8List.fromList([1]));
    await files.update('b', Uint8List.fromList([2]));
    final discarded = File(files.temporaryPath('a'));
    await files.discard('a');
    expect(await discarded.exists(), false);
    expect(await files.read('b'), [2]);
  });
}
