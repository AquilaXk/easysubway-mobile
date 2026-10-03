import 'dart:io';

import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/features/stations/data/server_station_timetable_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// #437 리뷰 F3: 서버 역 시간표의 nextStationId·terminalStationId가 앱 카탈로그
// ID 공간에 있는지 실데이터로 고정한다.
//
// 표본 ID는 실제 서버 경로 번들 seq126(data run 37109648483,
// nationwide-route-bundle-1)의 값이다. backend
// `StationTimetableRealDerivedFixture`(강남 2호선·신도림 1호선)와
// `StationTimetableRealBundleProbeTest`(인천 1호선 박촌)가 같은 ID를 쓴다.
// 같은 번들의 transit_stop_times 역 ID 942개를 이 앱 카탈로그
// (assets/datapacks/nationwide.sqlite.gz)와 전수 대조했을 때 누락은 0개였다
// (PR #440 본문 참조).
const _seq126Names = <String, String>{
  'station-gangnam': '강남',
  'station-6cb6f7dc212c': '역삼', // 강남 2호선 다음 정차역
  'station-7dfc6ea6a83c': '교대', // 강남 2호선 다음 정차역
  'station-seongsu': '성수', // 2호선 종착
  'station-6a5e08288b46': '신도림',
  'station-28102e7fc597': '구로', // 신도림 1호선 다음 정차역
  'station-be476fd82950': '인천', // 1호선 종착
  'station-f497b2d7043f': '박촌', // 인천 1호선
};

void main() {
  late Directory directory;
  late CatalogDatabase catalog;

  setUpAll(() {
    directory = Directory.systemTemp.createTempSync('timetable-id-space-');
    final file = File('${directory.path}/catalog.sqlite')
      ..writeAsBytesSync(
        gzip.decode(
          File('assets/datapacks/nationwide.sqlite.gz').readAsBytesSync(),
        ),
      );
    catalog = CatalogDatabase.file(file);
  });

  tearDownAll(() async {
    await catalog.close();
    directory.deleteSync(recursive: true);
  });

  test('seq126 서버 번들의 역 ID를 앱 카탈로그 이름으로 붙일 수 있다', () async {
    final resolve = stationDetailNameResolver(
      DriftStationRepository(database: catalog),
    );

    for (final MapEntry(key: stationId, value: name) in _seq126Names.entries) {
      expect(await resolve(stationId), name, reason: stationId);
    }
  });

  test('카탈로그에 없는 ID는 이름을 지어내지 않고 실패한다', () async {
    final resolve = stationDetailNameResolver(
      DriftStationRepository(database: catalog),
    );

    await expectLater(resolve('station-not-in-catalog'), throwsA(anything));
  });
}
