import 'package:flutter/foundation.dart';
import 'dart:math' as math;

double rotationFitScale(double width, double height, double degrees) {
  final angle = degrees * math.pi / 180;
  final c = math.cos(angle).abs(), s = math.sin(angle).abs();
  return math.min(1.0, math.min(width / (width * c + height * s), height / (width * s + height * c)));
}


/// Shared monotonic ordering for interleaved frame and image edits.
final class DocumentEditOrder {
  static int _value = 0;
  static int next() => ++_value;
  static List<int> restore(Object? raw, int count) {
    if (raw == null) return List.generate(count, (_) => next());
    if (raw is! List || raw.length != count || raw.any((v) => v is! int || v <= 0)) {
      throw const FormatException('Invalid document edit ordering.');
    }
    final values = raw.cast<int>();
    for (final value in values) { if (value > _value) _value = value; }
    return values.toList();
  }
}

/// A crop rectangle expressed as fractions of the source image bounds.
@immutable
final class NormalizedCropRect {
  const NormalizedCropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.rotation = 0,
  });

  static const full = NormalizedCropRect(left: 0, top: 0, right: 1, bottom: 1);

  /// Creates a rectangle clamped to the image bounds and ordered by edges.
  factory NormalizedCropRect.fromLTRB(
    double left,
    double top,
    double right,
    double bottom, {
    double rotation = 0,
  }) {
    var normalizedLeft = _clampUnit(left);
    var normalizedTop = _clampUnit(top);
    var normalizedRight = _clampUnit(right);
    var normalizedBottom = _clampUnit(bottom);
    if (normalizedRight < normalizedLeft) {
      final swap = normalizedLeft;
      normalizedLeft = normalizedRight;
      normalizedRight = swap;
    }
    if (normalizedBottom < normalizedTop) {
      final swap = normalizedTop;
      normalizedTop = normalizedBottom;
      normalizedBottom = swap;
    }
    return NormalizedCropRect(
      left: normalizedLeft,
      top: normalizedTop,
      right: normalizedRight,
      bottom: normalizedBottom,
      rotation: rotation.isFinite ? rotation.clamp(-180.0, 180.0) : 0,
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double rotation;

  NormalizedCropRect get clamped =>
      NormalizedCropRect.fromLTRB(left, top, right, bottom, rotation: rotation);

  bool get isFull => this == full;

  /// A stable suffix for derivative IDs; it contains no path separators.
  String get stableId => <double>[left, top, right, bottom, rotation]
      .map((value) => value.toStringAsFixed(4))
      .map((value) => value.replaceAll('.', '_'))
      .join('-');

  @override
  bool operator ==(Object other) {
    return other is NormalizedCropRect &&
        other.left == left &&
        other.top == top &&
        other.right == right &&
        other.bottom == bottom &&
        other.rotation == rotation;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom, rotation);

  @override
  String toString() =>
      'NormalizedCropRect(left: $left, top: $top, right: $right, bottom: $bottom)';
}

enum CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  right,
  bottom,
  left,
}

/// Transient crop draft history for one review item.
final class CropEditHistory extends ChangeNotifier {
  CropEditHistory({NormalizedCropRect initial = NormalizedCropRect.full, this.normalizedAspectRatio})
    : _initial = initial.clamped,
      _present = initial.clamped;

  factory CropEditHistory.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported crop history version.');
    }
    final history = CropEditHistory(initial: _decodeRect(json['initial']),
      normalizedAspectRatio: (json['normalizedAspectRatio'] as num?)?.toDouble());
    history._present = _decodeRect(json['present']);
    history._past.addAll((json['past'] as List).map(_decodeRect));
    history._future.addAll((json['future'] as List).map(_decodeRect));
    history._undoOrder.addAll(DocumentEditOrder.restore(json['undoOrder'], history._past.length));
    history._redoOrder.addAll(DocumentEditOrder.restore(json['redoOrder'], history._future.length));
    return history;
  }

  void restoreSnapshot(Map<String, dynamic> snapshot) {
    final restored = CropEditHistory.fromJson(snapshot);
    try {
      if (restored.initial != initial) {
        throw const FormatException(
          'Crop history has a different original frame.',
        );
      }
      _present = restored._present;
      _past
        ..clear()
        ..addAll(restored._past);
      _future
        ..clear()
        ..addAll(restored._future);
      _undoOrder..clear()..addAll(restored._undoOrder);
      _redoOrder..clear()..addAll(restored._redoOrder);
      _resizeStart = null;
      notifyListeners();
    } finally {
      restored.dispose();
    }
  }

  Map<String, Object> toJson() {
    final resizing = _resizeStart != null && _resizeStart != _present;
    return {
      'version': 1,
      'normalizedAspectRatio': ?normalizedAspectRatio,
      'undoOrder': [..._undoOrder, if (resizing) DocumentEditOrder.next()],
      'redoOrder': resizing ? <int>[] : List<int>.of(_redoOrder),
      'initial': _encodeRect(_initial),
      'present': _encodeRect(_present),
      'past': [
        ..._past.map(_encodeRect),
        if (resizing) _encodeRect(_resizeStart!),
      ],
      'future': resizing ? <Object>[] : _future.map(_encodeRect).toList(),
    };
  }

  static List<double> _encodeRect(NormalizedCropRect rect) => [
    rect.left,
    rect.top,
    rect.right,
    rect.bottom,
    rect.rotation,
  ];
  static NormalizedCropRect _decodeRect(Object? value) {
    if (value is! List ||
        (value.length != 4 && value.length != 5) ||
        value.any((v) => v is! num)) {
      throw const FormatException('Invalid crop rectangle.');
    }
    final edges = value.cast<num>().map((v) => v.toDouble()).toList();
    if (edges.take(4).any((v) => !v.isFinite || v < 0 || v > 1) ||
        (edges.length == 5 && (!edges[4].isFinite || edges[4].abs() > 180)) ||
        edges[0] > edges[2] ||
        edges[1] > edges[3]) {
      throw const FormatException(
        'Crop rectangle is outside the source image.',
      );
    }
    return NormalizedCropRect(
      left: edges[0],
      top: edges[1],
      right: edges[2],
      bottom: edges[3],
      rotation: edges.length == 5 ? edges[4] : 0,
    );
  }

  final List<int> _undoOrder = [], _redoOrder = [];
  VoidCallback? onEditCommitted;
  int get latestUndoOrder => _undoOrder.isEmpty ? 0 : _undoOrder.last;
  int get nextRedoOrder => _redoOrder.isEmpty ? 0 : _redoOrder.last;
  void clearRedo() { _future.clear(); _redoOrder.clear(); }
  /// Width / height in normalized coordinates; null preserves free cropping.
  final double? normalizedAspectRatio;
  final NormalizedCropRect _initial;
  final List<NormalizedCropRect> _past = <NormalizedCropRect>[];
  final List<NormalizedCropRect> _future = <NormalizedCropRect>[];
  NormalizedCropRect _present;

  NormalizedCropRect get initial => _initial;
  NormalizedCropRect get present => _present;
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  bool get isDirty => _present != _initial;

  void apply(NormalizedCropRect next) {
    final normalized = next.clamped;
    if (normalized == _present) return;
    _past.add(_present);
    _undoOrder.add(DocumentEditOrder.next());
    _present = normalized;
    clearRedo();
    onEditCommitted?.call();
    notifyListeners();
  }

  NormalizedCropRect? _resizeStart;

  void beginResize() {
    _resizeStart ??= _present;
  }

  void updateResize(
    CropHandle handle, {
    required double deltaX,
    required double deltaY,
    double minimumSize = 0.1,
  }) {
    beginResize();
    _present = _resized(
      _present,
      handle,
      deltaX: deltaX,
      deltaY: deltaY,
      minimumSize: minimumSize,
    );
    notifyListeners();
  }

  void updateTranslation(double deltaX, double deltaY) {
    beginResize();
    final width = _present.right - _present.left;
    final height = _present.bottom - _present.top;
    final left = (_present.left + deltaX).clamp(0.0, 1.0 - width);
    final top = (_present.top + deltaY).clamp(0.0, 1.0 - height);
    _present = NormalizedCropRect.fromLTRB(left, top, left + width, top + height, rotation: _present.rotation);
    notifyListeners();
  }

  void updateRotation(double degrees) {
    beginResize();
    _present = NormalizedCropRect.fromLTRB(
      _present.left,
      _present.top,
      _present.right,
      _present.bottom,
      rotation: degrees,
    );
    notifyListeners();
  }

  void endResize() {
    final start = _resizeStart;
    _resizeStart = null;
    if (start == null || start == _present) return;
    _past.add(start);
    _undoOrder.add(DocumentEditOrder.next());
    clearRedo();
    onEditCommitted?.call();
    notifyListeners();
  }

  void resize(
    CropHandle handle, {
    required double deltaX,
    required double deltaY,
    double minimumSize = 0.1,
  }) {
    apply(
      _resized(
        _present,
        handle,
        deltaX: deltaX,
        deltaY: deltaY,
        minimumSize: minimumSize,
      ),
    );
  }

  NormalizedCropRect _resized(
    NormalizedCropRect source,
    CropHandle handle, {
    required double deltaX,
    required double deltaY,
    required double minimumSize,
  }) {
    final ratio = normalizedAspectRatio;
    if (ratio != null && ratio > 0 && ratio.isFinite) {
      final hx = switch (handle) {
        CropHandle.left || CropHandle.topLeft || CropHandle.bottomLeft => -1,
        CropHandle.right || CropHandle.topRight || CropHandle.bottomRight => 1,
        _ => 0,
      };
      final vy = switch (handle) {
        CropHandle.top || CropHandle.topLeft || CropHandle.topRight => -1,
        CropHandle.bottom || CropHandle.bottomLeft || CropHandle.bottomRight => 1,
        _ => 0,
      };
      final ax = hx < 0 ? source.right : hx > 0 ? source.left : (source.left + source.right) / 2;
      final ay = vy < 0 ? source.bottom : vy > 0 ? source.top : (source.top + source.bottom) / 2;
      final maxX = hx < 0 ? ax : hx > 0 ? 1 - ax : math.min(ax, 1 - ax) * 2;
      final maxY = vy < 0 ? ay : vy > 0 ? 1 - ay : math.min(ay, 1 - ay) * 2;
      final maxWidth = math.min(maxX, maxY * ratio);
      final delta = hx != 0 && (vy == 0 || deltaX.abs() >= (deltaY * ratio).abs())
          ? deltaX * hx : deltaY * vy * ratio;
      final width = (source.right - source.left + delta)
          .clamp(math.min(minimumSize, maxWidth), maxWidth).toDouble();
      final height = width / ratio;
      final left = hx < 0 ? ax - width : hx > 0 ? ax : ax - width / 2;
      final top = vy < 0 ? ay - height : vy > 0 ? ay : ay - height / 2;
      return NormalizedCropRect.fromLTRB(left, top, left + width, top + height, rotation: source.rotation);
    }
    final minimum = minimumSize.clamp(0.01, 1.0).toDouble();
    var left = source.left;
    var top = source.top;
    var right = source.right;
    var bottom = source.bottom;
    switch (handle) {
      case CropHandle.top:
        top = (top + deltaY).clamp(0.0, bottom - minimum).toDouble();
      case CropHandle.bottom:
        bottom = (bottom + deltaY).clamp(top + minimum, 1.0).toDouble();
      case CropHandle.left:
        left = (left + deltaX).clamp(0.0, right - minimum).toDouble();
      case CropHandle.right:
        right = (right + deltaX).clamp(left + minimum, 1.0).toDouble();

      case CropHandle.topLeft:
        left = (left + deltaX).clamp(0.0, right - minimum).toDouble();
        top = (top + deltaY).clamp(0.0, bottom - minimum).toDouble();
      case CropHandle.topRight:
        right = (right + deltaX).clamp(left + minimum, 1.0).toDouble();
        top = (top + deltaY).clamp(0.0, bottom - minimum).toDouble();
      case CropHandle.bottomLeft:
        left = (left + deltaX).clamp(0.0, right - minimum).toDouble();
        bottom = (bottom + deltaY).clamp(top + minimum, 1.0).toDouble();
      case CropHandle.bottomRight:
        right = (right + deltaX).clamp(left + minimum, 1.0).toDouble();
        bottom = (bottom + deltaY).clamp(top + minimum, 1.0).toDouble();
    }
    return NormalizedCropRect.fromLTRB(
      left,
      top,
      right,
      bottom,
      rotation: source.rotation,
    );
  }

  void undo() {
    if (!canUndo) return;
    _future.add(_present);
    _redoOrder.add(_undoOrder.removeLast());
    _present = _past.removeLast();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _past.add(_present);
    _undoOrder.add(_redoOrder.removeLast());
    _present = _future.removeLast();
    notifyListeners();
  }

  void reset() {
    if (_present == _initial && _past.isEmpty && _future.isEmpty) return;
    _past.clear();
    _undoOrder.clear();
    clearRedo();
    _present = _initial;
    notifyListeners();
  }
}

double _clampUnit(double value) => value.clamp(0.0, 1.0).toDouble();
