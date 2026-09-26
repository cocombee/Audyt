import 'dart:typed_data';
import 'temporary_document_edit.dart';

/// Temporary pixels owned by one open receipt editor, never by the source file.
final class ReceiptEditFiles {
  final Map<String, TemporaryDocumentEdit> _files = {};

  Future<void> update(String id, Uint8List bytes) async {
    final existing = _files[id];
    if (existing == null) {
      _files[id] = await TemporaryDocumentEdit.create(bytes);
    } else {
      await existing.update(bytes);
    }
  }

  Future<Uint8List> read(String id) => _file(id).read();
  String temporaryPath(String id) => _file(id).file.path;

  Future<void> save(String id, Future<void> Function(Uint8List) writer) async {
    final file = _file(id);
    // A failed or cancelled destination write leaves the working file intact.
    await writer(await file.read());
    await file.discard();
    _files.remove(id);
  }

  Future<void> discard(String id) async {
    final file = _files[id];
    if (file == null) return;
    await file.discard();
    _files.remove(id);
  }

  Future<void> discardAll() async {
    for (final id in _files.keys.toList()) { await discard(id); }
  }

  TemporaryDocumentEdit _file(String id) =>
      _files[id] ?? (throw StateError('No temporary receipt for $id'));
}
