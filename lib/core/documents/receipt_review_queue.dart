import 'dart:typed_data';

import 'crop_edit.dart';
import 'receipt_document.dart';

enum ReceiptReviewItemState { needsReview, saved, skipped, failed, discarded }

final class ReceiptReviewItem {
  ReceiptReviewItem(ReceiptAttachment attachment)
    : _attachment = attachment,
      _workingAttachment = attachment,
      cropHistory = CropEditHistory(),
      _rawBytes = List<int>.unmodifiable(
        Uint8List.fromList(attachment.originalBytes),
      ) {
    _committedCropHistory = cropHistory.toJson();
    cropHistory.onEditCommitted = () { _redo.clear(); _redoOrder.clear(); };
  }

  ReceiptReviewItem._restore(
    this._attachment,
    this._workingAttachment,
    this.cropHistory,
    this._state,
  ) : _rawBytes = List<int>.unmodifiable(_attachment.originalBytes) {
    _committedCropHistory = cropHistory.toJson();
    cropHistory.onEditCommitted = () { _redo.clear(); _redoOrder.clear(); };
  }

  factory ReceiptReviewItem.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported review item version.');
    }
    final attachment = ReceiptAttachment.fromJson(
      json['attachment'] as Map<String, dynamic>,
    );
    final working = ReceiptAttachment.fromJson(
      json['workingAttachment'] as Map<String, dynamic>,
    );
    if (working.originalId != attachment.originalId ||
        working.originalSha256 != attachment.originalSha256) {
      throw const FormatException(
        'Review history does not belong to the preserved original.',
      );
    }
    final item = ReceiptReviewItem._restore(
      attachment,
      working,
      CropEditHistory.fromJson(json['cropHistory'] as Map<String, dynamic>),
      ReceiptReviewItemState.values.byName(json['state'] as String),
    );
    if (json['committedCropHistory'] != null) {
      final committed = CropEditHistory.fromJson(
        json['committedCropHistory'] as Map<String, dynamic>,
      );
      try {
        if (committed.initial != item.cropHistory.initial) {
          throw const FormatException(
            'Committed crop history has a different original frame.',
          );
        }
        item._committedCropHistory = committed.toJson();
      } finally {
        committed.dispose();
      }
    }
    for (final entry in {
      'editUndo': item._undo,
      'editRedo': item._redo,
    }.entries) {
      for (final snapshot in (json[entry.key] as List? ?? [])) {
        final previous = ReceiptAttachment.fromJson(
          Map<String, dynamic>.from(snapshot as Map),
        );
        if (previous.originalId != attachment.originalId ||
            previous.originalSha256 != attachment.originalSha256) {
          throw const FormatException(
            'Edit history belongs to another original.',
          );
        }
        entry.value.add(previous);
      }
    }
    item._undoOrder.addAll(DocumentEditOrder.restore(json['editUndoOrder'], item._undo.length));
    item._redoOrder.addAll(DocumentEditOrder.restore(json['editRedoOrder'], item._redo.length));
    return item;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'attachment': _attachment.toJson(),
    'workingAttachment': _workingAttachment.toJson(),
    'cropHistory': cropHistory.toJson(),
    'committedCropHistory': _committedCropHistory,
    'state': _state.name,
    'editUndoOrder': List<int>.of(_undoOrder),
    'editRedoOrder': List<int>.of(_redoOrder),
    'editUndo': _undo.map((a) => a.toJson()).toList(),
    'editRedo': _redo.map((a) => a.toJson()).toList(),
  };

  final List<int> _undoOrder = [], _redoOrder = [];
  bool get canUndoLatest => !isResolved && (canUndoEdit || cropHistory.canUndo);
  bool get canRedoLatest => !isResolved && (canRedoEdit || cropHistory.canRedo);
  void undoLatest() {
    if (isResolved) return;
    if (cropHistory.canUndo && (!canUndoEdit || cropHistory.latestUndoOrder > _undoOrder.last)) {
      cropHistory.undo();
    } else { undoEdit(); }
  }
  void redoLatest() {
    if (isResolved) return;
    if (cropHistory.canRedo && (!canRedoEdit || cropHistory.nextRedoOrder < _redoOrder.last)) {
      cropHistory.redo();
    } else { redoEdit(); }
  }
  final List<ReceiptAttachment> _undo = [];
  final List<ReceiptAttachment> _redo = [];
  bool get canUndoEdit => !isResolved && _undo.isNotEmpty;
  bool get canRedoEdit => !isResolved && _redo.isNotEmpty;
  void undoEdit() {
    if (!canUndoEdit) return;
    _redo.add(_workingAttachment);
    _redoOrder.add(_undoOrder.removeLast());
    _workingAttachment = _undo.removeLast();
  }

  void redoEdit() {
    if (!canRedoEdit) return;
    _undo.add(_workingAttachment);
    _undoOrder.add(_redoOrder.removeLast());
    _workingAttachment = _redo.removeLast();
  }

  final List<int> _rawBytes;
  final CropEditHistory cropHistory;
  late Map<String, Object> _committedCropHistory;
  ReceiptAttachment _attachment;
  ReceiptAttachment _workingAttachment;
  ReceiptReviewItemState _state = ReceiptReviewItemState.needsReview;

  ReceiptAttachment get attachment => _attachment;
  ReceiptAttachment get workingAttachment => _workingAttachment;
  ReceiptReviewItemState get state => _state;
  List<int> get rawBytes => _rawBytes;
  bool get isResolved =>
      _state == ReceiptReviewItemState.saved ||
      _state == ReceiptReviewItemState.skipped ||
      _state == ReceiptReviewItemState.discarded;

  void dispose() {
    cropHistory.dispose();
  }

  void applyWorkingAttachment(ReceiptAttachment attachment) {
    if (isResolved) return;
    if (attachment.originalId != _attachment.originalId ||
        attachment.originalSha256 != _attachment.originalSha256) {
      throw ArgumentError.value(
        attachment.originalId,
        'attachment',
        'A review derivative must belong to the current original.',
      );
    }
    _undo.add(_workingAttachment);
    _undoOrder.add(DocumentEditOrder.next());
    if (_undo.length > 20) { _undo.removeAt(0); _undoOrder.removeAt(0); }
    _redo.clear();
    _redoOrder.clear();
    cropHistory.clearRedo();
    _workingAttachment = attachment;
    if (_state == ReceiptReviewItemState.failed &&
        attachment.status == AttachmentProcessingStatus.ready) {
      _state = ReceiptReviewItemState.needsReview;
    }
  }

  void cancelWorkingAttachment() {
    if (!isResolved) {
      _workingAttachment = _attachment;
      cropHistory.restoreSnapshot(
        Map<String, dynamic>.from(_committedCropHistory),
      );
    }
  }

  void save() {
    if (_state == ReceiptReviewItemState.skipped) {
      throw StateError('A skipped receipt cannot be saved.');
    }
    if (_workingAttachment.status != AttachmentProcessingStatus.ready) {
      throw StateError('A receipt must be ready before it can be saved.');
    }
    _attachment = _workingAttachment;
    _committedCropHistory = cropHistory.toJson();
    _state = ReceiptReviewItemState.saved;
  }

  void skip() {
    if (!isResolved) {
      _workingAttachment = _attachment;
      cropHistory.restoreSnapshot(
        Map<String, dynamic>.from(_committedCropHistory),
      );
      _state = ReceiptReviewItemState.skipped;
    }
  }

  /// Discard belongs only to this open review; previously saved items survive.
  void discard() {
    if (isResolved) return;
    cancelWorkingAttachment();
    _undo.clear();
    _redo.clear();
    _undoOrder.clear();
    _redoOrder.clear();
    _state = ReceiptReviewItemState.discarded;
  }

  void fail() {
    if (!isResolved) {
      _state = ReceiptReviewItemState.failed;
    }
  }
}

final class ReceiptReviewQueue {
  ReceiptReviewQueue(Iterable<ReceiptAttachment> attachments, {this.retainAttachmentsOnDiscard = false})
    : _items = attachments.map(ReceiptReviewItem.new).toList() {
    if (_items.isEmpty) {
      throw ArgumentError.value(
        attachments,
        'attachments',
        'At least one receipt is required for review.',
      );
    }
  }

  ReceiptReviewQueue._restore(this._items, this._index, this.retainAttachmentsOnDiscard);
  factory ReceiptReviewQueue.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported receipt review version.');
    }
    final items = (json['items'] as List)
        .map((item) => ReceiptReviewItem.fromJson(item as Map<String, dynamic>))
        .toList();
    final index = json['index'];
    if (items.isEmpty ||
        index is! int ||
        index < 0 ||
        index >= items.length ||
        items.map((item) => item.attachment.originalId).toSet().length !=
            items.length) {
      for (final item in items) {
        item.dispose();
      }
      throw const FormatException('Invalid receipt review order or selection.');
    }
    return ReceiptReviewQueue._restore(items, index, json['retainAttachmentsOnDiscard'] == true);
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'index': _index,
    'retainAttachmentsOnDiscard': retainAttachmentsOnDiscard,
    'items': _items.map((item) => item.toJson()).toList(),
  };

  final bool retainAttachmentsOnDiscard;
  final List<ReceiptReviewItem> _items;
  int _index = 0;

  List<ReceiptReviewItem> get items =>
      List<ReceiptReviewItem>.unmodifiable(_items);
  ReceiptReviewItem get current => _items[_index];
  int get index => _index;
  int get totalCount => _items.length;

  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
  }

  int get savedCount =>
      _items.where((item) => item.state == ReceiptReviewItemState.saved).length;
  int get skippedCount => _items
      .where((item) => item.state == ReceiptReviewItemState.skipped)
      .length;
  int get failedCount => _items
      .where((item) => item.state == ReceiptReviewItemState.failed)
      .length;
  int get remainingCount => _items.where((item) => !item.isResolved).length;
  bool get hasUnresolved => remainingCount > 0;
  bool get isComplete => !hasUnresolved;

  bool moveNext() {
    if (_index >= _items.length - 1) return false;
    _index += 1;
    return true;
  }

  bool movePrevious() {
    if (_index == 0) return false;
    _index -= 1;
    return true;
  }

  bool moveToNextUnresolved() {
    for (var candidate = _index + 1; candidate < _items.length; candidate++) {
      if (!_items[candidate].isResolved) {
        _index = candidate;
        return true;
      }
    }
    return false;
  }

  bool moveToPreviousUnresolved() {
    for (var candidate = _index - 1; candidate >= 0; candidate--) {
      if (!_items[candidate].isResolved) {
        _index = candidate;
        return true;
      }
    }
    return false;
  }

  void applyWorkingAttachment(ReceiptAttachment attachment) {
    current.applyWorkingAttachment(attachment);
  }

  void cancelWorkingAttachment() {
    current.cancelWorkingAttachment();
  }

  void markSaved() {
    current.save();
  }

  void markSkipped() {
    current.skip();
  }

  bool skipAll({required bool confirmed}) {
    if (!confirmed) return false;
    for (final item in _items) {
      item.skip();
    }
    return true;
  }
}
