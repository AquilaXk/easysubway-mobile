import 'dart:convert';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'assets/datapacks/metro_map_pack/basemap';
const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> _region(
  String suffix, {
  Object? baseVector,
  Object? baseSha = _shaA,
  Object? lineVector,
  Object? lineSha = _shaB,
  Map<String, Object?>? lines,
}) => {
  'baseVector': baseVector ?? 'seoul$suffix.vec',
  'baseVectorSha256': baseSha,
  'lines':
      lines ??
      {
        'seoul-2': {
          'svgLineSlug': '2',
          'vector': lineVector ?? 'seoul.seoul-2$suffix.vec',
          'sha256': lineSha,
        },
      },
};

Map<String, Object?> _variants({
  Map<String, Object?>? outlinedRegions,
  Map<String, Object?>? textRegions,
  Object? outlinedLabels = 'outlined-into-vec',
}) => {
  'outlined': {
    'labels': outlinedLabels,
    'regions': outlinedRegions ?? {'seoul': _region('')},
  },
  'text': {
    'labels': 'text-into-vec',
    'regions': textRegions ?? {'seoul': _region('.text')},
  },
};

String _indexJson({
  Object? schemaVersion = 2,
  Object? artifactKind = 'route-map-basemap-line-overlays',
  Object? variants,
}) => jsonEncode({
  'schemaVersion': schemaVersion,
  'artifactKind': artifactKind,
  'variants': variants ?? _variants(),
});

Matcher _rejects(String reason) => throwsA(
  isA<FormatException>().having(
    (error) => error.message,
    'message',
    contains(reason),
  ),
);

void main() {
  group('변형마다 자기 파일만 돌려준다', () {
    final index = RouteMapLineOverlayIndex.parse(_indexJson());

    test('윤곽선 변형', () {
      final files = index.variant(RouteMapBasemapVariant.outlined);

      expect(files.baseAssetFor('seoul'), '$_dir/seoul.vec');
      expect(
        files.overlayAssetFor(regionId: 'seoul', lineId: 'seoul-2'),
        '$_dir/seoul.seoul-2.vec',
      );
    });

    test('텍스트 변형', () {
      final files = index.variant(RouteMapBasemapVariant.text);

      expect(files.baseAssetFor('seoul'), '$_dir/seoul.text.vec');
      expect(
        files.overlayAssetFor(regionId: 'seoul', lineId: 'seoul-2'),
        '$_dir/seoul.seoul-2.text.vec',
      );
    });

    test('자산 계약 대조용으로 색인에 실린 파일과 sha256을 모두 낸다', () {
      expect(index.variant(RouteMapBasemapVariant.text).files, [
        (asset: '$_dir/seoul.text.vec', sha256: _shaA),
        (asset: '$_dir/seoul.seoul-2.text.vec', sha256: _shaB),
      ]);
    });
  });

  test('렌더러가 Impeller면 윤곽선 변형, 아니면 텍스트 변형을 고른다', () {
    expect(
      RouteMapBasemapVariant.forRenderer(impeller: true),
      RouteMapBasemapVariant.outlined,
    );
    expect(
      RouteMapBasemapVariant.forRenderer(impeller: false),
      RouteMapBasemapVariant.text,
    );
  });

  test('schemaVersion이 2가 아니면 읽지 않고 실패한다', () {
    for (final version in [1, 3, 0, '2', null]) {
      expect(
        () =>
            RouteMapLineOverlayIndex.parse(_indexJson(schemaVersion: version)),
        _rejects('schemaVersion'),
        reason: 'schemaVersion=$version',
      );
    }
  });

  test('다른 산출물 종류의 JSON은 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(artifactKind: 'route-map-basemap-owner-labels'),
      ),
      _rejects('route-map-basemap-owner-labels'),
    );
  });

  test('변형이 빠지거나 모르는 변형이 있으면 실패한다', () {
    final full = _variants();
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(variants: {'outlined': full['outlined']}),
      ),
      _rejects('variants'),
    );
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(variants: {...full, 'raster': full['text']}),
      ),
      _rejects('variants'),
    );
  });

  test('변형의 labels가 그 변형의 라벨 방식이 아니면 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(variants: _variants(outlinedLabels: 'text-into-vec')),
      ),
      _rejects('labels'),
    );
  });

  test('두 변형의 권역이 다르면 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(
          variants: _variants(
            textRegions: {
              'seoul': _region('.text'),
              'busan': _region('.text', baseVector: 'busan.text.vec'),
            },
          ),
        ),
      ),
      _rejects('text 변형'),
    );
  });

  test('두 변형의 같은 권역 노선이 다르면 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(
          variants: _variants(
            textRegions: {
              'seoul': _region('.text', lines: const <String, Object?>{}),
            },
          ),
        ),
      ),
      _rejects('text 변형'),
    );
  });

  test('바탕이나 노선 레이어의 sha256이 없거나 모양이 다르면 실패한다', () {
    for (final sha in [null, '', 'abc', _shaA.toUpperCase(), 7]) {
      expect(
        () => RouteMapLineOverlayIndex.parse(
          _indexJson(
            variants: _variants(
              textRegions: {'seoul': _region('.text', baseSha: sha)},
            ),
          ),
        ),
        _rejects('sha256'),
        reason: 'baseVectorSha256=$sha',
      );
      expect(
        () => RouteMapLineOverlayIndex.parse(
          _indexJson(
            variants: _variants(
              textRegions: {'seoul': _region('.text', lineSha: sha)},
            ),
          ),
        ),
        _rejects('sha256'),
        reason: 'sha256=$sha',
      );
    }
  });

  test('바탕이나 레이어 파일 이름이 바탕 폴더 밖을 가리키거나 .vec가 아니면 실패한다', () {
    for (final vector in [
      '../seoul.vec',
      'nested/seoul.seoul-2.vec',
      'seoul.seoul-2.svg',
      '',
      7,
    ]) {
      expect(
        () => RouteMapLineOverlayIndex.parse(
          _indexJson(
            variants: _variants(
              outlinedRegions: {'seoul': _region('', lineVector: vector)},
            ),
          ),
        ),
        _rejects('파일 이름'),
        reason: 'vector=$vector',
      );
      expect(
        () => RouteMapLineOverlayIndex.parse(
          _indexJson(
            variants: _variants(
              outlinedRegions: {'seoul': _region('', baseVector: vector)},
            ),
          ),
        ),
        _rejects('파일 이름'),
        reason: 'baseVector=$vector',
      );
    }
  });

  test('variants·regions·lines가 객체가 아니면 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(_indexJson(variants: <Object>[])),
      throwsFormatException,
    );
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(variants: _variants(textRegions: {'seoul': null})),
      ),
      throwsFormatException,
    );
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(
          variants: _variants(
            textRegions: {
              'seoul': {..._region('.text'), 'lines': null},
            },
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(() => RouteMapLineOverlayIndex.parse('[]'), throwsFormatException);
  });

  test('색인에 없는 권역이나 노선은 명시적 오류다', () {
    final files = RouteMapLineOverlayIndex.parse(
      _indexJson(),
    ).variant(RouteMapBasemapVariant.outlined);

    expect(
      () => files.overlayAssetFor(regionId: 'seoul', lineId: 'seoul-3'),
      throwsA(
        isA<RouteMapLineOverlayMissing>()
            .having((error) => error.regionId, 'regionId', 'seoul')
            .having((error) => error.lineId, 'lineId', 'seoul-3')
            .having(
              (error) => error.toString(),
              'crash log message',
              contains('seoul/seoul-3'),
            ),
      ),
    );
    expect(
      () => files.overlayAssetFor(regionId: 'busan', lineId: 'seoul-2'),
      throwsA(isA<RouteMapLineOverlayMissing>()),
    );
    expect(
      () => files.baseAssetFor('busan'),
      throwsA(
        isA<RouteMapBasemapRegionMissing>()
            .having((error) => error.regionId, 'regionId', 'busan')
            .having(
              (error) => error.toString(),
              'crash log message',
              contains('busan'),
            ),
      ),
    );
  });
}
