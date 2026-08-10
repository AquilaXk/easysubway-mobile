import 'dart:ui' show Offset, Rect;

import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_label_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network map models preserve JSON defaults, order, and labels', () {
    final data = NetworkMapData.fromJson(<String, Object?>{
      'regions': <Object?>[
        <String, Object?>{'name': '부산권'},
        'not-an-object',
        <String, Object?>{'name': '수도권'},
      ],
      'selectedRegion': '부산권',
      'lines': <Object?>[
        <String, Object?>{
          'id': 'line-2',
          'name': '수도권 2호선',
          'color': '#00AA00',
          'region': '수도권',
        },
        <String, Object?>{'id': 'gtx-a', 'nameKo': 'GTX-A'},
      ],
      'stations': <Object?>[
        <String, Object?>{
          'id': 'station-a',
          'nameKo': '시청',
          'nameEn': 'City Hall',
          'region': '수도권',
          'lineId': 'line-2',
          'stationCode': '201',
          'sequence': 3,
          'position': <String, Object?>{
            'x': 10,
            'y': 20,
            'labelDx': 4,
            'labelDy': -2,
            'labelPolygon': '[{"x":1,"y":2},{"x":3,"y":4},{"x":5,"y":6}]',
            'upPath': 'M 0 0',
            'downPath': 'M 1 1',
            'sourceId': 'source-a',
          },
        },
      ],
      'edges': <Object?>[
        <String, Object?>{
          'id': 'edge-a',
          'lineId': 'line-2',
          'fromStationId': 'station-a',
          'toStationId': 'station-b',
          'accessibilityStatus': 'AVAILABLE',
          'reliabilityScore': 95,
        },
      ],
      'positionSources': <Object?>[
        <String, Object?>{
          'id': 'source-a',
          'name': 'source',
          'licenseStatus': 'APPROVED',
        },
      ],
      'stationLineMemberships': <Object?>[
        <String, Object?>{'stationId': 'station-a', 'lineId': 'line-2'},
      ],
      'lineTracks': <Object?>[
        <String, Object?>{
          'lineId': 'line-2',
          'paths': <Object?>['M 10 20 L 30 40', 'M 50 60 L 70 80'],
        },
      ],
    });

    expect(data.regions.map((region) => region.name), <String>['부산권', '수도권']);
    expect(data.regions.first.displayName, '부산');
    expect(data.lines.map((line) => line.id), <String>['line-2', 'gtx-a']);
    expect(data.lines.first.shortName, '2호선');
    expect(data.lines.first.badgeText, '2');
    expect(data.lines.last.badgeText, 'A');
    expect(data.stations.single.displayName, '시청역');
    expect(data.stations.single.position.labelDx, 4);
    expect(data.edges.single.accessibilityStatus, 'AVAILABLE');
    expect(data.positionSources.single.licenseStatus, 'APPROVED');
    expect(data.stationLineMemberships.single.lineId, 'line-2');
    expect(data.lineTracks.single.paths, <String>[
      'M 10 20 L 30 40',
      'M 50 60 L 70 80',
    ]);

    final emptyData = NetworkMapData.fromJson(const <String, Object?>{});
    expect(emptyData.selectedRegion, '');
    expect(emptyData.regions, isEmpty);
    expect(emptyData.lines, isEmpty);
    expect(emptyData.stations, isEmpty);
    expect(emptyData.edges, isEmpty);
    expect(emptyData.positionSources, isEmpty);
    expect(emptyData.stationLineMemberships, isEmpty);
    expect(emptyData.lineTracks, isEmpty);

    final emptyRegion = NetworkMapRegion.fromJson(const <String, Object?>{});
    final emptyLine = NetworkMapLine.fromJson(const <String, Object?>{});
    final emptyStation = NetworkMapStation.fromJson(const <String, Object?>{});
    final emptyPosition = NetworkMapPosition.fromJson(
      const <String, Object?>{},
    );
    final emptyEdge = NetworkMapEdge.fromJson(const <String, Object?>{});
    final emptySource = NetworkMapPositionSource.fromJson(
      const <String, Object?>{},
    );
    final emptyMembership = NetworkMapStationLineMembership.fromJson(
      const <String, Object?>{},
    );
    final emptyTrack = NetworkMapLineTrack.fromJson(const <String, Object?>{});

    expect(emptyRegion.name, '');
    expect(emptyLine.id, '');
    expect(emptyLine.name, '');
    expect(emptyLine.color, '#006D77');
    expect(emptyLine.region, '');
    expect(emptyStation.id, '');
    expect(emptyStation.nameKo, '');
    expect(emptyStation.position.x, 0);
    expect(emptyPosition.x, 0);
    expect(emptyPosition.y, 0);
    expect(emptyPosition.labelDx, 0);
    expect(emptyPosition.labelDy, 0);
    expect(emptyPosition.labelPolygon, '');
    expect(emptyPosition.upPath, '');
    expect(emptyPosition.downPath, '');
    expect(emptyPosition.sourceId, '');
    expect(emptyEdge.accessibilityStatus, 'UNKNOWN');
    expect(emptyEdge.reliabilityScore, 0);
    expect(emptySource.id, '');
    expect(emptySource.name, '');
    expect(emptySource.licenseStatus, '');
    expect(emptyMembership.stationId, '');
    expect(emptyMembership.lineId, '');
    expect(emptyTrack.lineId, '');
    expect(emptyTrack.paths, isEmpty);
    expect(
      NetworkMapLine.fromJson(const <String, Object?>{
        'name': '부산김해경전철',
      }).badgeText,
      '김해',
    );
    expect(
      NetworkMapRegion(name: '수도권') == NetworkMapRegion(name: '수도권'),
      isFalse,
    );
  });

  test('label polygon parsing and structured-map derivation stay shared', () {
    expect(
      parseRouteMapLabelPolygon(
        '[{"x":1,"y":2},{"x":3.5,"y":4},{"x":5,"y":6}]',
      ),
      const <Offset>[Offset(1, 2), Offset(3.5, 4), Offset(5, 6)],
    );
    expect(parseRouteMapLabelPolygon(''), isNull);
    expect(parseRouteMapLabelPolygon('not-json'), isNull);
    expect(parseRouteMapLabelPolygon('[{"x":1,"y":2}]'), isNull);
    expect(
      parseRouteMapLabelPolygon('[{"x":-1,"y":2},{"x":3,"y":4},{"x":5,"y":6}]'),
      isNull,
    );

    final data = NetworkMapData(
      regions: const <NetworkMapRegion>[NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: const <NetworkMapLine>[],
      stations: const <NetworkMapStation>[
        NetworkMapStation(
          id: 'station-a',
          nameKo: '시청',
          nameEn: 'City Hall',
          region: '수도권',
          lineId: 'line-2',
          stationCode: '201',
          sequence: 1,
          position: NetworkMapPosition(
            x: 10,
            y: 20,
            labelDx: 0,
            labelDy: 0,
            labelPolygon: '[{"x":1,"y":2},{"x":3,"y":4},{"x":5,"y":6}]',
            upPath: '',
            downPath: '',
            sourceId: 'source-a',
          ),
        ),
      ],
      edges: const <NetworkMapEdge>[],
      positionSources: const <NetworkMapPositionSource>[],
      lineTracks: const <NetworkMapLineTrack>[
        NetworkMapLineTrack(
          lineId: 'line-2',
          paths: <String>['M 10 20 L 30 40'],
        ),
      ],
    );

    final structured = data.toStructuredRouteMap();
    expect(structured.stations.single.position, const Offset(10, 20));
    expect(structured.stations.single.labelPolygon, const <Offset>[
      Offset(1, 2),
      Offset(3, 4),
      Offset(5, 6),
    ]);
    expect(structured.lines.single.polylines.single, const <Offset>[
      Offset(10, 20),
      Offset(30, 40),
    ]);
  });

  test(
    'repository ports preserve their exact asynchronous signatures',
    () async {
      const data = NetworkMapData(
        regions: <NetworkMapRegion>[],
        selectedRegion: '',
        lines: <NetworkMapLine>[],
        stations: <NetworkMapStation>[],
        edges: <NetworkMapEdge>[],
        positionSources: <NetworkMapPositionSource>[],
      );
      final repository = _NetworkMapRepository(data);
      final viewportRepository = _NetworkMapViewportRepository();

      expect(
        await repository.getNetworkMap(region: '수도권', lineId: 'line-2'),
        same(data),
      );
      await viewportRepository.saveSelectedRegion('부산');
      expect(await viewportRepository.loadSelectedRegion(), '부산');
      await viewportRepository.saveViewport(
        region: '부산',
        viewport: const Rect.fromLTWH(1, 2, 3, 4),
      );
      expect(
        await viewportRepository.loadViewport('부산'),
        const Rect.fromLTWH(1, 2, 3, 4),
      );
    },
  );
}

final class _NetworkMapRepository implements NetworkMapRepository {
  const _NetworkMapRepository(this.data);

  final NetworkMapData data;

  @override
  Future<NetworkMapData> getNetworkMap({
    String? region,
    String? lineId,
  }) async => data;
}

final class _NetworkMapViewportRepository
    implements NetworkMapViewportRepository {
  String? _selectedRegion;
  final Map<String, Rect> _viewports = <String, Rect>{};

  @override
  Future<String?> loadSelectedRegion() async => _selectedRegion;

  @override
  Future<Rect?> loadViewport(String region) async => _viewports[region];

  @override
  Future<void> saveSelectedRegion(String region) async {
    _selectedRegion = region;
  }

  @override
  Future<void> saveViewport({
    required String region,
    required Rect viewport,
  }) async {
    _viewports[region] = viewport;
  }
}
