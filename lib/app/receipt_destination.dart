import 'dart:convert';

import 'package:flutter/services.dart';

import 'naming_setup.dart';

Future<String> saveReceiptDestination({
  required SetupKind kind,
  required String attachmentId,
  required DateTime date,
  required String categoryCode,
  required String mimeType,
  required Uint8List bytes,
}) async {
  final filename = await documentDestinationFilename(
    kind: kind,
    date: date,
    categoryCode: categoryCode,
    mimeType: mimeType,
  );
  final path = await namingSettingsChannel.invokeMethod<String>(
    'saveDocument',
    {
      'kind': kind.id,
      'attachmentId': attachmentId,
      'year': date.year,
      'month': date.month,
      'filename': filename,
      'bytes': bytes,
    },
  );
  if (path == null || path.isEmpty) {
    throw PlatformException(
      code: 'save_failed',
      message: 'The destination file was not saved.',
    );
  }
  return path;
}

/// Resolve the saved naming owner without writing a file. Generated outputs
/// use this before committing their portable filing intent.
Future<String> documentDestinationFilename({
  required SetupKind kind,
  required DateTime date,
  required String categoryCode,
  required String mimeType,
}) async {
  final saved = await namingSettingsChannel.invokeMethod<String>('load', {
    'kind': kind.id,
  });
  if (saved == null) {
    throw StateError('Set up a folder and naming format before saving.');
  }
  final blocks = (jsonDecode(saved) as List)
      .map(
        (entry) =>
            NamingBlock.fromJson(Map<String, dynamic>.from(entry as Map)),
      )
      .toList();
  if (blocks.isEmpty || blocks.any((b) => b.type == null)) {
    throw StateError('Complete the naming format before saving.');
  }
  if (blocks.any((b) => b.type == NamingValue.category) &&
      categoryCode.trim().isEmpty) {
    throw StateError('Choose a category before saving this attachment.');
  }
  final name = namingPreview(blocks, date, categoryCode);
  if (name.trim().isEmpty ||
      name.endsWith('.') ||
      RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(name)) {
    throw StateError('The naming format must produce a valid filename.');
  }
  final extension = switch (mimeType.toLowerCase()) {
    'application/pdf' => 'pdf',
    'image/svg+xml' => 'svg',
    'image/png' => 'png',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    _ => 'jpg',
  };
  return '$name.$extension';
}
