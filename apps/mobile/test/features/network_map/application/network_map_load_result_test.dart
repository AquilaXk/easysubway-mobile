import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/application/network_map_load_result.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network map load result는 data와 viewport를 verbatim 보존한다', () {
    final data = NetworkMapData(
      regions: const [],
      selectedRegion: '수도권',
      lines: const [],
      stations: const [],
      edges: const [],
      positionSources: const [],
    );
    const viewport = Rect.fromLTWH(10, 20, 300, 400);

    final result = NetworkMapLoadResult(data: data, initialViewport: viewport);

    expect(result.data, same(data));
    expect(result.initialViewport, viewport);
  });

  test('network map load result는 null viewport를 대체하지 않는다', () {
    final data = NetworkMapData(
      regions: const [],
      selectedRegion: '',
      lines: const [],
      stations: const [],
      edges: const [],
      positionSources: const [],
    );

    final result = NetworkMapLoadResult(data: data, initialViewport: null);

    expect(result.data, same(data));
    expect(result.initialViewport, isNull);
  });
}
