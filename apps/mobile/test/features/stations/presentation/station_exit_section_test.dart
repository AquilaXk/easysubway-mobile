import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_exit_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 출구 목록은 섹션 생성 시 거부한다', () {
    expect(
      () => StationExitSection(
        station: _station,
        exits: const [],
        mapLauncher: _RecordingMapLauncher(),
        locationProvider: null,
      ),
      throwsAssertionError,
    );
  });

  testWidgets('첫 출구가 기본 선택되고 가로 알약 탭 터치로 선택된 출구가 갱신된다', (tester) async {
    await _pumpSection(tester);

    expect(find.text('preview-exit-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-1')), findsOneWidget);
    expect(find.byKey(const Key('stationExitPill-exit-1')), findsOneWidget);
    expect(find.byKey(const Key('stationExitPill-exit-2')), findsOneWidget);
    expect(find.byKey(const Key('stationExitPill-exit-3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stationExitPill-exit-2')));
    await tester.pumpAndSettle();

    expect(find.text('preview-exit-2'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stationExitPill-exit-3')));
    await tester.pumpAndSettle();

    expect(find.text('preview-exit-3'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-3')), findsOneWidget);
  });

  testWidgets('지도 확대 버튼(Icons.open_in_full) 터치 시 현재 선택 출구를 launcher로 연다', (
    tester,
  ) async {
    final launcher = _RecordingMapLauncher();
    await _pumpSection(tester, launcher: launcher);

    await tester.tap(find.byKey(const Key('stationExitPill-exit-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationExitMapExpandButton')));
    await tester.pump();

    expect(launcher.lookTargets, hasLength(1));
    expect(launcher.lookTargets.single.label, '상록수역 2번 출구');
    expect(find.text('카카오맵을 열었습니다.'), findsOneWidget);
  });

  testWidgets('미리보기 탭은 현재 선택 출구를 기존 카카오맵 launcher로 연다', (tester) async {
    final launcher = _RecordingMapLauncher();
    await _pumpSection(tester, launcher: launcher);

    await tester.tap(find.byKey(const Key('stationExitPill-exit-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fakeMapPreviewButton')));
    await tester.pump();

    expect(launcher.lookTargets, hasLength(1));
    expect(launcher.lookTargets.single.label, '상록수역 2번 출구');
    expect(find.text('카카오맵을 열었습니다.'), findsOneWidget);
  });

  testWidgets('출구 목록이 바뀌면 새 목록의 첫 출구로 돌아간다', (tester) async {
    await _pumpSection(tester);
    await tester.tap(find.byKey(const Key('stationExitPill-exit-2')));
    await tester.pumpAndSettle();
    expect(find.text('preview-exit-2'), findsOneWidget);

    await _pumpSection(tester, exits: [_exits[2], _exits[0]]);
    await tester.pumpAndSettle();

    expect(find.text('preview-exit-3'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-3')), findsOneWidget);
  });

  testWidgets('출구 알약 탭은 접근성 가이드에 따라 최소 48dp 터치 영역을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSection(
      tester,
      exits: [_exits.first],
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('stationExitPill-exit-1'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('지도 앱 실행 실패 시 실패 안내 스낵바를 표시한다', (tester) async {
    final launcher = _FailingMapLauncher();
    await _pumpSection(tester, launcher: launcher);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fakeMapPreviewButton')));
    await tester.pumpAndSettle();

    expect(find.text('지도 앱을 열지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('unknown 상태의 출구 카드는 "계단 없는 이동 가능" 표시가 없고 Semantics에도 포함하지 않는다', (
    tester,
  ) async {
    const unknownExit = StationExitInfo(
      id: 'exit-unknown-1',
      stationId: 'station-sangnoksu',
      exitNumber: '9',
      name: '9번 출구',
      hasElevatorConnection: true,
      hasStairOnlyPath: StairOnlyPathStatus.unknown,
      dataConfidence: 'HIGH',
    );

    await _pumpSection(tester, exits: [unknownExit]);
    await tester.pumpAndSettle();

    expect(find.text('계단 없는 이동 가능'), findsNothing);
    expect(unknownExit.stairPathLabel, isNull);
    expect(unknownExit.semanticLabel, isNot(contains('계단 없는 이동 가능')));
    expect(unknownExit.semanticLabel, isNot(contains('계단만 있는 길 있음')));
  });

  testWidgets('absent 상태의 출구 카드는 "계단 없는 이동 가능"을 표시하고 Semantics에도 포함한다', (
    tester,
  ) async {
    const absentExit = StationExitInfo(
      id: 'exit-absent-1',
      stationId: 'station-sangnoksu',
      exitNumber: '1',
      name: '1번 출구',
      hasElevatorConnection: true,
      hasStairOnlyPath: StairOnlyPathStatus.absent,
      dataConfidence: 'HIGH',
    );

    await _pumpSection(tester, exits: [absentExit]);
    await tester.pumpAndSettle();

    expect(find.text('계단 없는 이동 가능'), findsOneWidget);
    expect(absentExit.stairPathLabel, '계단 없는 이동 가능');
    expect(absentExit.semanticLabel, contains('계단 없는 이동 가능'));
  });

  testWidgets(
    'present 상태의 출구 카드는 "계단 없는 이동 가능"을 표시하지 않고 Semantics에 "계단만 있는 길 있음"을 포함한다',
    (tester) async {
      const presentExit = StationExitInfo(
        id: 'exit-present-1',
        stationId: 'station-sangnoksu',
        exitNumber: '2',
        name: '2번 출구',
        hasElevatorConnection: false,
        hasStairOnlyPath: StairOnlyPathStatus.present,
        dataConfidence: 'HIGH',
      );

      await _pumpSection(tester, exits: [presentExit]);
      await tester.pumpAndSettle();

      expect(find.text('계단 없는 이동 가능'), findsNothing);
      expect(presentExit.stairPathLabel, '계단만 있는 길 있음');
      expect(presentExit.semanticLabel, contains('계단만 있는 길 있음'));
    },
  );
}

class _FailingMapLauncher implements KakaoMapLauncher {
  @override
  Future<KakaoMapLaunchResult> openLook(KakaoMapTarget target) async {
    return KakaoMapLaunchResult.failed;
  }

  @override
  Future<KakaoMapLaunchResult> openWalkingRoute(
    KakaoWalkingRouteTarget target,
  ) async {
    return KakaoMapLaunchResult.failed;
  }
}

Future<void> _pumpSection(
  WidgetTester tester, {
  KakaoMapLauncher? launcher,
  List<StationExitInfo> exits = _exits,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SingleChildScrollView(
            child: StationExitSection(
              station: _station,
              exits: exits,
              mapLauncher: launcher ?? _RecordingMapLauncher(),
              locationProvider: null,
              mapPreviewBuilder:
                  ({
                    required station,
                    required exits,
                    required selectedExitId,
                    required onOpenSelected,
                  }) {
                    return TextButton(
                      key: const Key('fakeMapPreviewButton'),
                      onPressed: onOpenSelected,
                      child: Text('preview-$selectedExitId'),
                    );
                  },
            ),
          ),
        ),
      ),
    ),
  );
}

const _station = StationDetail(
  id: 'station-sangnoksu',
  nameKo: '상록수',
  nameEn: 'Sangnoksu',
  region: '수도권',
  latitude: 37.302795,
  longitude: 126.866489,
  dataQualityLevel: 'LEVEL_2',
  lastVerifiedAt: '2026-07-28',
  lines: [],
);

const _exits = [
  StationExitInfo(
    id: 'exit-1',
    stationId: 'station-sangnoksu',
    exitNumber: '1',
    name: '1번 출구',
    latitude: 37.301,
    longitude: 126.861,
    hasElevatorConnection: true,
    hasStairOnlyPath: StairOnlyPathStatus.absent,
    dataConfidence: 'HIGH',
  ),
  StationExitInfo(
    id: 'exit-2',
    stationId: 'station-sangnoksu',
    exitNumber: '2',
    name: '2번 출구',
    latitude: 37.302,
    longitude: 126.862,
    hasElevatorConnection: false,
    hasStairOnlyPath: StairOnlyPathStatus.present,
    dataConfidence: 'HIGH',
  ),
  StationExitInfo(
    id: 'exit-3',
    stationId: 'station-sangnoksu',
    exitNumber: '3',
    name: '3번 출구',
    latitude: 37.303,
    longitude: 126.863,
    hasElevatorConnection: true,
    hasStairOnlyPath: StairOnlyPathStatus.unknown,
    dataConfidence: 'HIGH',
  ),
];

class _RecordingMapLauncher implements KakaoMapLauncher {
  final lookTargets = <KakaoMapTarget>[];

  @override
  Future<KakaoMapLaunchResult> openLook(KakaoMapTarget target) async {
    lookTargets.add(target);
    return KakaoMapLaunchResult.app;
  }

  @override
  Future<KakaoMapLaunchResult> openWalkingRoute(
    KakaoWalkingRouteTarget target,
  ) async {
    return KakaoMapLaunchResult.failed;
  }
}
