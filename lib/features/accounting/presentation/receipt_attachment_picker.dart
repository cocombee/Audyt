import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

final class PickedExpenseAttachment {
  const PickedExpenseAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.path,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String? path;
}

typedef ExpenseAttachmentsPicker =
    Future<List<PickedExpenseAttachment>> Function(BuildContext context);

typedef NativeExpenseFilePicker =
    Future<List<PickedExpenseAttachment>> Function({
      required bool allowMultiple,
    });

final class NativeExpenseAttachmentPicker {
  const NativeExpenseAttachmentPicker({this.filePicker});

  static const supportedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'heic',
    'heif',
    'pdf',
    'doc',
    'docx',
  ];

  static String mimeTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  final NativeExpenseFilePicker? filePicker;
  static String? _lastDirectory;

  Future<List<PickedExpenseAttachment>> pick(BuildContext context) {
    final picker = filePicker;
    if (picker != null) return picker(allowMultiple: true);
    return _pickWithFilePicker();
  }

  Future<List<PickedExpenseAttachment>> _pickWithFilePicker() async {
    final files = await FilePicker.pickFiles(
      // file_picker exposes this compatibility flag for multi-file dialogs.
      // ignore: deprecated_member_use
      allowMultiple: true,
      dialogTitle: 'Choose receipt or document',
      initialDirectory: _lastDirectory,
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    final path = files.isEmpty ? null : files.last.path;
    if (path != null) _lastDirectory = File(path).parent.path;
    final selected = <PickedExpenseAttachment>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      selected.add(
        PickedExpenseAttachment(
          name: file.name,
          mimeType: mimeTypeForFilename(file.name),
          bytes: bytes,
          path: file.path,
        ),
      );
    }
    return selected;
  }
}
