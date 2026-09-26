import 'dart:io';

final class RelocationItem {
  const RelocationItem({
    required this.relativePath,
    required this.sourcePath,
    required this.destinationPath,
  });

  final String relativePath;
  final String sourcePath;
  final String destinationPath;
}

final class LocalFolderRelocationPlan {
  LocalFolderRelocationPlan._({
    required this.sourceRoot,
    required this.destinationRoot,
    required List<RelocationItem> items,
  }) : items = List.unmodifiable(items);

  factory LocalFolderRelocationPlan.build({
    required Directory sourceRoot,
    required Directory destinationRoot,
  }) {
    final sourcePath = sourceRoot.absolute.path;
    final destinationPath = destinationRoot.absolute.path;
    if (!sourceRoot.existsSync()) {
      throw ArgumentError.value(
        sourceRoot.path,
        'sourceRoot',
        'Root does not exist.',
      );
    }
    if (sourceRoot.statSync().type != FileSystemEntityType.directory) {
      throw ArgumentError.value(
        sourceRoot.path,
        'sourceRoot',
        'Root is not a directory.',
      );
    }
    if (_isWithin(destinationPath, sourcePath)) {
      throw ArgumentError.value(
        destinationRoot.path,
        'destinationRoot',
        'Destination cannot be inside the source root.',
      );
    }

    final items = <RelocationItem>[];
    for (final entity in sourceRoot.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        throw ArgumentError.value(
          entity.path,
          'sourceRoot',
          'Symlinks are not supported in a managed root.',
        );
      }
      if (entity is! File) {
        continue;
      }
      final relativePath = _relativePath(sourcePath, entity.absolute.path);
      items.add(
        RelocationItem(
          relativePath: relativePath,
          sourcePath: entity.path,
          destinationPath: '$destinationPath/$relativePath',
        ),
      );
    }
    items.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return LocalFolderRelocationPlan._(
      sourceRoot: sourceRoot,
      destinationRoot: destinationRoot,
      items: items,
    );
  }

  final Directory sourceRoot;
  final Directory destinationRoot;
  final List<RelocationItem> items;

  static bool _isWithin(String candidate, String root) {
    return candidate == root ||
        candidate.startsWith('$root${Platform.pathSeparator}');
  }

  static String _relativePath(String root, String path) {
    if (!_isWithin(path, root) || path == root) {
      throw StateError('A relocation item escaped the managed root.');
    }
    return path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
  }
}
