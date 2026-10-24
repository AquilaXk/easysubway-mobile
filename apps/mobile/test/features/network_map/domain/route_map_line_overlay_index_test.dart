import 'dart:convert';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:flutter_test/flutter_test.dart';

String _indexJson({
  Object? schemaVersion = 1,
  Object? artifactKind = 'route-map-basemap-line-overlays',
  Object? vector = 'seoul.seoul-2.vec',
}) => jsonEncode({
  'schemaVersion': schemaVersion,
  'artifactKind': artifactKind,
  'regions': {
    'seoul': {
      'baseVector': 'seoul.vec',
      'lines': {
        'seoul-2': {'svgLineSlug': 'line2', 'vector': vector},
      },
    },
  },
});

void main() {
  test('색인의 노선 레이어 파일을 바탕 자산 폴더 경로로 돌려준다', () {
    final index = RouteMapLineOverlayIndex.parse(_indexJson());

    expect(
      index.overlayAssetFor(regionId: 'seoul', lineId: 'seoul-2'),
      'assets/datapacks/metro_map_pack/basemap/seoul.seoul-2.vec',
    );
  });

  test('schemaVersion이 1이 아니면 읽지 않고 실패한다', () {
    for (final version in [2, 0, '1', null]) {
      expect(
        () =>
            RouteMapLineOverlayIndex.parse(_indexJson(schemaVersion: version)),
        throwsFormatException,
        reason: 'schemaVersion=$version',
      );
    }
  });

  test('다른 산출물 종류의 JSON은 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(
        _indexJson(artifactKind: 'route-map-basemap-owner-labels'),
      ),
      throwsFormatException,
    );
  });

  test('레이어 파일 이름이 바탕 폴더 밖을 가리키거나 .vec가 아니면 실패한다', () {
    for (final vector in [
      '../seoul.vec',
      'nested/seoul.seoul-2.vec',
      'seoul.seoul-2.svg',
      '',
      7,
    ]) {
      expect(
        () => RouteMapLineOverlayIndex.parse(_indexJson(vector: vector)),
        throwsFormatException,
        reason: 'vector=$vector',
      );
    }
  });

  test('regions나 lines가 객체가 아니면 실패한다', () {
    expect(
      () => RouteMapLineOverlayIndex.parse(
        jsonEncode({
          'schemaVersion': 1,
          'artifactKind': 'route-map-basemap-line-overlays',
          'regions': <Object>[],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => RouteMapLineOverlayIndex.parse(
        jsonEncode({
          'schemaVersion': 1,
          'artifactKind': 'route-map-basemap-line-overlays',
          'regions': {
            'seoul': {'baseVector': 'seoul.vec', 'lines': null},
          },
        }),
      ),
      throwsFormatException,
    );
    expect(() => RouteMapLineOverlayIndex.parse('[]'), throwsFormatException);
  });

  test('색인에 없는 노선이나 권역은 명시적 오류다', () {
    final index = RouteMapLineOverlayIndex.parse(_indexJson());

    expect(
      () => index.overlayAssetFor(regionId: 'seoul', lineId: 'seoul-3'),
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
      () => index.overlayAssetFor(regionId: 'busan', lineId: 'seoul-2'),
      throwsA(isA<RouteMapLineOverlayMissing>()),
    );
  });
}
