import 'package:audyt/core/documents/document_record.dart';
import 'package:audyt/core/ids/entity_id.dart';

abstract interface class DocumentRecordStore {
  DocumentRecord? byId(EntityId id);

  List<DocumentRecord> forTransaction(EntityId transactionId);

  void save(DocumentRecord record);
}

final class InMemoryDocumentRecordStore implements DocumentRecordStore {
  InMemoryDocumentRecordStore({Iterable<DocumentRecord> records = const []}) {
    for (final record in records) {
      if (_records.containsKey(record.id)) {
        throw ArgumentError.value(
          record.id,
          'records',
          'A document record cannot be included twice.',
        );
      }
      _records[record.id] = record;
    }
  }

  final Map<EntityId, DocumentRecord> _records = <EntityId, DocumentRecord>{};

  @override
  DocumentRecord? byId(EntityId id) => _records[id];

  @override
  List<DocumentRecord> forTransaction(EntityId transactionId) =>
      List<DocumentRecord>.unmodifiable(
        _records.values.where(
          (record) => record.transactionId == transactionId,
        ),
      );

  @override
  void save(DocumentRecord record) {
    _records[record.id] = record;
  }

  List<DocumentRecord> get all =>
      List<DocumentRecord>.unmodifiable(_records.values);
}
