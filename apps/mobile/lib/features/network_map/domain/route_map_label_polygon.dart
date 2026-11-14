import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

const int _maxPolygonInputLength = 65536;
const int _maxPolygonVertices = 2048;
const int _maxPolygonCacheEntries = 4096;

/// [Float32List] interleaved 좌표 `[x0, y0, x1, y1, ...]`와 사전 계산된 AABB를 보관한다.
class ParsedRouteMapLabelPolygon {
  const ParsedRouteMapLabelPolygon.raw(this.coordinates, this.bounds);

  final Float32List coordinates;
  final Rect bounds;

  int get pointCount => coordinates.length >> 1;

  Offset pointAt(int index) {
    final base = index << 1;
    return Offset(coordinates[base], coordinates[base + 1]);
  }

  List<Offset> toOffsetList() => [
    for (var i = 0; i < coordinates.length; i += 2)
      Offset(coordinates[i], coordinates[i + 1]),
  ];
}

final LinkedHashMap<String, ParsedRouteMapLabelPolygon?> _polygonDataCache =
    LinkedHashMap<String, ParsedRouteMapLabelPolygon?>();

ParsedRouteMapLabelPolygon? parseRouteMapLabelPolygonData(String value) {
  if (value.isEmpty || value.length > _maxPolygonInputLength) {
    return null;
  }
  if (_polygonDataCache.containsKey(value)) {
    final cached = _polygonDataCache.remove(value);
    _polygonDataCache[value] = cached;
    return cached;
  }
  final parsed = _parsePolygonDataUncached(value);
  if (_polygonDataCache.length >= _maxPolygonCacheEntries) {
    _polygonDataCache.remove(_polygonDataCache.keys.first);
  }
  _polygonDataCache[value] = parsed;
  return parsed;
}

ParsedRouteMapLabelPolygon? _parsePolygonDataUncached(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > _maxPolygonInputLength) {
    return null;
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! List ||
        decoded.length < 3 ||
        decoded.length > _maxPolygonVertices) {
      return null;
    }
    final coordinates = Float32List(decoded.length * 2);
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var writeIndex = 0;
    for (final rawPoint in decoded) {
      if (rawPoint is! Map) {
        return null;
      }
      final x = rawPoint['x'];
      final y = rawPoint['y'];
      if (x is! num || y is! num) {
        return null;
      }
      final dx = x.toDouble();
      final dy = y.toDouble();
      if (!dx.isFinite || !dy.isFinite || dx < 0 || dy < 0) {
        return null;
      }
      coordinates[writeIndex] = dx;
      coordinates[writeIndex + 1] = dy;
      final fx = coordinates[writeIndex];
      final fy = coordinates[writeIndex + 1];
      minX = math.min(minX, fx);
      minY = math.min(minY, fy);
      maxX = math.max(maxX, fx);
      maxY = math.max(maxY, fy);
      writeIndex += 2;
    }
    return ParsedRouteMapLabelPolygon.raw(
      coordinates,
      Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  } on FormatException {
    return null;
  }
}

List<Offset>? parseRouteMapLabelPolygon(String value) {
  if (value.trim().isEmpty || value.length > _maxPolygonInputLength) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List ||
        decoded.length < 3 ||
        decoded.length > _maxPolygonVertices) {
      return null;
    }
    final points = <Offset>[];
    for (final rawPoint in decoded) {
      if (rawPoint is! Map) {
        return null;
      }
      final x = rawPoint['x'];
      final y = rawPoint['y'];
      if (x is! num || y is! num) {
        return null;
      }
      final dx = x.toDouble();
      final dy = y.toDouble();
      if (!dx.isFinite || !dy.isFinite || dx < 0 || dy < 0) {
        return null;
      }
      points.add(Offset(dx, dy));
    }
    return points;
  } on FormatException {
    return null;
  }
}
