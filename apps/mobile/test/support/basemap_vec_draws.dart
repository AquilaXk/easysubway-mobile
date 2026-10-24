import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_graphics_codec/vector_graphics_codec.dart';

/// path 하나 안의 윤곽(moveTo로 시작하는 subpath) 하나.
///
/// 라벨 글리프 하나는 윤곽 여럿으로 이뤄지고("ㅇ"은 바깥과 안쪽 둘), halo(stroke)와
/// 글자(fill)는 **같은 윤곽 좌표**를 칠한다. 묶음(data #1495)은 인접 path를 이어 한 path로
/// 칠하지만 윤곽 좌표는 바꾸지 않으므로, 윤곽 좌표가 묶음과 무관하게 halo와 글자를
/// 잇는 열쇠다.
class BasemapVecContour {
  BasemapVecContour(this.points);

  /// [x0, y0, x1, y1, ...] 끝점 좌표.
  final List<double> points;

  late final String key = points.join(',');

  late final double minX = _extreme(0, math.min, double.infinity);
  late final double minY = _extreme(1, math.min, double.infinity);
  late final double maxX = _extreme(0, math.max, double.negativeInfinity);
  late final double maxY = _extreme(1, math.max, double.negativeInfinity);

  double _extreme(
    int offset,
    double Function(double, double) pick,
    double initial,
  ) {
    var value = initial;
    for (var i = offset; i < points.length; i += 2) {
      value = pick(value, points[i]);
    }
    return value;
  }
}

/// 컴파일 산출 `.vec`에서 **path draw 명령**을 문서 순서대로 뽑는다.
///
/// 윤곽선 변형 바탕의 라벨은 글리프 윤곽선 path로 구워져(data #1488) 텍스트 draw가 없다.
/// 라벨의 그리기 순서는 path draw의 paint(채움/선, 색, 선 굵기)와 윤곽 좌표로 읽는다.
/// 래스터라이즈에 의존하지 않아 배경·안티에일리어싱과 무관하게 결정적이다.
class BasemapVecPathDraw {
  BasemapVecPathDraw({
    required this.index,
    required this.isStroke,
    required this.color,
    required this.contours,
  });

  /// .vec 안에서의 path draw 순서(0부터).
  final int index;

  /// stroke paint로 그려지는 draw인가(false면 fill).
  final bool isStroke;

  /// paint 색(ARGB 32비트).
  final int color;

  final List<BasemapVecContour> contours;

  bool get isOpaqueWhite => color == 0xffffffff;
}

class _PaintRecord {
  _PaintRecord(this.color, this.isStroke);

  final int color;
  final bool isStroke;
}

class _PathDrawListener extends BasemapVecListener {
  final Map<int, _PaintRecord> _paints = <int, _PaintRecord>{};
  final Map<int, List<BasemapVecContour>> _paths =
      <int, List<BasemapVecContour>>{};
  final List<BasemapVecPathDraw> draws = <BasemapVecPathDraw>[];

  int _pathId = -1;
  List<BasemapVecContour> _contours = <BasemapVecContour>[];
  List<double>? _points;

  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {
    _paints[id] = _PaintRecord(color, paintStyle == _paintStyleStroke);
  }

  @override
  void onPathStart(int id, int fillType) {
    _pathId = id;
    _contours = <BasemapVecContour>[];
    _points = null;
  }

  @override
  void onPathMoveTo(double x, double y) {
    _closeContour();
    _points = <double>[x, y];
  }

  @override
  void onPathLineTo(double x, double y) => _points?.addAll([x, y]);

  @override
  void onPathCubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => _points?.addAll([x3, y3]);

  @override
  void onPathFinished() {
    _closeContour();
    _paths[_pathId] = _contours;
  }

  void _closeContour() {
    final points = _points;
    if (points != null) _contours.add(BasemapVecContour(points));
    _points = null;
  }

  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) {
    final paint = _paints[paintId];
    final contours = _paths[pathId];
    if (paint == null || contours == null || contours.isEmpty) return;
    draws.add(
      BasemapVecPathDraw(
        index: draws.length,
        isStroke: paint.isStroke,
        color: paint.color,
        contours: contours,
      ),
    );
  }
}

/// 코덱 `paintStyle` 값 중 stroke. 런타임 vector_graphics 1.2.2 lib/src/listener.dart 395행이 같은 값으로 가른다.
const int _paintStyleStroke = 1;

/// 모든 명령을 무시하는 `.vec` 디코드 리스너. 게이트는 필요한 명령만 덮어쓴다.
class BasemapVecListener extends VectorGraphicsCodecListener {
  @override
  void onSize(double width, double height) {}
  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {}
  @override
  void onPathStart(int id, int fillType) {}
  @override
  void onPathMoveTo(double x, double y) {}
  @override
  void onPathLineTo(double x, double y) {}
  @override
  void onPathCubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {}
  @override
  void onPathClose() {}
  @override
  void onPathFinished() {}
  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) {}
  @override
  void onDrawVertices(
    Float32List vertices,
    Uint16List? indices,
    int? paintId,
  ) {}
  @override
  void onSaveLayer(int paintId) {}
  @override
  void onClipPath(int pathId) {}
  @override
  void onRestoreLayer() {}
  @override
  void onMask() {}
  @override
  void onRadialGradient(
    double centerX,
    double centerY,
    double radius,
    double? focalX,
    double? focalY,
    Int32List colors,
    Float32List? offsets,
    Float64List? transform,
    int tileMode,
    int id,
  ) {}
  @override
  void onLinearGradient(
    double fromX,
    double fromY,
    double toX,
    double toY,
    Int32List colors,
    Float32List? offsets,
    int tileMode,
    int id,
  ) {}
  @override
  void onImage(
    int imageId,
    int format,
    Uint8List data, {
    VectorGraphicsErrorListener? onError,
  }) {}
  @override
  void onDrawImage(
    int imageId,
    double x,
    double y,
    double width,
    double height,
    Float64List? transform,
  ) {}
  @override
  void onPatternStart(
    int patternId,
    double x,
    double y,
    double width,
    double height,
    Float64List transform,
  ) {}
  @override
  void onTextPosition(
    int textPositionId,
    double? x,
    double? y,
    double? dx,
    double? dy,
    bool reset,
    Float64List? transform,
  ) {}
  @override
  void onUpdateTextPosition(int textPositionId) {}
  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double xAnchorMultiplier,
    int fontWeight,
    double fontSize,
    int decoration,
    int decorationStyle,
    int decorationColor,
    int id,
  ) {}
  @override
  void onDrawText(int textId, int? fillId, int? strokeId, int? patternId) {}
}

/// [path]의 `.vec`를 디코드해 path draw를 그리기 순서대로 돌려준다.
List<BasemapVecPathDraw> basemapVecPathDraws(String path) {
  final bytes = File(path).readAsBytesSync();
  final listener = _PathDrawListener();
  const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), listener);
  return listener.draws;
}

/// 텍스트 라벨 변형 `.vec`의 텍스트 draw 하나. [x]·[y]는 그리기 직전 펜 위치다.
///
/// 런타임 vector_graphics 1.2.3 lib/src/listener.dart onUpdateTextPosition(630행)의
/// 펜 이동 규칙을 그대로 따른다. 앵커 정렬 전 위치라 글자 폭과 무관하고, 같은 줄의
/// halo(stroke)와 글자(fill) 사본은 같은 위치 레코드를 써서 같은 값을 갖는다.
class BasemapVecTextDraw {
  BasemapVecTextDraw({
    required this.index,
    required this.text,
    required this.x,
    required this.y,
    required this.hasFill,
    required this.hasStroke,
  });

  /// .vec 안에서의 텍스트 draw 순서(0부터).
  final int index;
  final String text;
  final double x;
  final double y;

  /// fill paint로 그려지는 draw인가(paint-order 분해의 글자 사본).
  final bool hasFill;

  /// stroke paint로 그려지는 draw인가(paint-order 분해의 halo 사본).
  final bool hasStroke;
}

typedef _TextPosition = ({
  double? x,
  double? y,
  double? dx,
  double? dy,
  bool reset,
  Float64List? transform,
});

class _TextDrawListener extends BasemapVecListener {
  final List<_TextPosition> _positions = <_TextPosition>[];
  final Map<int, String> _texts = <int, String>{};
  final List<BasemapVecTextDraw> draws = <BasemapVecTextDraw>[];

  double? _penX;
  double _penY = 0;
  Float64List? _transform;

  @override
  void onTextPosition(
    int textPositionId,
    double? x,
    double? y,
    double? dx,
    double? dy,
    bool reset,
    Float64List? transform,
  ) {
    _positions.add((
      x: x,
      y: y,
      dx: dx,
      dy: dy,
      reset: reset,
      transform: transform,
    ));
  }

  @override
  void onUpdateTextPosition(int textPositionId) {
    final position = _positions[textPositionId];
    if (position.reset) {
      _penX = 0;
      _penY = 0;
    }
    if (position.x != null) _penX = position.x;
    if (position.y != null) _penY = position.y!;
    if (position.dx != null) _penX = (_penX ?? 0) + position.dx!;
    if (position.dy != null) _penY = _penY + position.dy!;
    _transform = position.transform;
  }

  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double xAnchorMultiplier,
    int fontWeight,
    double fontSize,
    int decoration,
    int decorationStyle,
    int decorationColor,
    int id,
  ) {
    _texts[id] = text;
  }

  @override
  void onDrawText(int textId, int? fillId, int? strokeId, int? patternId) {
    var x = _penX ?? 0;
    var y = _penY;
    final transform = _transform;
    if (transform != null) {
      // 런타임은 그리기 직전 canvas.transform(4x4 열 우선)을 적용한다.
      (x, y) = (
        transform[0] * x + transform[4] * y + transform[12],
        transform[1] * x + transform[5] * y + transform[13],
      );
    }
    draws.add(
      BasemapVecTextDraw(
        index: draws.length,
        text: _texts[textId]!,
        x: x,
        y: y,
        hasFill: fillId != null,
        hasStroke: strokeId != null,
      ),
    );
  }
}

/// [path]의 `.vec`를 디코드해 텍스트 draw를 그리기 순서대로 돌려준다.
List<BasemapVecTextDraw> basemapVecTextDraws(String path) {
  final bytes = File(path).readAsBytesSync();
  final listener = _TextDrawListener();
  const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), listener);
  return listener.draws;
}
