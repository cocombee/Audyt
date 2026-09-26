import 'package:flutter/services.dart';

import '../../../core/ids/entity_id.dart';
import 'accounting_workspace.dart';

/// Device-local recovery catalogue. Entries retain the archive's company ID;
/// the separate copy ID is never a membership or an accounting identity.
final class RestoredWorkspaceEntry {
  const RestoredWorkspaceEntry({
    required this.id,
    required this.businessId,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.available,
  });
  factory RestoredWorkspaceEntry.decode(Object? data) {
    if (data is! Map) {
      throw const FormatException('Invalid restored workspace.');
    }
    final id = data['id'], business = data['businessId'];
    final name = data['name'], path = data['path'];
    final created = data['createdAt'], available = data['available'];
    if (id is! String ||
        business is! String ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 4000 ||
        path is! String ||
        !path.startsWith('/') ||
        created is! String ||
        available is! bool) {
      throw const FormatException('Invalid restored workspace.');
    }
    EntityId.parse(id);
    final date = DateTime.tryParse(created);
    if (date == null) {
      throw const FormatException('Invalid restored workspace.');
    }
    return RestoredWorkspaceEntry(
      id: id,
      businessId: EntityId.parse(business),
      name: name,
      path: path,
      createdAt: date,
      available: available,
    );
  }
  final String id, name, path;
  final EntityId businessId;
  final DateTime createdAt;
  final bool available;
}

final class RestoredWorkspaceCatalog {
  const RestoredWorkspaceCatalog(this.entries, this.issues);
  final List<RestoredWorkspaceEntry> entries;
  final int issues;
}

final class RestoredWorkspaces {
  const RestoredWorkspaces();
  static const channel = MethodChannel('audyt/local-storage');
  Future<RestoredWorkspaceCatalog> list() async {
    final data = await channel.invokeMethod<Map>('listRestoredWorkspaces');
    if (data == null ||
        data['workspaces'] is! List ||
        data['issues'] is! int ||
        (data['issues'] as int) < 0) {
      throw const FormatException(
        'The restored workspace list is unavailable.',
      );
    }
    final entries = (data['workspaces'] as List)
        .map(RestoredWorkspaceEntry.decode)
        .toList(growable: false);
    if (entries.map((entry) => entry.id).toSet().length != entries.length) {
      throw const FormatException(
        'The restored workspace list needs recovery.',
      );
    }
    return RestoredWorkspaceCatalog(
      List.unmodifiable(entries),
      data['issues'] as int,
    );
  }

  Future<RestoredWorkspaceEntry> lookup(String path) async {
    final entry = RestoredWorkspaceEntry.decode(
      await channel.invokeMethod<Map>('restoredWorkspace', {'path': path}),
    );
    if (!entry.available || entry.path != path) {
      throw StateError(
        'The restored workspace is unavailable or needs recovery.',
      );
    }
    return entry;
  }

  Future<RestoredWorkspaceEntry> register(
    String path,
    AccountingWorkspace workspace,
  ) async {
    final name = workspace.preferences.text(
      'Business Profile',
      'Business Name',
    );
    final entry = RestoredWorkspaceEntry.decode(
      await channel.invokeMethod<Map>('registerRestoredWorkspace', {
        'path': path,
        'businessId': workspace.identity.businessId.value,
        'name': name.trim().isEmpty ? 'Restored Company' : name,
      }),
    );
    if (entry.businessId != workspace.identity.businessId ||
        entry.path != path ||
        !entry.available) {
      throw StateError('The restored workspace could not be registered.');
    }
    return entry;
  }
}
