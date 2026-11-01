import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_owner_labels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_index.dart';
import '../../../support/basemap_vec_draws.dart';

// #2068 바탕층 라벨 paint-order 회귀 게이트(컴파일 .vec 그리기 순서 실측).
//
// [막는 회귀] 오너 SVG의 역명 라벨은 `paint-order:stroke fill` + 흰 halo를 쓴다
// (busan `.station-name` stroke 5.747px, daegu 5px, daejeon·gwangju
//  `#station-name-labels-layer text` stroke 4px). 흰 stroke가 글자 fill보다 **나중에**
// 그려지면 글자 속을 덮어 속이 빈 유령 글자가 된다 — 오너 실기기 실측에서 대구는
// 역명이 화면에서 사실상 소멸했고 부산은 일반역명이 파편화됐다.
//
// 앱은 렌더러에 맞는 변형 하나를 그리므로(route_map_line_overlay_index.dart) 두 변형을
// 모두 본다. 텍스트 변형은 텍스트 draw의 그리기 순서로, 윤곽선 변형은 윤곽 좌표로 본다.
//
// [텍스트 변형] 같은 글자·같은 펜 위치에 stroke 전용 draw와 fill 전용 draw가 짝으로
// 있으면 stroke가 먼저여야 한다.
//
// [윤곽선 변형] data #1488이 라벨 `<text>`를 참조 서체의 글리프 윤곽선
// path로 굽고, data #1495가 같은 paint의 인접 path를 한 path로 이었다. `.vec`에는
// 텍스트 draw가 없고(route_map_basemap_draw_budget_test가 0건으로 못 박는다), 라벨은
// path draw 안의 윤곽(subpath)이다. halo(stroke)와 글자(fill)는 **같은 윤곽 좌표**를
// 칠하지만 묶음 경계는 서로 다를 수 있다(halo는 선 굵기만큼 넓어 묶음 규칙이 달리
// 적용된다). 그래서 path 단위가 아니라 윤곽 좌표를 열쇠로 둘을 잇는다.
//
// [무엇을 보나] 라벨 위치의 진실은 labels.json이다(접근성·히트 테스트도 이 sidecar와
// 구조화 데이터에서 온다). 라벨 런마다 앵커 주변 상자 안에 든 흰색 아닌 fill 윤곽을
// 그 라벨의 글자로 보고,
//   1) 상자 안 윤곽 수가 라벨 글자 수(공백 제외) 이상이어야 하고(라벨이 빠지지 않았다.
//      글자 하나는 윤곽 하나 이상이다),
//   2) 글자 윤곽과 같은 좌표의 흰 stroke(halo)는 글자보다 먼저 그려져야 한다.
// 래스터·폰트·배경과 무관하고 맞춘 상수는 권역별 halo 라벨 런 수뿐이다.
//
// 컴파일 입력 층위(분해가 일어났는가·두 사본이 paint 외 동일한가)는
// tools/route-map/basemap-paint-order-gate.test.mjs가 따로 고정한다. 이 게이트는
// 그 분해가 **배포 바이트까지 순서 그대로 살아남았는지**를 본다.

String _basemapAsset(RouteMapBasemapVariant variant, String regionId) =>
    bundledBasemapIndex.variant(variant).baseAssetFor(regionId);

// 텍스트 변형 실측 기준선(data pipelineRevision 8). halo/글자 짝의 수이며 세는 단위는
// 텍스트 런이다. 다줄 라벨은 tspan마다 draw가 하나씩 나와 `<text>` 요소 수(부산 147·
// 대구 97)보다 크다. seoul은 라벨 CSS가 stroke를 주지 않아 짝이 없다.
const _expectedTextHaloPairs = <String, int>{
  'seoul': 0,
  'busan': 155,
  'daegu': 104,
  'daejeon': 22,
  'gwangju': 20,
};

/// 같은 글자·같은 펜 위치를 가리키는 키(부동소수 흔들림을 흡수한다).
String _penKey(BasemapVecTextDraw draw) =>
    '${draw.text}@${draw.x.toStringAsFixed(3)},${draw.y.toStringAsFixed(3)}';

/// 텍스트 변형 한 권역의 halo/글자 짝 수와, halo가 글자보다 뒤에 그려진 라벨.
({int pairs, List<String> haloAfterGlyph}) _textHaloOrder(
  List<BasemapVecTextDraw> draws,
) {
  final byPen = <String, List<BasemapVecTextDraw>>{};
  for (final draw in draws) {
    byPen.putIfAbsent(_penKey(draw), () => <BasemapVecTextDraw>[]).add(draw);
  }
  var pairs = 0;
  final haloAfterGlyph = <String>[];
  for (final group in byPen.values) {
    final halos = group.where((draw) => draw.hasStroke && !draw.hasFill);
    final glyphs = group.where((draw) => draw.hasFill && !draw.hasStroke);
    if (halos.isEmpty || glyphs.isEmpty) continue;
    pairs += 1;
    final firstHalo = halos.first.index;
    final firstGlyph = glyphs.first.index;
    if (firstHalo > firstGlyph) {
      haloAfterGlyph.add(
        '"${group.first.text}": halo draw #$firstHalo이 글자 draw #$firstGlyph보다 뒤다.',
      );
    }
  }
  return (pairs: pairs, haloAfterGlyph: haloAfterGlyph);
}

BasemapVecTextDraw _textDraw(int index, {required bool stroke}) =>
    BasemapVecTextDraw(
      index: index,
      text: '가',
      x: 10,
      y: 20,
      hasFill: !stroke,
      hasStroke: stroke,
    );

// 라벨 상자 계수. 글자 폭 상한은 글자 수 × 글자 크기 × 1.15(전각 + 자간), 높이는
// 기준선 위 1.15em·아래 0.35em, 가로 여유는 0.3em이다. 상자가 넓어 이웃 라벨이나
// 기호의 윤곽이 걸릴 수 있다. 그래서 1)은 윤곽이 있는지가 아니라 글자 수만큼 있는지를
// 본다. halo 순서 판정은 걸린 윤곽도 라벨 글자라 영향이 없다.
const _widthPerEm = 1.15;
const _ascentEm = 1.15;
const _descentEm = 0.35;
const _slackEm = 0.3;

// 윤곽선 변형 실측 기준선(data pipelineRevision 8). halo가 붙은 라벨 런의 수다.
// 라벨 런은 `<text>` 한 줄이며 다줄 라벨은 줄마다 센다(busan 147개 중 8개가 2줄 → 155).
//   busan·daegu     : `.station-name`/`.transfer-name` 클래스 규칙이 stroke를 준다.
//   daejeon·gwangju : `#station-name-labels-layer text` **자손 결합자** 규칙이
//     stroke를 준다.
//   seoul           : 라벨 CSS가 stroke를 주지 않아 halo가 없다. 1건은 `김포공항` 라벨
//     상자 안에 든 공항 아이콘 윤곽이다(아이콘 path는 stroke 사본이 먼저 그려진다).
const _expectedHaloedRuns = <String, int>{
  'seoul': 1,
  'busan': 155,
  'daegu': 104,
  'daejeon': 22,
  'gwangju': 20,
};

class _LabelRun {
  _LabelRun({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  factory _LabelRun.of(
    RouteMapOwnerLabelEntry entry,
    String text,
    double x,
    double y,
  ) {
    final fontSize = entry.fontSizePx;
    final width = text.length * fontSize * _widthPerEm;
    final slack = _slackEm * fontSize;
    final (left, right) = switch (entry.anchor) {
      RouteMapOwnerLabelAnchor.start => (x - slack, x + width + slack),
      RouteMapOwnerLabelAnchor.middle => (
        x - width / 2 - slack,
        x + width / 2 + slack,
      ),
      RouteMapOwnerLabelAnchor.end => (x - width - slack, x + slack),
    };
    return _LabelRun(
      text: text,
      left: left,
      right: right,
      top: y - _ascentEm * fontSize,
      bottom: y + _descentEm * fontSize,
    );
  }

  final String text;

  /// 공백을 뺀 글자 수. 글자 하나는 윤곽 하나 이상으로 그려진다.
  int get glyphCount => text.replaceAll(RegExp(r'\s'), '').runes.length;

  final double left;
  final double right;
  final double top;
  final double bottom;

  bool contains(BasemapVecContour contour) =>
      contour.minX >= left &&
      contour.maxX <= right &&
      contour.minY >= top &&
      contour.maxY <= bottom;
}

/// labels.json 한 권역의 라벨 런. 다줄 라벨은 줄마다, 한 줄 라벨은 역명 하나가 런이다.
List<_LabelRun> _labelRuns(String regionId) {
  final entries = parseRouteMapOwnerLabelsForRegion(
    File(kRouteMapOwnerLabelsAssetPath).readAsStringSync(),
    regionId,
  );
  return [
    for (final entry in entries.values.expand((list) => list))
      if (entry.lines.isEmpty)
        _LabelRun.of(entry, entry.station, entry.position.dx, entry.position.dy)
      else
        for (final line in entry.lines)
          _LabelRun.of(entry, line.text, line.position.dx, line.position.dy),
  ];
}

/// 한 권역 .vec를 labels.json의 라벨 런과 맞춰 읽은 결과.
class _LabelPaintOrder {
  _LabelPaintOrder(this.draws, this.runs) {
    final fillDrawOfKey = <String, int>{};
    final haloDrawsOfKey = <String, List<int>>{};
    final inkContours = <BasemapVecContour>[];
    for (final draw in draws) {
      for (final contour in draw.contours) {
        if (draw.isStroke) {
          if (draw.isOpaqueWhite) {
            haloDrawsOfKey
                .putIfAbsent(contour.key, () => <int>[])
                .add(draw.index);
          }
        } else if (!draw.isOpaqueWhite) {
          fillDrawOfKey.putIfAbsent(contour.key, () => draw.index);
          inkContours.add(contour);
        }
      }
    }

    for (final run in runs) {
      final ink = inkContours.where(run.contains).toList();
      if (ink.length < run.glyphCount) {
        runsMissingGlyphs.add(run.text);
        continue;
      }
      var haloed = false;
      for (final contour in ink) {
        final halos = haloDrawsOfKey[contour.key];
        if (halos == null) continue;
        haloed = true;
        final glyphDraw = fillDrawOfKey[contour.key]!;
        if (halos.first > glyphDraw) {
          haloAfterGlyph.add(
            '${run.text}: halo draw #${halos.first}이 글자 draw #$glyphDraw보다 뒤다.',
          );
        }
      }
      if (haloed) haloedRuns += 1;
    }
  }

  final List<BasemapVecPathDraw> draws;
  final List<_LabelRun> runs;

  /// 앵커 상자 안 글자 윤곽이 라벨 글자 수보다 적은 라벨 런.
  final List<String> runsMissingGlyphs = <String>[];

  /// 글자 윤곽과 같은 좌표의 흰 stroke(halo)가 있는 라벨 런 수.
  int haloedRuns = 0;

  /// halo가 같은 좌표의 글자보다 뒤에 그려진 라벨(흰 halo가 글자를 덮는다).
  final List<String> haloAfterGlyph = <String>[];
}

BasemapVecPathDraw _syntheticDraw(
  int index, {
  required bool stroke,
  required int color,
  List<double> glyphPoints = const [100, 90, 140, 90, 140, 110, 100, 110],
}) => BasemapVecPathDraw(
  index: index,
  isStroke: stroke,
  color: color,
  contours: [BasemapVecContour(glyphPoints)],
);

final _syntheticRun = _LabelRun(
  text: '가',
  left: 90,
  right: 150,
  top: 80,
  bottom: 120,
);

const _white = 0xffffffff;
const _ink = 0xff14293d;

void main() {
  test('#2068 텍스트 변형 halo(stroke) 사본이 글자(fill) 사본보다 먼저 그려진다 — 5권역 전수', () {
    final failures = <String>[];
    final summary = <String>[];

    for (final MapEntry(key: region, value: expectedPairs)
        in _expectedTextHaloPairs.entries) {
      final draws = basemapVecTextDraws(
        _basemapAsset(RouteMapBasemapVariant.text, region),
      );
      expect(
        draws,
        isNotEmpty,
        reason: '$region: .vec에서 텍스트 draw를 하나도 못 읽었다 — 디코더가 죽었다',
      );
      final order = _textHaloOrder(draws);
      failures.addAll(
        order.haloAfterGlyph.map(
          (message) => '$region/$message 흰 halo가 글자를 덮어 유령 글자가 된다.',
        ),
      );
      if (order.pairs != expectedPairs) {
        failures.add(
          '$region: halo/글자 짝 ${order.pairs}건(기준 $expectedPairs). 라벨 halo가 '
          '빠졌는지·중복인지 먼저 규명하고 정당한 변화면 기준선을 실측으로 갱신하세요.',
        );
      }
      summary.add('$region: 짝 ${order.pairs}건 / 텍스트 draw ${draws.length}건');
    }

    // ignore: avoid_print
    print('[label-paint-order text] ${summary.join(' · ')}');
    expect(
      failures,
      isEmpty,
      reason: '텍스트 변형 라벨 그리기 순서가 어긋났다:\n${failures.join('\n')}',
    );
  });

  test('#2068 윤곽선 변형 halo(stroke) 윤곽이 글자(fill) 윤곽보다 먼저 그려진다 — 5권역 전수', () {
    final failures = <String>[];
    final summary = <String>[];

    for (final entry in _expectedHaloedRuns.entries) {
      final region = entry.key;
      final draws = basemapVecPathDraws(
        _basemapAsset(RouteMapBasemapVariant.outlined, region),
      );
      expect(
        draws,
        isNotEmpty,
        reason: '$region: .vec에서 path draw를 하나도 못 읽었다 — 디코더가 죽었다',
      );
      final runs = _labelRuns(region);
      expect(runs, isNotEmpty, reason: '$region: labels.json에 라벨이 없다');
      final order = _LabelPaintOrder(draws, runs);

      failures
        ..addAll(
          order.runsMissingGlyphs.map(
            (text) =>
                '$region/"$text": 앵커 주변 글자 윤곽이 글자 수보다 적다. 라벨 글자가 .vec에서 빠졌다.',
          ),
        )
        ..addAll(
          order.haloAfterGlyph.map(
            (message) => '$region/$message 흰 halo가 글자를 덮어 유령 글자가 된다.',
          ),
        );
      if (order.haloedRuns != entry.value) {
        failures.add(
          '$region: halo가 붙은 라벨 런 ${order.haloedRuns}건(기준 ${entry.value}). '
          '라벨 halo가 빠졌는지 먼저 규명하고 정당한 변화면 기준선을 실측으로 갱신하세요.',
        );
      }
      summary.add(
        '$region: 라벨 런 ${runs.length}건 중 halo ${order.haloedRuns}건 / path draw ${draws.length}건',
      );
    }

    // ignore: avoid_print
    print('[label-paint-order outlined] ${summary.join(' · ')}');
    expect(
      failures,
      isEmpty,
      reason: '바탕층 라벨 그리기 순서가 어긋났다:\n${failures.join('\n')}',
    );
  });

  group('텍스트 변형 순서 판독', () {
    test('halo가 글자보다 먼저면 짝으로 세고 위반이 없다', () {
      final order = _textHaloOrder([
        _textDraw(0, stroke: true),
        _textDraw(1, stroke: false),
      ]);

      expect(order.pairs, 1);
      expect(order.haloAfterGlyph, isEmpty);
    });

    test('글자가 halo보다 먼저면 흰 halo가 글자를 덮는 위반으로 잡는다', () {
      final order = _textHaloOrder([
        _textDraw(0, stroke: false),
        _textDraw(1, stroke: true),
      ]);

      expect(order.haloAfterGlyph, hasLength(1));
    });

    test('halo 없이 글자만 있으면 짝으로 세지 않는다', () {
      expect(_textHaloOrder([_textDraw(0, stroke: false)]).pairs, 0);
    });
  });

  group('윤곽선 변형 순서 판독', () {
    test('halo가 글자보다 먼저면 halo 라벨로 세고 위반이 없다', () {
      final order = _LabelPaintOrder(
        [
          _syntheticDraw(0, stroke: true, color: _white),
          _syntheticDraw(1, stroke: false, color: _ink),
        ],
        [_syntheticRun],
      );

      expect(order.haloedRuns, 1);
      expect(order.haloAfterGlyph, isEmpty);
      expect(order.runsMissingGlyphs, isEmpty);
    });

    test('글자가 halo보다 먼저면 흰 halo가 글자를 덮는 위반으로 잡는다', () {
      final order = _LabelPaintOrder(
        [
          _syntheticDraw(0, stroke: false, color: _ink),
          _syntheticDraw(1, stroke: true, color: _white),
        ],
        [_syntheticRun],
      );

      expect(order.haloAfterGlyph, hasLength(1));
    });

    test('앵커 주변에 글자 윤곽이 없으면 라벨이 빠진 것으로 잡는다', () {
      final order = _LabelPaintOrder(
        [
          _syntheticDraw(
            0,
            stroke: false,
            color: _ink,
            glyphPoints: const [900, 900, 940, 900, 940, 920, 900, 920],
          ),
        ],
        [_syntheticRun],
      );

      expect(order.runsMissingGlyphs, ['가']);
    });

    test('상자 안 윤곽이 글자 수보다 적으면 다른 윤곽이 걸려 있어도 라벨이 빠진 것으로 잡는다', () {
      final order = _LabelPaintOrder(
        [_syntheticDraw(0, stroke: false, color: _ink)],
        [
          _LabelRun(
            text: '가나',
            left: _syntheticRun.left,
            right: _syntheticRun.right,
            top: _syntheticRun.top,
            bottom: _syntheticRun.bottom,
          ),
        ],
      );

      expect(order.runsMissingGlyphs, ['가나']);
    });
  });
}
