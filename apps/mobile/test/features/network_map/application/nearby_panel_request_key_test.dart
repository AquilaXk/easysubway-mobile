import 'package:easysubway_mobile/features/network_map/application/nearby_panel_request_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nearby request key는 station·line·generation exact identity만 허용한다', () {
    const request = NearbyPanelRequestKey(
      stationId: 'station-1',
      lineId: 'line-4',
      generation: 7,
    );

    expect(request.stationId, 'station-1');
    expect(request.lineId, 'line-4');
    expect(request.generation, 7);
    expect(
      request.matches(stationId: 'station-1', lineId: 'line-4', generation: 7),
      isTrue,
    );
    expect(
      request.matches(stationId: 'station-2', lineId: 'line-4', generation: 7),
      isFalse,
    );
    expect(
      request.matches(stationId: 'station-1', lineId: 'line-7', generation: 7),
      isFalse,
    );
    expect(
      request.matches(stationId: 'station-1', lineId: 'line-4', generation: 8),
      isFalse,
    );
    expect(
      request.matches(stationId: null, lineId: 'line-4', generation: 7),
      isFalse,
    );
    expect(
      request.matches(stationId: 'station-1', lineId: null, generation: 7),
      isFalse,
    );
  });

  test('nearby request key는 empty identity도 정규화하지 않고 literal 비교한다', () {
    const request = NearbyPanelRequestKey(
      stationId: '',
      lineId: '',
      generation: 0,
    );

    expect(request.matches(stationId: '', lineId: '', generation: 0), isTrue);
    expect(request.matches(stationId: ' ', lineId: '', generation: 0), isFalse);
    expect(request.matches(stationId: '', lineId: ' ', generation: 0), isFalse);
  });
}
