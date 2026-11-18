import 'package:easysubway_mobile/features/network_map/domain/route_map_major_stations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routeMapMajorLandmarkStationNamesByRegion', () {
    test('전국 5개 권역의 비환승 주요역 allowlist를 정확히 정의한다', () {
      expect(
        routeMapMajorLandmarkStationNamesByRegion.keys.toSet(),
        equals({'수도권', '부산권', '대구권', '대전권', '광주권'}),
      );

      expect(routeMapMajorLandmarkStationNamesByRegion['수도권'], equals({'성수'}));
      expect(
        routeMapMajorLandmarkStationNamesByRegion['부산권'],
        equals({'해운대', '부산대'}),
      );
      expect(routeMapMajorLandmarkStationNamesByRegion['대구권'], equals({'중앙로'}));
      expect(
        routeMapMajorLandmarkStationNamesByRegion['대전권'],
        equals({'시청', '정부청사'}),
      );
      expect(
        routeMapMajorLandmarkStationNamesByRegion['광주권'],
        equals({'금남로4가', '상무'}),
      );
    });

    test('모든 권역의 주요역명은 비어있지 않다', () {
      for (final entry in routeMapMajorLandmarkStationNamesByRegion.entries) {
        expect(entry.value.isNotEmpty, isTrue);
        for (final station in entry.value) {
          expect(station.trim().isNotEmpty, isTrue);
        }
      }
    });
  });
}
