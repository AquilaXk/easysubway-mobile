// 출처 화면은 "현재 앱 또는 데이터팩(서버 번들 포함)이 실제로 쓰는 원천"만 보여 준다.
// 쓰이지 않는 원천 카드가 inventory 동기화로 조용히 되돌아오지 못하게 막는 회귀 검사다.
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/attribution/presentation/data_source_attribution_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 퇴역했거나 쓰이지 않아 출처 화면에서 뺀 원천과 그 카드 제목.
/// 제목은 inventory가 `userDisplayName`으로 내려 주던 값이다.
const _removedSourceTitles = <String, String>{
  // 거버넌스 원장에서 퇴역한 KRIC 접근성 원천 5건. 정기 수집은 stationCnvFacl만 한다.
  'kric-station-elevator': '국가철도공단 역사별 엘리베이터 현황',
  'kric-station-elevator-movement': '국가철도공단 역사별 엘리베이터 이동동선',
  'kric-station-escalator': '국가철도공단 역사별 에스컬레이터 현황',
  'kric-wheelchair-lift-location': '국가철도공단 역사별 휠체어리프트 위치',
  'kric-wheelchair-lift-movement': '국가철도공단 역사별 휠체어리프트 이동동선',
  // 후보 평가에만 쓰이고 데이터팩·서버 번들에 들어가지 않는 원천
  'kric-station-info': '역사별 정보',
  'kric-station-movement-detailed': '출입구-승강장 이동경로',
  'kric-station-transfer-info': '역사별 환승정보',
  'kric-train-operation-organ': '열차운영기관정보',
  // 현재 노선도는 공개 좌표 자료와 자체 배치로 만들고, 이 원천은 과거 진단 이력으로만 남는다.
  'seoulmetro-cyberstation-route-map': '서울교통공사 노선도',
};

/// 운영 사용 허용 표시가 꺼져 있어도 실제로 쓰여서 출처 카드를 남기는 원천과 그 이유.
const _listedDespiteNoProductionFlag = <String, String>{
  'kric-subway-route-info': '모든 KRIC 수집이 이 노선·역 목록으로 제공처 코드를 맞춘다',
  'kric-station-movement-standard':
      '서버 번들의 역 엘리베이터 경로 표(#834)를 이 원천의 보관 snapshot으로 만든다',
};

// testWidgets의 가짜 시계 안에서는 비동기 파일 읽기가 끝나지 않으므로 동기로 읽는다.
Map<String, Object?> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  test('출처 inventory에는 퇴역했거나 쓰이지 않는 원천이 없다', () {
    final inventory = _readJson('assets/datapacks/source-inventory.json');
    final ids = [
      for (final source
          in (inventory['sources']! as List).cast<Map<String, Object?>>())
        source['id']! as String,
    ];
    expect(ids.where(_removedSourceTitles.containsKey), isEmpty);
  });

  test('출처 목록에 올라오는 원천 중 운영 사용 허용이 꺼진 것은 실제로 쓰이는 원천뿐이다', () {
    final inventory = _readJson('assets/datapacks/source-inventory.json');
    final flaggedOff = [
      for (final source
          in (inventory['sources']! as List).cast<Map<String, Object?>>().where(
            isListedDataSource,
          ))
        if (source['productionUseAllowed'] == false) source['id']! as String,
    ];
    expect(flaggedOff.toSet(), _listedDespiteNoProductionFlag.keys.toSet());
  });

  testWidgets('출처 화면에는 퇴역했거나 쓰이지 않는 원천 카드가 그려지지 않는다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 200000);
    addTearDown(tester.view.reset);
    final manifest = _readJson('assets/datapacks/metro_map_pack/manifest.json');
    final inventory = _readJson('assets/datapacks/source-inventory.json');

    await tester.pumpWidget(
      MaterialApp(
        home: DataSourceAttributionScreen(
          initialManifest: manifest,
          initialInventory: inventory,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rendered = <String>[
      for (final text in tester.widgetList<Text>(find.byType(Text))) ?text.data,
    ];
    // 카드가 그려진다는 전제를 같이 고정해야 "없다"는 단언이 비어 있는 화면에서 통과하지 않는다.
    expect(rendered, contains('서울교통공사 실시간운임정보'));
    for (final entry in _removedSourceTitles.entries) {
      expect(rendered, isNot(contains(entry.value)), reason: entry.key);
    }
    for (final id in _listedDespiteNoProductionFlag.keys) {
      final source = (inventory['sources']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((candidate) => candidate['id'] == id);
      expect(rendered, contains(source['userDisplayName']), reason: id);
    }
  });
}
