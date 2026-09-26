import 'dart:io';
import 'dart:typed_data';
import 'package:audyt/core/documents/temporary_document_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save writes current bytes then deletes temporary file', () async {
    final directory = await Directory.systemTemp.createTemp('edit-test-');
    addTearDown(() => directory.delete(recursive: true));
    final edit = await TemporaryDocumentEdit.create(Uint8List.fromList([1, 2, 3]));
    expect(await edit.size(), 3);
    await edit.update(Uint8List.fromList([8, 9]));
    expect(await edit.size(), 2);
    final destination = File('${directory.path}/saved.jpg');
    await edit.saveTo(destination);
    expect(await destination.readAsBytes(), [8, 9]);
    expect(await edit.file.exists(), false);
  });
  test('failed save keeps working bytes and existing destination intact', () async {
    final directory = await Directory.systemTemp.createTemp('edit-test-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/saved.jpg');
    await destination.writeAsBytes([7]);
    final edit = await TemporaryDocumentEdit.create(Uint8List.fromList([1, 2]));
    addTearDown(edit.discard);
    await expectLater(edit.saveTo(destination), throwsA(isA<FileSystemException>()));
    expect(await edit.read(), [1, 2]);
    expect(await destination.readAsBytes(), [7]);
  });
  test('discard removes only session temporary file', () async {
    final edit = await TemporaryDocumentEdit.create(Uint8List.fromList([1]));
    await edit.discard();
    expect(await edit.file.exists(), false);
    await edit.discard();
  });
}
