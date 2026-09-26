import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_labels_cache.dart';
import 'package:easysubway_mobile/features/network_map/data/network_map_owner_nodes_cache.dart';
import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapitalOnlyNetworkMapRepository implements NetworkMapRepository {
  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    final isCapital = region == null || region == '수도권' || region == '수도권권';
    if (!isCapital) {
      // 수도권 외 지역은 번들에 없어 데이터가 비어있음
      return const NetworkMapData(
        regions: [NetworkMapRegion(name: '수도권')],
        selectedRegion: '부산',
        lines: [],
        stations: [],
        edges: [],
        positionSources: [],
      );
    }
    return const NetworkMapData(
      regions: [NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: [
        NetworkMapLine(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A4E3',
          region: '수도권',
        ),
      ],
      stations: [
        NetworkMapStation(
          id: 'station-sangnoksu',
          nameKo: '상록수',
          nameEn: 'Sangnoksu',
          region: '수도권',
          lineId: 'seoul-4',
          stationCode: '448',
          sequence: 1,
          position: NetworkMapPosition(
            x: 100,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'test-src',
          ),
        ),
      ],
      edges: [],
      positionSources: [],
    );
  }
}

void main() {
  testWidgets('오프라인 미내장 지역 선택 시 침묵 리셋하지 않고 스낵바 피드백을 제공한다', (tester) async {
    final repository = _CapitalOnlyNetworkMapRepository();
    final routeDraftController = RouteDraftController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkMapScreen(
            repository: repository,
            routeDraftController: routeDraftController,
            onOpenStationSearch: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 현재 지역이 '수도권'임을 확인
    expect(find.text('수도권'), findsWidgets);

    // 지역 드롭다운 열기
    await tester.tap(find.byKey(const Key('networkMapRegionDropdown')));
    await tester.pumpAndSettle();

    // 드롭다운에 5대 대도시권(수도권, 광주, 대구, 대전, 부산)이 지원되어야 함
    expect(
      find.byKey(const ValueKey('networkMapRegionMenuRow_부산')),
      findsOneWidget,
    );

    // 미내장 지역 '부산' 탭
    await tester.tap(find.byKey(const ValueKey('networkMapRegionMenuRow_부산')));
    await tester.pumpAndSettle();

    // 안내 스낵바가 표시되어야 함
    expect(
      find.text('부산 지역은 내장된 오프라인 데이터가 없어 수도권 노선도로 유지됩니다.'),
      findsOneWidget,
    );

    // 노선도는 수도권으로 안전하게 유지됨
    expect(find.text('수도권'), findsWidgets);
  });

  testWidgets('오너 노드 sidecar 로드 실패 시에도 NetworkMapScreen은 정상 초기화된다', (
    tester,
  ) async {
    final repository = _CapitalOnlyNetworkMapRepository();
    final routeDraftController = RouteDraftController();
    final reportedErrors = <FlutterErrorDetails>[];
    primeNetworkMapOwnerLabelsCacheForTest(const {});
    primeNetworkMapOwnerNodesCacheErrorForTest(
      Exception('sidecar load failed'),
    );
    addTearDown(() {
      resetNetworkMapOwnerLabelsCacheForTest();
      resetNetworkMapOwnerNodesCacheForTest();
    });

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkMapScreen(
              repository: repository,
              routeDraftController: routeDraftController,
              onOpenStationSearch: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(find.text('수도권'), findsWidgets);
    expect(reportedErrors, isNotEmpty);
  });
}
