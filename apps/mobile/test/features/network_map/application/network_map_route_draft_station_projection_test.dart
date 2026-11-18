import 'package:easysubway_mobile/features/network_map/application/network_map_route_draft_station_projection.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const station = NetworkMapStation(
    id: 'station-201',
    nameKo: '시청',
    nameEn: 'City Hall',
    region: '수도권',
    lineId: ' line-2 ',
    stationCode: '201',
    sequence: 1,
    position: NetworkMapPosition(
      x: 10,
      y: 20,
      labelDx: 0,
      labelDy: 0,
      labelPolygon: '',
      upPath: '',
      downPath: '',
      sourceId: '',
    ),
  );
  const data = NetworkMapData(
    regions: <NetworkMapRegion>[],
    selectedRegion: '수도권',
    lines: <NetworkMapLine>[
      NetworkMapLine(
        id: 'line-2',
        name: '수도권 2호선',
        color: '#00A84D',
        region: '수도권',
      ),
    ],
    stations: <NetworkMapStation>[],
    edges: <NetworkMapEdge>[],
    positionSources: <NetworkMapPositionSource>[],
  );

  test('matching line metadata를 typed Route Draft station에 보존한다', () {
    final projected = networkMapRouteDraftStation(station, data);

    expect(projected.id, 'station-201');
    expect(projected.nameKo, '시청');
    expect(projected.lineId, 'line-2');
    expect(projected.lineName, '수도권 2호선');
    expect(projected.lineColor, '#00A84D');
    expect(projected.stationCode, '201');
  });

  test('data 또는 matching line이 없으면 line metadata만 비운다', () {
    final withoutData = networkMapRouteDraftStation(station, null);
    final withoutMatchingLine = networkMapRouteDraftStation(
      station,
      const NetworkMapData(
        regions: <NetworkMapRegion>[],
        selectedRegion: '수도권',
        lines: <NetworkMapLine>[],
        stations: <NetworkMapStation>[],
        edges: <NetworkMapEdge>[],
        positionSources: <NetworkMapPositionSource>[],
      ),
    );

    for (final stationProjection in <RouteDraftStation>[
      withoutData,
      withoutMatchingLine,
    ]) {
      expect(stationProjection.lineId, 'line-2');
      expect(stationProjection.lineName, '');
      expect(stationProjection.lineColor, '');
      expect(stationProjection.id, 'station-201');
      expect(stationProjection.stationCode, '201');
    }
  });
}
