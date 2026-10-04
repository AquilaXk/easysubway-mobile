import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:easysubway_mobile/features/journey/presentation/result/journey_result_view_model.dart';
import 'package:easysubway_mobile/features/journey/presentation/result/journey_result_widgets.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

// #441: 계단 상태 안내, 계단 없는 경로 요청 422 안내, 경로 탭 라벨의 화면 고정.
const _goldenFontFamily = 'NanumGothicGolden';
const _boundaryKey = ValueKey('journey-stair-status-golden-boundary');
const _injectVisualMutation = bool.fromEnvironment(
  'EASYSUBWAY_GOLDEN_MUTATION',
);
const _goldenBackground = Color(0xFFFFFFFF);
const _mutationBackground = Color(0xFF004D40);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: _goldenFontFamily),
      home: Scaffold(
        backgroundColor: _goldenBackground,
        body: Center(
          child: RepaintBoundary(
            key: _boundaryKey,
            child: ColoredBox(
              // CI의 mutation probe만 known pixel delta를 주입한다.
              color: _injectVisualMutation
                  ? _mutationBackground
                  : _goldenBackground,
              child: SizedBox(
                width: 360,
                child: Padding(padding: const EdgeInsets.all(16), child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<JourneyStairStatusNotice> _notices(
  JourneyStairFreeAlternativeStatus status,
  JourneyStairFreeFacilityStatus facility, {
  required bool hasStairFreeJourney,
}) => journeyStairStatusNotices(
  JourneyStairFreeAlternative(status: status, facilityStatus: facility),
  hasStairFreeJourney: hasStairFreeJourney,
);

void main() {
  setUpAll(() async {
    final bytes = await File(
      'test/assets/fonts/NanumGothic-Regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      _goldenFontFamily,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  // golden 비교는 macOS 호스트 래스터라이저에서만 (CI 크로스플랫폼 오탐 방지).
  final skipReason = !Platform.isMacOS;

  testWidgets('기본 상태', (tester) async {
    // 계단 정보 미확인 + 엘리베이터 고장 정보 미반영이 함께 오는 표준 검색 결과.
    await _pump(
      tester,
      JourneyStairStatusNotices(
        notices: _notices(
          JourneyStairFreeAlternativeStatus.undetermined,
          JourneyStairFreeFacilityStatus.unobserved,
          hasStairFreeJourney: true,
        ),
      ),
    );
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_stair_status_undetermined.png'),
    );
  }, skip: skipReason);

  testWidgets('계단 없는 경로 없음', (tester) async {
    await _pump(
      tester,
      JourneyStairStatusNotices(
        notices: _notices(
          JourneyStairFreeAlternativeStatus.notFound,
          JourneyStairFreeFacilityStatus.applied,
          hasStairFreeJourney: false,
        ),
      ),
    );
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_stair_status_not_found.png'),
    );
  }, skip: skipReason);

  testWidgets('계단 없는 경로가 필요한 사용자의 경로 탭', (tester) async {
    Journey journey(
      String id,
      int minutes,
      int transfers,
      List<JourneyAlternativeCategory> categories, {
      bool stairFree = false,
    }) => Journey(
      journeyId: id,
      status: JourneyStatus.found,
      planSource: JourneyPlanSource.serverTimetableRaptor,
      plannedDepartureTime: DateTime.utc(2026, 9, 30, 0),
      plannedArrivalTime: DateTime.utc(2026, 9, 30, 0, minutes),
      realtimeDepartureTime: null,
      realtimeArrivalTime: null,
      durationSeconds: minutes * 60,
      transferCount: transfers,
      walkingDistanceMeters: 100,
      timeSource: JourneyTimeSource.timetable,
      accessibility: JourneyAccessibility(
        result: JourneyAccessibilityResult.verified,
        stairFree: stairFree,
        reasonCodes: const <String>[],
      ),
      legs: const <JourneyLeg>[
        JourneyEntryLeg(fromStationId: 'origin', durationSeconds: 60),
      ],
      fare: const JourneyFare(
        status: JourneyFareStatus.unavailable,
        sourceSnapshotIds: <String>[],
      ),
      alternativeCategories: categories,
    );
    final tabs = journeyRouteTabs(showStairStatus: true, [
      journey('a', 30, 2, [JourneyAlternativeCategory.fastest]),
      journey('b', 34, 1, [JourneyAlternativeCategory.fewestTransfers]),
      journey('c', 41, 0, [
        JourneyAlternativeCategory.stairFree,
      ], stairFree: true),
    ]);
    await _pump(
      tester,
      JourneyRouteTabs(tabs: tabs, selectedJourneyId: 'a', onSelect: (_) {}),
    );
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_route_tabs_stair_free.png'),
    );
  }, skip: skipReason);

  testWidgets('계단 없는 경로 요청 422 안내', (tester) async {
    await _pump(
      tester,
      JourneyStepFreeUnavailablePanel(
        copy: journeyFailureCopy(
          JourneyErrorDispositions.lookup(
            JourneyOperation.searchJourneys,
            422,
            JourneyErrorCode.accessibilityConstraintUnsatisfied,
          ),
        ),
        onShowStandardRoutes: () {},
        onReselectStations: () {},
      ),
    );
    await expectLater(
      find.byKey(_boundaryKey),
      matchesGoldenFile('goldens/journey_step_free_unavailable.png'),
    );
  }, skip: skipReason);
}
