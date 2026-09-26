import 'dart:collection';
import 'dart:io';

import 'package:audyt/core/ids/entity_id.dart';
import 'package:crypto/crypto.dart';

import 'folder_relocation.dart';

final class RelocationResult {
  const RelocationResult({
    required this.movedFiles,
    required this.verifiedFiles,
    required this.sha256ByRelativePath,
  });

  final int movedFiles;
  final int verifiedFiles;
  final Map<String, String> sha256ByRelativePath;
}

final class DocumentFilingConflict implements Exception {
  const DocumentFilingConflict({
    required this.relativePath,
    required this.reason,
  });

  final String relativePath;
  final String reason;

  @override
  String toString() => 'Document filing collision at $relativePath: $reason';
}

final class PaidDocumentMove {
  const PaidDocumentMove({
    required this.documentId,
    required this.sourceRelativePath,
    required this.destinationRelativePath,
    required this.expectedSha256,
    required this.metadataJson,
  });

  final EntityId documentId;
  final String sourceRelativePath;
  final String destinationRelativePath;
  final String expectedSha256;
  final String metadataJson;
}

final class PaidDocumentMoveResult {
  const PaidDocumentMoveResult({required this.sha256ByDocumentId});

  final Map<EntityId, String> sha256ByDocumentId;
}

final class LocalFolderDocumentAdapter {
  Future<RelocationResult> move(LocalFolderRelocationPlan plan) async {
    await plan.destinationRoot.create(recursive: true);
    final hashes = <String, String>{};
    var verifiedFiles = 0;

    for (final item in plan.items) {
      final source = File(item.sourcePath);
      final destination = File(item.destinationPath);
      if (!source.existsSync()) {
        throw FileSystemException('Source file is missing', source.path);
      }

      await destination.parent.create(recursive: true);
      final sourceHash = await _sha256(source);
      if (destination.existsSync()) {
        final destinationHash = await _sha256(destination);
        if (destinationHash != sourceHash) {
          throw FileSystemException(
            'Destination collision contains different content',
            destination.path,
          );
        }
      } else {
        final partial = File('${destination.path}.audyt-partial');
        if (partial.existsSync()) {
          await partial.delete();
        }
        await source.copy(partial.path);
        final partialHash = await _sha256(partial);
        if (partialHash != sourceHash) {
          await partial.delete();
          throw FileSystemException(
            'Copied content failed hash verification',
            destination.path,
          );
        }
        await partial.rename(destination.path);
      }

      hashes[item.relativePath] = sourceHash;
      verifiedFiles += 1;
    }

    for (final item in plan.items.reversed) {
      final source = File(item.sourcePath);
      if (source.existsSync()) {
        await source.delete();
      }
    }
    await _removeEmptyDirectories(plan.sourceRoot);

    return RelocationResult(
      movedFiles: plan.items.length,
      verifiedFiles: verifiedFiles,
      sha256ByRelativePath: UnmodifiableMapView(hashes),
    );
  }

  /// Copies, stamps, verifies, and then removes paid-claim source documents.
  ///
  /// All source files remain in place until every destination file and its
  /// structured metadata sidecar has passed verification. Existing matching
  /// destinations are treated as an idempotent retry; any other destination
  /// occupant is a typed collision and is never overwritten.
  Future<PaidDocumentMoveResult> movePaidDocuments({
    required Directory managedRoot,
    required Iterable<PaidDocumentMove> items,
  }) async {
    final moves = List<PaidDocumentMove>.unmodifiable(items);
    final root = managedRoot.absolute;
    await root.create(recursive: true);
    _validateManagedRoot(root);

    final destinationPaths = <String>{};
    final prepared = <_PreparedPaidMove>[];
    for (final item in moves) {
      _validateRelativePath(item.sourceRelativePath);
      _validateRelativePath(item.destinationRelativePath);
      if (item.metadataJson.trim().isEmpty) {
        throw ArgumentError.value(
          item.metadataJson,
          'metadataJson',
          'Paid document metadata is required.',
        );
      }
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(item.expectedSha256)) {
        throw ArgumentError.value(
          item.expectedSha256,
          'expectedSha256',
          'Document hash is invalid.',
        );
      }

      final source = _file(root, item.sourceRelativePath);
      final destination = _file(root, item.destinationRelativePath);
      if (source.absolute.path == destination.absolute.path) {
        throw const DocumentFilingConflict(
          relativePath: '',
          reason: 'A paid document destination must differ from its source.',
        );
      }
      if (!destinationPaths.add(destination.absolute.path)) {
        throw DocumentFilingConflict(
          relativePath: item.destinationRelativePath,
          reason: 'Two paid documents resolve to the same destination.',
        );
      }

      final metadata = _file(
        root,
        metadataRelativePath(item.destinationRelativePath),
      );
      if (source.existsSync()) {
        if (source.statSync().type != FileSystemEntityType.file) {
          throw FileSystemException(
            'Source document is not a file',
            source.path,
          );
        }
        final sourceHash = await _sha256(source);
        if (sourceHash != item.expectedSha256.toLowerCase()) {
          throw FileSystemException(
            'Source document hash changed',
            source.path,
          );
        }
      }

      final destinationExists = destination.existsSync();
      final metadataExists = metadata.existsSync();
      var alreadyPresent = false;
      if (destinationExists || metadataExists) {
        if (!destinationExists || !metadataExists) {
          throw DocumentFilingConflict(
            relativePath: item.destinationRelativePath,
            reason: 'A partial or unstructured destination already exists.',
          );
        }
        if (destination.statSync().type != FileSystemEntityType.file ||
            metadata.statSync().type != FileSystemEntityType.file) {
          throw DocumentFilingConflict(
            relativePath: item.destinationRelativePath,
            reason: 'The destination or its metadata sidecar is not a file.',
          );
        }
        final destinationHash = await _sha256(destination);
        final metadataText = await metadata.readAsString();
        if (destinationHash != item.expectedSha256.toLowerCase() ||
            metadataText != item.metadataJson) {
          throw DocumentFilingConflict(
            relativePath: item.destinationRelativePath,
            reason: 'The destination belongs to different content or metadata.',
          );
        }
        alreadyPresent = true;
      }

      if (!source.existsSync() && !alreadyPresent) {
        throw FileSystemException('Source document is missing', source.path);
      }
      prepared.add(
        _PreparedPaidMove(
          item: item,
          source: source,
          destination: destination,
          metadata: metadata,
          alreadyPresent: alreadyPresent,
        ),
      );
    }

    final hashes = <EntityId, String>{};
    final createdDestinations = <File>[];
    final createdMetadata = <File>[];
    try {
      for (final move in prepared) {
        if (!move.alreadyPresent) {
          await move.destination.parent.create(recursive: true);
          final partial = File('${move.destination.path}.audyt-partial');
          if (partial.existsSync()) await partial.delete();
          await move.source.copy(partial.path);
          final partialHash = await _sha256(partial);
          if (partialHash != move.item.expectedSha256.toLowerCase()) {
            await partial.delete();
            throw FileSystemException(
              'Copied content failed hash verification',
              move.destination.path,
            );
          }
          await partial.rename(move.destination.path);
          createdDestinations.add(move.destination);

          final metadataPartial = File(
            '${move.metadata.path}.audyt-partial',
          );
          if (metadataPartial.existsSync()) await metadataPartial.delete();
          await metadataPartial.writeAsString(
            move.item.metadataJson,
            flush: true,
          );
          if (await metadataPartial.readAsString() != move.item.metadataJson) {
            await metadataPartial.delete();
            throw FileSystemException(
              'Paid metadata failed verification',
              move.metadata.path,
            );
          }
          await metadataPartial.rename(move.metadata.path);
          createdMetadata.add(move.metadata);
        }
        hashes[move.item.documentId] = move.item.expectedSha256.toLowerCase();
      }

      for (final move in prepared) {
        if (move.source.existsSync()) {
          final currentHash = await _sha256(move.source);
          if (currentHash != move.item.expectedSha256.toLowerCase()) {
            throw FileSystemException(
              'Source document changed before finalization',
              move.source.path,
            );
          }
        }
      }
      for (final move in prepared.reversed) {
        if (move.source.existsSync()) await move.source.delete();
        await _removeEmptyAncestors(move.source.parent, root);
      }
    } catch (_) {
      for (final file in createdMetadata) {
        if (file.existsSync()) await file.delete();
      }
      for (final file in createdDestinations) {
        if (file.existsSync()) await file.delete();
      }
      rethrow;
    }

    return PaidDocumentMoveResult(
      sha256ByDocumentId: UnmodifiableMapView(hashes),
    );
  }

  static String metadataRelativePath(String destinationRelativePath) {
    _validateRelativePath(destinationRelativePath);
    final separator = destinationRelativePath.lastIndexOf('/');
    final parent = separator == -1
        ? ''
        : destinationRelativePath.substring(0, separator);
    final filename = separator == -1
        ? destinationRelativePath
        : destinationRelativePath.substring(separator + 1);
    final metadataName = '.$filename.audyt.json';
    return parent.isEmpty ? metadataName : '$parent/$metadataName';
  }

  Future<String> _sha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<void> _removeEmptyDirectories(Directory root) async {
    final directories =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort(
            (left, right) => right.path.length.compareTo(left.path.length),
          );
    for (final directory in directories) {
      if (directory.existsSync() && directory.listSync().isEmpty) {
        await directory.delete();
      }
    }
    if (root.existsSync() && root.listSync().isEmpty) {
      await root.delete();
    }
  }

  void _validateManagedRoot(Directory root) {
    if (root.statSync().type != FileSystemEntityType.directory) {
      throw ArgumentError.value(
        root.path,
        'managedRoot',
        'Root is not a directory.',
      );
    }
  }

  File _file(Directory root, String relativePath) => File(
    '${root.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );

  static void _validateRelativePath(String path) {
    final segments = path.split('/');
    if (path.trim().isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError.value(
        path,
        'relativePath',
        'Document paths must be relative and path-safe.',
      );
    }
  }

  Future<void> _removeEmptyAncestors(
    Directory directory,
    Directory root,
  ) async {
    var current = directory.absolute;
    final rootPath = root.absolute.path;
    while (current.path != rootPath &&
        current.path.startsWith('$rootPath${Platform.pathSeparator}')) {
      if (!current.existsSync() || current.listSync().isNotEmpty) break;
      await current.delete();
      current = current.parent;
    }
  }
}

final class _PreparedPaidMove {
  const _PreparedPaidMove({
    required this.item,
    required this.source,
    required this.destination,
    required this.metadata,
    required this.alreadyPresent,
  });

  final PaidDocumentMove item;
  final File source;
  final File destination;
  final File metadata;
  final bool alreadyPresent;
}
