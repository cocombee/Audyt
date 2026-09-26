import 'dart:io';
import 'dart:typed_data';

/// One editing session. Never deletes or overwrites the uploaded source.
final class TemporaryDocumentEdit {
  TemporaryDocumentEdit._(this._directory, this.file);
  final Directory _directory;
  final File file;
  bool _closed = false;

  static Future<TemporaryDocumentEdit> create(Uint8List bytes) async {
    final directory = await Directory.systemTemp.createTemp('audyt-edit-');
    final file = File('${directory.path}/working');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return TemporaryDocumentEdit._(directory, file);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<Uint8List> read() => file.readAsBytes();
  Future<int> size() => file.length();

  Future<void> update(Uint8List bytes) async {
    if (_closed) throw StateError('The edit session is closed.');
    final next = File('${_directory.path}/next');
    await next.writeAsBytes(bytes, flush: true);
    await next.rename(file.path);
  }

  /// Use a new destination path; replacement authorization belongs to the UI.
  Future<void> saveTo(File destination) async {
    if (_closed) throw StateError('The edit session is closed.');
    if (await destination.exists()) {
      throw FileSystemException('Destination already exists', destination.path);
    }
    final bytes = await read();
    // Create exclusively: an existing destination must never be overwritten.
    await destination.create(exclusive: true);
    try {
      await destination.writeAsBytes(bytes, flush: true);
      final saved = await destination.readAsBytes();
      if (saved.length != bytes.length) throw const FileSystemException('Incomplete save');
      for (var i = 0; i < bytes.length; i++) {
        if (saved[i] != bytes[i]) throw const FileSystemException('Save verification failed');
      }
    } catch (_) {
      await destination.delete();
      rethrow;
    }
    await discard();
  }

  Future<void> discard() async {
    if (_closed) return;
    if (await _directory.exists()) await _directory.delete(recursive: true);
    _closed = true;
  }
}
