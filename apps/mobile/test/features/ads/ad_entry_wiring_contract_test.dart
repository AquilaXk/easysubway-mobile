import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: start);
  expect(endIndex, greaterThan(startIndex), reason: end);
  return source.substring(startIndex, endIndex);
}

void main() {
  test('세 station detail 앱 조합 진입점이 같은 광고 repository를 전달한다', () {
    final main = File('lib/main.dart').readAsStringSync();
    final home = File('lib/app/home_screen.dart').readAsStringSync();
    final networkMap = File(
      'lib/app/network_map_screen.dart',
    ).readAsStringSync();

    expect(
      _between(main, 'stationDetailBuilder:', 'child: EasySubwayApp'),
      contains('adRepository: bootstrap.dependencies.adRepository'),
    );
    expect(
      _between(
        home,
        'onOpenStationDetail: (favorite)',
        'onOpenFacilityReport: openFacilityReport',
      ),
      contains('adRepository: adRepository'),
    );
    expect(
      _between(
        networkMap,
        'expandedDetail = StationDetailExpandHost(',
        '} else {',
      ),
      contains('adRepository: widget.adRepository'),
    );
  });
}
