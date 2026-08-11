import 'package:easysubway_mobile/features/network_map/domain/network_map_edge_topology.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 노선도 edge resolver는 station-line endpoint를 해석한다', () {
    const stations = [
      NetworkMapStation(
        id: 'station-a',
        nameKo: '출발역',
        nameEn: 'A',
        region: '수도권',
        lineId: 'seoul-4',
        stationCode: '401',
        sequence: 1,
        position: NetworkMapPosition(
          x: 2800,
          y: 3200,
          labelDx: 0,
          labelDy: 40,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
      NetworkMapStation(
        id: 'station-a',
        nameKo: '다른노선역',
        nameEn: 'A transfer',
        region: '수도권',
        lineId: 'seoul-2',
        stationCode: '201',
        sequence: 1,
        position: NetworkMapPosition(
          x: 2800,
          y: 3200,
          labelDx: 0,
          labelDy: 40,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
    ];

    expect(
      networkMapStationForMapEdgeEndpoint(
        endpoint: 'station-a:seoul-4',
        lineId: 'seoul-4',
        stations: stations,
      )?.stationCode,
      '401',
    );
    expect(
      networkMapStationForMapEdgeEndpoint(
        endpoint: 'station-a',
        lineId: 'seoul-4',
        stations: stations,
      )?.stationCode,
      '401',
    );
  });

  test('패널 인접은 network_edges RIDE만 따르고 sequence 충돌 역은 무시한다', () {
    NetworkMapStation station({
      required String id,
      required String name,
      required int sequence,
      required int x,
      required int y,
    }) {
      return NetworkMapStation(
        id: id,
        nameKo: name,
        nameEn: name,
        region: '수도권',
        lineId: 'line-472a81add377',
        stationCode: id,
        sequence: sequence,
        position: NetworkMapPosition(
          x: x,
          y: y,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-line1-branch',
        ),
      );
    }

    NetworkMapEdge ride(String fromId, String toId) {
      return NetworkMapEdge(
        id: 'edge-$fromId-$toId',
        lineId: 'line-472a81add377',
        fromStationId: '$fromId:line-472a81add377',
        toStationId: '$toId:line-472a81add377',
        accessibilityStatus: 'UNKNOWN',
        reliabilityScore: 100,
      );
    }

    final stations = [
      station(id: 'gwanak', name: '관악', sequence: 50, x: 1240, y: 2075),
      station(id: 'yeokgok', name: '역곡', sequence: 50, x: 869, y: 1758),
      station(id: 'sosa', name: '소사', sequence: 51, x: 820, y: 1757),
      station(id: 'anyang', name: '안양', sequence: 51, x: 1282, y: 2122),
      station(id: 'bucheon', name: '부천', sequence: 52, x: 755, y: 1758),
      station(id: 'myeonghak', name: '명학', sequence: 52, x: 1328, y: 2173),
    ];
    final edges = [
      ride('gwanak', 'anyang'),
      ride('anyang', 'gwanak'),
      ride('anyang', 'myeonghak'),
      ride('myeonghak', 'anyang'),
    ];

    final pair = networkMapAdjacentStationPair(
      stations: stations,
      edges: edges,
      stationId: 'anyang',
      lineId: 'line-472a81add377',
    );

    expect(pair.leftName, '관악');
    expect(pair.rightName, '명학');
    expect(pair.leftStationId, 'gwanak');
    expect(pair.rightStationId, 'myeonghak');
  });
}
