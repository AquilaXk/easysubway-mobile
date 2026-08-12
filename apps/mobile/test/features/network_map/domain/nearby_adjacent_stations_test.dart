import 'package:easysubway_mobile/features/network_map/domain/nearby_adjacent_stations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('유효한 previous·next identity 값을 변경 없이 반환한다', () {
    const adjacent = NearbyAdjacentStations(
      leftName: '  건대입구  ',
      rightName: '한양대',
      leftStationId: '',
      rightStationId: 'station-right',
    );

    expect(adjacent.previousNeighbor, (stationId: '', nameKo: '  건대입구  '));
    expect(adjacent.nextNeighbor, (stationId: 'station-right', nameKo: '한양대'));
  });

  test('station id·name 누락 또는 empty name은 neighbor를 만들지 않는다', () {
    const missingLeftId = NearbyAdjacentStations(leftName: '건대입구');
    const missingLeftName = NearbyAdjacentStations(leftStationId: 'left-id');
    const emptyRightName = NearbyAdjacentStations(
      rightStationId: 'right-id',
      rightName: '',
    );

    expect(missingLeftId.previousNeighbor, isNull);
    expect(missingLeftName.previousNeighbor, isNull);
    expect(emptyRightName.nextNeighbor, isNull);
  });
}
