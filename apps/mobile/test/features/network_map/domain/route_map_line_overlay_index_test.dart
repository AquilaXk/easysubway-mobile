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
  String regionId = 'seoul',
  Object? baseVector,
  Object? baseSha = _shaA,
  Object? lineVector,
  Object? lineSha = _shaB,
  Map<String, Object?>? lines,
}) => {
  'baseVector': baseVector ?? '$regionId$suffix.vec',
  'baseVectorSha256': baseSha,
  'lines':
      lines ??
      {
        '$regionId-2': {
          'svgLineSlug': '2',
          'vector': lineVector ?? '$regionId.$regionId-2$suffix.vec',
          'sha256': lineSha,
        },
      },
};

/// 앱이 그리는 모든 권역을 갖춘 권역 목록. [overrides]의 권역은 그 항목으로 바꾼다.
Map<String, Object?> _regions(
  String suffix, [
  Map<String, Object?> overrides = const {},
]) => {
  for (final regionId in kRouteMapBasemapRegionToId.values)
    regionId: _region(suffix, regionId: regionId),
  ...overrides,
};

Map<String, Object?> _variants({
  Map<String, Object?>? outlinedRegions,
  Map<String, Object?>? textRegions,
  Object? outlinedLabels = 'outlined-into-vec',
}) => {
  'outlined': {
    'labels': outlinedLabels,
    'regions': outlinedRegions ?? _regions(''),
  },
  'text': {
    'labels': 'text-into-vec',
    'regions': textRegions ?? _regions('.text'),
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

RouteMapLineOverlayIndex _parse(String json) =>
    RouteMapLineOverlayIndex.parse(json);

Matcher _rejects(String reason) => throwsA(
  isA<FormatException>().having(
    (error) => error.message,
    'message',
    contains(reason),
  ),
);

void main() {
  group('권역 이름에서 바탕 권역 id를 찾는다', () {
    test('표시 이름과 저장 이름이 같은 id로 풀린다', () {
      expect(
        {
          for (final region in [
            '수도권',
            '부산',
            '부산권',
            '광주',
            '광주권',
            '대구',
            '대구권',
            '대전',
            '대전권',
          ])
            region: routeMapBasemapRegionId(region),
        },
        {
          '수도권': 'seoul',
          '부산': 'busan',
          '부산권': 'busan',
          '광주': 'gwangju',
          '광주권': 'gwangju',
          '대구': 'daegu',
          '대구권': 'daegu',
          '대전': 'daejeon',
          '대전권': 'daejeon',
        },
      );
    });

    test('앱이 그리지 않는 권역은 null이다', () {
      expect(routeMapBasemapRegionId('알 수 없음'), isNull);
      expect(routeMapBasemapRegionId(''), isNull);
    });
  });

  group('렌더러에 맞는 변형', () {
    test('Impeller는 윤곽선 라벨 변형을 그린다', () {
      expect(
        RouteMapBasemapVariant.forRenderer(impeller: true),
        RouteMapBasemapVariant.outlined,
      );
    });

    test('Skia OpenGLES는 텍스트 라벨 변형을 그린다', () {
      expect(
        RouteMapBasemapVariant.forRenderer(impeller: false),
        RouteMapBasemapVariant.text,
      );
    });
  });

  group('변형마다 자기 파일만 돌려준다', () {
    final index = _parse(_indexJson());

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
  });

  test('schemaVersion이 2가 아니면 읽지 않고 실패한다', () {
    for (final version in [1, 3, 0, '2', null]) {
      expect(
        () => _parse(_indexJson(schemaVersion: version)),
        _rejects('schemaVersion'),
        reason: 'schemaVersion=$version',
      );
    }
  });

  test('다른 산출물 종류의 JSON은 실패한다', () {
    expect(
      () => _parse(_indexJson(artifactKind: 'route-map-basemap-owner-labels')),
      _rejects('route-map-basemap-owner-labels'),
    );
  });

  test('변형이 빠지거나 모르는 변형이 있으면 실패한다', () {
    final full = _variants();
    expect(
      () => _parse(_indexJson(variants: {'outlined': full['outlined']})),
      _rejects('variants'),
    );
    expect(
      () => _parse(_indexJson(variants: {...full, 'raster': full['text']})),
      _rejects('variants'),
    );
  });

  test('변형의 labels가 그 변형의 라벨 방식이 아니면 실패한다', () {
    expect(
      () => _parse(
        _indexJson(variants: _variants(outlinedLabels: 'text-into-vec')),
      ),
      _rejects('labels'),
    );
  });

  group('변형마다 권역이 앱이 그리는 권역과 정확히 같아야 한다', () {
    test('앱이 그리는 권역이 빠진 변형이 있으면 실패한다', () {
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(outlinedRegions: _regions('')..remove('busan')),
          ),
        ),
        _rejects('variants.outlined.regions'),
      );
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(
              textRegions: _regions('.text')..remove('busan'),
            ),
          ),
        ),
        _rejects('variants.text.regions'),
      );
    });

    test('두 변형 모두 권역이 없으면 실패한다', () {
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(
              outlinedRegions: const <String, Object?>{},
              textRegions: const <String, Object?>{},
            ),
          ),
        ),
        _rejects('variants.outlined.regions'),
      );
    });

    test('앱이 그리지 않는 권역이 있으면 실패한다', () {
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(
              textRegions: _regions('.text', {
                'incheon': _region('.text', regionId: 'incheon'),
              }),
            ),
          ),
        ),
        _rejects('variants.text.regions'),
      );
    });
  });

  test('한 .vec 파일을 두 항목이 함께 가리키면 실패한다', () {
    expect(
      () => _parse(
        _indexJson(
          variants: _variants(
            textRegions: _regions('.text', {
              'seoul': _region('.text', baseVector: 'seoul.vec'),
            }),
          ),
        ),
      ),
      _rejects('seoul.vec'),
    );
    expect(
      () => _parse(
        _indexJson(
          variants: _variants(
            textRegions: _regions('.text', {
              'seoul': _region('.text', lineVector: 'seoul.seoul-2.vec'),
            }),
          ),
        ),
      ),
      _rejects('seoul.seoul-2.vec'),
    );
  });

  test('두 변형의 같은 권역 노선이 다르면 실패한다', () {
    expect(
      () => _parse(
        _indexJson(
          variants: _variants(
            textRegions: _regions('.text', {
              'seoul': _region('.text', lines: const <String, Object?>{}),
            }),
          ),
        ),
      ),
      _rejects('text 변형'),
    );
  });

  test('바탕이나 노선 레이어의 sha256이 없거나 모양이 다르면 실패한다', () {
    for (final sha in [null, '', 'abc', _shaA.toUpperCase(), 7]) {
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(
              textRegions: _regions('.text', {
                'seoul': _region('.text', baseSha: sha),
              }),
            ),
          ),
        ),
        _rejects('sha256'),
        reason: 'baseVectorSha256=$sha',
      );
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(
              textRegions: _regions('.text', {
                'seoul': _region('.text', lineSha: sha),
              }),
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
        () => _parse(
          _indexJson(
            variants: _variants(
              outlinedRegions: _regions('', {
                'seoul': _region('', lineVector: vector),
              }),
            ),
          ),
        ),
        _rejects('파일 이름'),
        reason: 'vector=$vector',
      );
      expect(
        () => _parse(
          _indexJson(
            variants: _variants(
              outlinedRegions: _regions('', {
                'seoul': _region('', baseVector: vector),
              }),
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
      () => _parse(_indexJson(variants: <Object>[])),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _indexJson(
          variants: _variants(textRegions: _regions('.text', {'seoul': null})),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => _parse(
        _indexJson(
          variants: _variants(
            textRegions: _regions('.text', {
              'seoul': {..._region('.text'), 'lines': null},
            }),
          ),
        ),
      ),
      throwsFormatException,
    );
    expect(() => _parse('[]'), throwsFormatException);
  });

  test('색인에 없는 노선은 명시적 오류이고 앱 권역이 아닌 권역 조회는 호출 오류다', () {
    final files = _parse(_indexJson()).variant(RouteMapBasemapVariant.outlined);

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
      files.overlayAssetFor(regionId: 'busan', lineId: 'busan-2'),
      '$_dir/busan.busan-2.vec',
    );
    expect(() => files.baseAssetFor('incheon'), throwsArgumentError);
  });
}
