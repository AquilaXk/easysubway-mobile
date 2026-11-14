import 'dart:typed_data';

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_aligner.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_selection.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_spatial_index.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_label_polygon.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_parallel_offsets.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/infrastructure/cached_route_map_path.dart';
import 'package:easysubway_mobile/features/network_map/presentation/network_map_geometry.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_hit_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkMapStation _station({
  required String id,
  required String lineId,
  required int x,
  required int y,
  String labelPolygon = '',
}) {
  return NetworkMapStation(
    id: id,
    nameKo: id,
    nameEn: id,
    region: '수도권',
    lineId: lineId,
    stationCode: '100',
    sequence: 1,
    position: NetworkMapPosition(
      x: x,
      y: y,
      labelDx: 0,
      labelDy: 0,
      labelPolygon: labelPolygon,
      upPath: '',
      downPath: '',
      sourceId: 'fixture',
    ),
  );
}

void main() {
  group('ParsedRouteMapLabelPolygon cache', () {
    test('Float32List 좌표와 AABB bounds를 1회 파싱 후 캐시한다', () {
      const raw =
          '[{"x":10,"y":20},{"x":30,"y":20},{"x":30,"y":40},{"x":10,"y":40}]';
      final first = parseRouteMapLabelPolygonData(raw);
      final second = parseRouteMapLabelPolygonData(raw);

      expect(first, isNotNull);
      expect(second, same(first));
      expect(first!.coordinates, isA<Float32List>());
      expect(first.coordinates, <double>[10, 20, 30, 20, 30, 40, 10, 40]);
      expect(first.pointCount, 4);
      expect(first.pointAt(2), const Offset(30, 40));
      expect(first.bounds, const Rect.fromLTRB(10, 20, 30, 40));
      expect(first.toOffsetList(), parseRouteMapLabelPolygon(raw));
    });

    test('비유효, 음수 또는 과대 labelPolygon 입력은 거부한다', () {
      expect(parseRouteMapLabelPolygonData(''), isNull);
      expect(
        parseRouteMapLabelPolygonData('[{"x":0,"y":0},{"x":1,"y":1}]'),
        isNull,
      );
      expect(
        parseRouteMapLabelPolygonData(
          '[{"x":-1,"y":0},{"x":1,"y":0},{"x":1,"y":1}]',
        ),
        isNull,
      );
      expect(parseRouteMapLabelPolygonData('not json'), isNull);
      final oversized = List.generate(
        3000,
        (index) => '{"x":$index,"y":${index + 1}}',
      ).join(',');
      expect(parseRouteMapLabelPolygonData('[$oversized]'), isNull);
    });

    test(
      'NetworkMapPosition.fromJson과 copyWith가 parsedLabelPolygon을 유지·갱신한다',
      () {
        final pos = NetworkMapPosition.fromJson(<String, Object?>{
          'x': 100,
          'y': 200,
          'labelDx': 0,
          'labelDy': 0,
          'labelPolygon':
              '[{"x":90,"y":190},{"x":130,"y":190},{"x":130,"y":210},{"x":90,"y":210}]',
          'upPath': '',
          'downPath': '',
          'sourceId': 'fixture',
        });

        final initial = pos.parsedLabelPolygon;
        expect(initial, isNotNull);
        expect(initial!.bounds, const Rect.fromLTRB(90, 190, 130, 210));

        final moved = pos.copyWith(x: 105);
        expect(moved.parsedLabelPolygon, same(initial));

        final relabeled = pos.copyWith(
          labelPolygon:
              '[{"x":0,"y":0},{"x":20,"y":0},{"x":20,"y":10},{"x":0,"y":10}]',
        );
        expect(relabeled.parsedLabelPolygon, isNotNull);
        expect(
          relabeled.parsedLabelPolygon!.bounds,
          const Rect.fromLTRB(0, 0, 20, 10),
        );
      },
    );

    test('geometry와 station hit scoring이 캐시된 Float32List 다각형과 일치한다', () {
      const polygon =
          '[{"x":120,"y":120},{"x":180,"y":120},{"x":180,"y":150},{"x":120,"y":150}]';
      final station = _station(
        id: 'station-poly',
        lineId: 'line-1',
        x: 100,
        y: 100,
        labelPolygon: polygon,
      );
      final geometry = NetworkMapGeometry.fromStations(
        [station],
        stationSourceBoundsFor:
            NetworkMapStationHitGeometry.sourceBoundsForStation,
        stationKeyFor: NetworkMapStationHitGeometry.stationKeyFor,
      );
      final hitGeometry = NetworkMapStationHitGeometry(geometry: geometry);

      final bounds = hitGeometry.sourceBoundsFor(station);
      expect(bounds.left, closeTo(100 - geometry.origin.dx - 24, 0.01));
      expect(bounds.right, closeTo(180 - geometry.origin.dx, 0.01));
      expect(bounds.bottom, closeTo(150 - geometry.origin.dy, 0.01));

      final camera = MapCameraState(
        sourceBounds: Rect.fromLTWH(0, 0, geometry.width, geometry.height),
        viewportSize: const Size(400, 400),
        center: Offset(geometry.width / 2, geometry.height / 2),
        scale: 1,
        minScale: 0.5,
        maxScale: 4,
        revision: 0,
      );

      final hitInsideLabel = hitGeometry.stationAtViewportPosition(
        camera.sourceToViewportPoint(
          Offset(150 - geometry.origin.dx, 135 - geometry.origin.dy),
        ),
        camera: camera,
      );
      expect(hitInsideLabel?.id, 'station-poly');

      final edgeDistanceHit = hitGeometry.stationAtViewportPosition(
        camera.sourceToViewportPoint(
          Offset(182 - geometry.origin.dx, 135 - geometry.origin.dy),
        ),
        camera: camera,
      );
      expect(edgeDistanceHit?.id, 'station-poly');
    });
  });

  group('64-bit packed grid key & negative coordinates', () {
    test('packRouteMapGridKey는 음수 좌표를 비트 충돌 없이 구분한다', () {
      final keys = <int>{
        packRouteMapGridKey(0, 0),
        packRouteMapGridKey(-1, 1),
        packRouteMapGridKey(1, -1),
        packRouteMapGridKey(-1, -1),
        packRouteMapGridKey(0, -1),
        packRouteMapGridKey(-1, 0),
        packRouteMapGridKey(-2147483648, 2147483647),
      };
      expect(keys, hasLength(7));
    });

    test('NetworkMapStationSpatialIndex는 음수 좌표 버킷 조회와 순서를 보존한다', () {
      final s1 = _station(id: 'neg-1', lineId: 'line-1', x: -300, y: -520);
      final s2 = _station(id: 'neg-2', lineId: 'line-1', x: -250, y: -490);
      final s3 = _station(id: 'pos-1', lineId: 'line-1', x: 300, y: 520);

      final index = NetworkMapStationSpatialIndex.fromStations(
        [s1, s2, s3],
        sourceBoundsForStation: (s) => Rect.fromCircle(
          center: Offset(s.position.x.toDouble(), s.position.y.toDouble()),
          radius: 18,
        ),
        stationKeyFor: NetworkMapStationHitGeometry.stationKeyFor,
      );

      final negativeHits = index.query(
        const Rect.fromLTRB(-350, -560, -220, -460),
      );
      expect(negativeHits.map((s) => s.id), ['neg-1', 'neg-2']);

      final positiveHits = index.query(const Rect.fromLTRB(260, 480, 340, 560));
      expect(positiveHits.map((s) => s.id), ['pos-1']);
    });

    test('applyRouteMapParallelOffsets는 음수 정점과 대칭 좌표를 구분한다', () {
      final offsets = routeMapParallelLineOffsets(const [
        RouteMapLineGeometry(
          lineId: 'A',
          polylines: [
            [Offset(-100, 100), Offset(-90, 100)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'B',
          polylines: [
            [Offset(-100, 100), Offset(-90, 100)],
          ],
        ),
        RouteMapLineGeometry(
          lineId: 'C',
          polylines: [
            [Offset(100, -100), Offset(110, -100)],
          ],
        ),
      ]);

      expect(offsets['A']!.first, const [Offset(0, -0.5), Offset(0, -0.5)]);
      expect(offsets['B']!.first, const [Offset(0, 0.5), Offset(0, 0.5)]);
      expect(offsets['C']!.first, const [Offset.zero, Offset.zero]);
    });
  });

  group('O(1) station lookup & pre-hoisted parsers', () {
    test('NetworkMapStationLookup은 byId와 byIdentity에서 기존 함수와 동일하다', () {
      final s1Line1 = _station(id: 'st-1', lineId: 'line-1', x: 10, y: 10);
      final s1Line2 = _station(id: 'st-1', lineId: 'line-2', x: 20, y: 20);
      final s2Line2 = _station(id: 'st-2', lineId: 'line-2', x: 30, y: 30);
      final stations = [s1Line1, s1Line2, s2Line2];

      final lookup = NetworkMapStationLookup.fromStations(stations);

      expect(lookup.byId(null), isNull);
      expect(lookup.byId('missing'), isNull);
      expect(
        lookup.byId('st-1'),
        same(networkMapStationById(stations, 'st-1')),
      );
      expect(
        lookup.byId('st-2'),
        same(networkMapStationById(stations, 'st-2')),
      );

      expect(lookup.byIdentity(null), isNull);
      expect(
        lookup.byIdentity(s1Line2),
        same(networkMapStationByIdentity(stations, s1Line2)),
      );
      expect(
        lookup.byIdentity(_station(id: 'st-1', lineId: 'line-9', x: 0, y: 0)),
        isNull,
      );
      expect(NetworkMapStationLookup.empty.byId('st-1'), isNull);
    });

    test('호이스팅된 정규식 파서와 SVG 경로 캐시가 정확히 동작한다', () {
      expect(parseRouteMapPolyline('M -12.5 34.25 L 0 -8.5'), const [
        Offset(-12.5, 34.25),
        Offset(0, -8.5),
      ]);
      final cached = cachedRouteMapPath('M 0 0 L 10 0 L 10 20 Z', Offset.zero);
      expect(cached.bounds, const Rect.fromLTRB(0, 0, 10, 20));
      expect(normalizeStationNameForBasemap('석남(거북시장)'), '석남');
    });

    test('labelPolygon과 SVG 경로 캐시는 LRU 상한 초과 시 오래된 항목을 제거한다', () {
      final firstPolyRaw = '[{"x":0,"y":0},{"x":1,"y":0},{"x":0,"y":1}]';
      final firstPoly = parseRouteMapLabelPolygonData(firstPolyRaw);
      expect(firstPoly, isNotNull);
      for (var i = 1; i <= 4100; i++) {
        parseRouteMapLabelPolygonData(
          '[{"x":0,"y":0},{"x":$i,"y":0},{"x":0,"y":1}]',
        );
      }
      final reparsedPoly = parseRouteMapLabelPolygonData(firstPolyRaw);
      expect(reparsedPoly, isNotNull);
      expect(identical(reparsedPoly, firstPoly), isFalse);

      const firstPathRaw = 'M 0 0 L 1 10 L 0 20 Z';
      final firstPath = cachedRouteMapPath(firstPathRaw, Offset.zero);
      for (var i = 2; i <= 1030; i++) {
        cachedRouteMapPath('M 0 0 L $i 10 L 0 20 Z', Offset.zero);
      }
      final reparsedPath = cachedRouteMapPath(firstPathRaw, Offset.zero);
      expect(identical(reparsedPath, firstPath), isFalse);
    });
  });
}
