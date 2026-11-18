import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_station_selection.dart';
import 'package:flutter_test/flutter_test.dart';

const _position = NetworkMapPosition(
  x: 0,
  y: 0,
  labelDx: 0,
  labelDy: 0,
  upPath: '',
  downPath: '',
  sourceId: 'fixture',
);

NetworkMapStation _station(String id, String lineId, String stationCode) {
  return NetworkMapStation(
    id: id,
    nameKo: id,
    nameEn: id,
    region: '수도권',
    lineId: lineId,
    stationCode: stationCode,
    sequence: 0,
    position: _position,
  );
}

const _lines = [
  NetworkMapLine(id: 'line-1', name: '1호선', color: '#000001', region: '수도권'),
  NetworkMapLine(id: 'line-2', name: '2호선', color: '#000002', region: '수도권'),
];

NetworkMapData _data({
  required List<NetworkMapStation> stations,
  List<NetworkMapStationLineMembership> memberships = const [],
}) {
  return NetworkMapData(
    regions: const [],
    selectedRegion: '수도권',
    lines: _lines,
    stations: stations,
    edges: const [],
    positionSources: const [],
    stationLineMemberships: memberships,
  );
}

void main() {
  test('명시 membership은 embedded line을 대체하고 unknown·중복 line을 무시한다', () {
    final stations = [
      _station('station-a', 'line-1', 'A1'),
      _station('station-a', 'line-2', 'A2'),
      _station('station-b', 'missing-line', 'B1'),
    ];
    final result = networkMapStationLinesById(
      _data(
        stations: stations,
        memberships: const [
          NetworkMapStationLineMembership(
            stationId: 'station-a',
            lineId: 'line-2',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-a',
            lineId: 'line-2',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-a',
            lineId: 'missing-line',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-b',
            lineId: 'line-1',
          ),
        ],
      ),
    );

    expect(result['station-a']?.map((line) => line.id), ['line-2']);
    expect(result['station-b']?.map((line) => line.id), ['line-1']);
  });

  test('membership이 없으면 station 선언 순서의 line을 사용한다', () {
    final result = networkMapStationLinesById(
      _data(
        stations: [
          _station('station-a', 'line-1', 'A1'),
          _station('station-a', 'line-2', 'A2'),
          _station('station-a', 'line-1', 'A3'),
        ],
      ),
    );

    expect(result['station-a']?.map((line) => line.id), ['line-1', 'line-2']);
  });

  test('station lookup은 첫 ID match와 exact ID-line identity를 구분한다', () {
    final first = _station('station-a', 'line-1', 'A1');
    final second = _station('station-a', 'line-2', 'A2');
    final stations = [first, second];

    expect(networkMapStationById(stations, 'station-a'), same(first));
    expect(networkMapStationById(stations, null), isNull);
    expect(networkMapStationById(stations, 'missing'), isNull);
    expect(networkMapStationByIdentity(stations, second), same(second));
    expect(networkMapStationByIdentity(stations, null), isNull);
    expect(
      networkMapStationByIdentity(
        stations,
        _station('station-a', 'missing-line', 'A3'),
      ),
      isNull,
    );
  });
}
