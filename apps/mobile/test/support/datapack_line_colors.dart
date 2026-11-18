import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:flutter/painting.dart';

import 'bundled_datapack.dart';

/// 번들 데이터팩 `lines` 표의 노선색 전부. 앱이 노선색으로 그리는 색의 원천이다.
/// 노선색 글자를 알아보는 검사(`rendered_typography.dart`)가 쓴다.
final Set<Color> datapackLineColors = _readDatapackLineColors();

Set<Color> _readDatapackLineColors() {
  return openBundledDatapack((database) {
    final colors = {
      for (final row in database.select('SELECT color FROM lines'))
        stationLineColor(row['color'] as String),
    };
    if (colors.isEmpty) {
      throw StateError('데이터팩 lines 표에서 노선색을 읽지 못했다: $bundledDatapackAssetPath');
    }
    return colors;
  });
}
