import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/presentation/network_map_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

// tools/mobile/analyze-route-map-android-evidence.mjs의 FRAME_LINE과 같은 형식이다.
final _analyzerFrameLine = RegExp(
  r'routeMapFrame buildMs=([\d.]+) rasterMs=([\d.]+) totalMs=([\d.]+) '
  r'frame=(\d+) vsyncStartUs=(\d+)',
);

void main() {
  test('노선도 프레임 줄은 분석기가 읽는 build·raster·total·frame·vsync 값을 담는다', () {
    final line = routeMapFrameTimingLine(
      FrameTiming(
        vsyncStart: 1000000,
        buildStart: 1000500,
        buildFinish: 1003500,
        rasterStart: 1004000,
        rasterFinish: 1017250,
        rasterFinishWallTime: 1017250,
        frameNumber: 42,
      ),
    );

    final match = _analyzerFrameLine.firstMatch(line);
    expect(match, isNotNull, reason: line);
    expect(match!.group(1), '3.00');
    expect(match.group(2), '13.25');
    expect(match.group(3), '17.25');
    expect(match.group(4), '42');
    expect(match.group(5), '1000000');
  });
}
