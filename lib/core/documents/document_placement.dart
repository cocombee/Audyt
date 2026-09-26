import 'folder_placement_plan.dart';

final class DocumentPlacementPlan {
  DocumentPlacementPlan._({required this.rootPath, required this.relativePath});

  factory DocumentPlacementPlan.build({
    required String rootPath,
    required List<DocumentNamingPlan> folderPlans,
    required DocumentNamingPlan filenamePlan,
    required NamingContext context,
  }) {
    final normalizedRoot = rootPath.trim();
    if (normalizedRoot.isEmpty) {
      throw ArgumentError.value(
        rootPath,
        'rootPath',
        'A document root is required.',
      );
    }
    final folders = folderPlans
        .map((plan) => plan.render(context))
        .where((folder) => folder.isNotEmpty)
        .toList();
    final filename = filenamePlan.render(context);
    if (filename.contains('/') || filename.contains('\\')) {
      throw ArgumentError.value(
        filename,
        'filenamePlan',
        'A rendered filename cannot contain a path separator.',
      );
    }
    final relativePath = [...folders, filename].join('/');
    return DocumentPlacementPlan._(
      rootPath: normalizedRoot,
      relativePath: relativePath,
    );
  }

  final String rootPath;
  final String relativePath;

  String get absolutePath => '$rootPath/$relativePath';
}
