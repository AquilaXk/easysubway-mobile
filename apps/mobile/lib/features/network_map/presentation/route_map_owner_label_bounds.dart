import 'dart:ui' show Offset, Rect;

import '../domain/route_map_owner_labels.dart';

/// [text]/[position]/[anchor]/[fontSizeSource] 한 줄의 근사 렌더 rect(source
/// 좌표). [_ownerLabelSourceRect]·다줄 union이 공유하는 단일 줄 계산 —
/// painter의 같은 baseline 규칙(top = anchorY − 0.8×fontSize)·anchor 배치를
/// 쓴다. 폭은 TextPainter 실측 대신 "글자수 × fontSize"로 보수적 근사한다
/// (한글 자폭 ≈ 1em이라 근사 방향은 과대 → bounds가 살짝 넓어질 뿐 라벨을
/// 자르는 방향이 아니어서 안전).
Rect _ownerLabelLineSourceRect(
  String text,
  Offset position,
  RouteMapOwnerLabelAnchor anchor,
  double fontSizeSource,
) {
  final width = text.runes.length * fontSizeSource;
  // painter의 TextPainter 높이는 대략 fontSize × 1.3(줄 높이)이라 그만큼 잡는다
  // (수직 여유 — 과대 방향이라 안전).
  final height = fontSizeSource * 1.3;
  final top = position.dy - 0.8 * fontSizeSource;
  final double left;
  switch (anchor) {
    case RouteMapOwnerLabelAnchor.middle:
      left = position.dx - width / 2;
    case RouteMapOwnerLabelAnchor.end:
      left = position.dx - width;
    case RouteMapOwnerLabelAnchor.start:
      left = position.dx;
  }
  return Rect.fromLTWH(left, top, width, height);
}

/// basemap 오너 라벨 1건의 실제 렌더 rect를 source 좌표로 산출한다(#2068,
/// 다줄 라벨 렌더 갱신). 라벨 자체는 canonical SVG 바탕층이 그리므로
/// (#2068 SVG 충실도) 이 rect는 렌더가 아니라 **geometry bounds 확장**에
/// 쓰인다 — entry.fontSizePx는 이미 source(viewBox) 단위 로컬 font-size라 design
/// 변환·클램프 없이 그대로 쓴다(클램프가 있으면 bounds가 실제 렌더보다 좁게
/// 잡혀 라벨이 잘릴 수 있다).
///
/// [entry.lines]가 2줄 이상이면(오너 SVG가 줄바꿈한 라벨) 단일 줄 근사
/// (entry.station 전체 폭)와 줄별 근사의 **합집합**을 잡아 항상 안전한
/// 상위집합이 되게 한다(과대 방향, 절대 과소 방향 아님).
Rect _ownerLabelSourceRect(RouteMapOwnerLabelEntry entry) {
  var rect = _ownerLabelLineSourceRect(
    entry.station,
    entry.position,
    entry.anchor,
    entry.fontSizePx,
  );
  for (final line in entry.lines) {
    rect = rect.expandToInclude(
      _ownerLabelLineSourceRect(
        line.text,
        line.position,
        entry.anchor,
        entry.fontSizePx,
      ),
    );
  }
  return rect;
}

/// basemap 지역 오너 라벨들의 실제 렌더 rect(source 좌표) 목록. geometry bounds가
/// 라벨 extents까지 담도록 지도 geometry 계산에 넘긴다(#2068). 매칭 여부와
/// 무관하게 전 엔트리를 포함한다 — 매치 라벨은 정확히 이 앵커에 그려지고,
/// 미매치 라벨은 솔버가 그 역 근처(이미 station±18 bounds 안)에 배치하므로,
/// 전 엔트리 union은 실렌더 extents의 안전한 상위집합이다.
List<Rect> networkMapOwnerLabelSourceRects({
  required Iterable<RouteMapOwnerLabelEntry> ownerLabels,
}) {
  return [for (final entry in ownerLabels) _ownerLabelSourceRect(entry)];
}
