import 'package:easysubway_mobile/features/network_map/application/network_map_region_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('region bridge는 exact synchronous attach/select/detach 계약을 보존한다', () {
    final bridge = NetworkMapRegionBridge();
    final firstSelections = <String>[];
    final secondSelections = <String>[];

    bridge.selectRegion('attach 전');

    bridge.attach(firstSelections.add);
    bridge.selectRegion('부산');

    bridge.attach(secondSelections.add);
    bridge.selectRegion('대구');

    bridge.detach();
    bridge.selectRegion('광주');

    bridge.attach(firstSelections.add);
    bridge.selectRegion('대전');

    expect(firstSelections, ['부산', '대전']);
    expect(secondSelections, ['대구']);
  });
}
