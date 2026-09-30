import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_profile_models.dart';
import 'package:easysubway_mobile/features/journey/journey_session_provider.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';

void main() {
  testWidgets('(1) 무단차 요청 + NARROW/LOW 위치 4개 → 칸·문 오름차순 앞 3개만 표시 (형식 정확히)', (
    tester,
  ) async {
    final gaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 7-4',
        carNumber: 7,
        doorNumber: 4,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 8-1',
        carNumber: 8,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 5-1',
        carNumber: 5,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      // 틈은 좁지만 높이차가 LOW가 아닌 위치는 칸 번호가 앞서도 제외돼야 한다(#424 리뷰 F2).
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 1-1',
        carNumber: 1,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 2-3',
        carNumber: 2,
        doorNumber: 3,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.high,
        curved: false,
      ),
    ];

    final journey = _makeTestJourney(id: 'journey-gap-1', boardingGaps: gaps);
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    // 경로 후보 선택
    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-1')));
    await tester.pumpAndSettle();

    // (1) 칸·문 오름차순 앞 3개 (3-2, 5-1, 7-4) 형식 정확히 표시
    expect(find.text('틈이 좁은 문 3-2 · 5-1 · 7-4'), findsOneWidget);
    // 4번째인 8-1은 표시되지 않아야 함
    expect(find.textContaining('8-1'), findsNothing);
    // NARROW라도 높이차가 NORMAL·HIGH인 1-1, 2-3은 표시되지 않아야 함
    expect(find.textContaining('1-1'), findsNothing);
    expect(find.textContaining('2-3'), findsNothing);
    // WIDE 위치가 없으므로 "틈 넓은 곳" 줄은 없어야 함
    expect(find.textContaining('틈 넓은 곳'), findsNothing);
  });

  testWidgets('(2) NARROW/LOW 위치가 없고 WIDE 2곳 → "틈이 좁은 문" 줄 없음, 틈 넓은 곳 2곳만 표시', (
    tester,
  ) async {
    final gaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: true,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 5-1',
        carNumber: 5,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.high,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 7-4',
        carNumber: 7,
        doorNumber: 4,
        gapGrade: PlatformGapGrade.normal,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: false,
      ),
    ];

    final journey = _makeTestJourney(id: 'journey-gap-2', boardingGaps: gaps);
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-2')));
    await tester.pumpAndSettle();

    // NARROW/LOW 위치가 없으므로 "틈이 좁은 문" 줄 없음
    expect(find.textContaining('틈이 좁은 문'), findsNothing);
    // WIDE 2곳 표시
    expect(find.text('틈 넓은 곳 2곳'), findsOneWidget);
  });

  testWidgets('(3) 빈 배열 → 영역 미표시', (tester) async {
    final journey = _makeTestJourney(
      id: 'journey-gap-3',
      boardingGaps: const [],
      alightingGaps: const [],
    );
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-3')));
    await tester.pumpAndSettle();

    expect(find.textContaining('틈이 좁은 문'), findsNothing);
    expect(find.textContaining('틈 넓은 곳'), findsNothing);
    expect(find.textContaining('정보 없음'), findsNothing);
  });

  testWidgets('(4) 일반 요청 → 미표시', (tester) async {
    final gaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 5-1',
        carNumber: 5,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.high,
        curved: false,
      ),
    ];

    final journey = _makeTestJourney(id: 'journey-gap-4', boardingGaps: gaps);
    final repo = _GapTestRepository(journey);

    // 일반(STANDARD) 요청
    await _pumpScreen(tester, repository: repo, mobilityType: 'STANDARD');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-4')));
    await tester.pumpAndSettle();

    // 일반 요청에서는 아무것도 표시하지 않음
    expect(find.textContaining('틈이 좁은 문'), findsNothing);
    expect(find.textContaining('틈 넓은 곳'), findsNothing);
  });

  testWidgets('(5) 바텀시트 순서가 서버 순서와 같고, 등급명·곡선 표기가 정확하며, 칸·문 없는 위치는 원문 표시', (
    tester,
  ) async {
    final gaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: true,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 1-1',
        carNumber: 1,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '동대문 방면 끝',
        carNumber: null,
        doorNumber: null,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.high,
        curved: false,
      ),
    ];

    final journey = _makeTestJourney(id: 'journey-gap-5', boardingGaps: gaps);
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-5')));
    await tester.pumpAndSettle();

    // 안내 줄 탭하여 바텀시트 열기
    final lineFinder = find.text('틈 넓은 곳 2곳');
    expect(lineFinder, findsOneWidget);
    await tester.ensureVisible(lineFinder);
    await tester.tap(lineFinder);
    await tester.pumpAndSettle();

    // 바텀시트 행 형식 검증:
    // 1. 서버 첫 번째 항목 (3-2, 넓음, 보통, 곡선)
    final row1 = find.text('3-2 · 틈 넓음 · 높이차 보통 · 곡선 승강장');
    // 2. 서버 두 번째 항목 (1-1, 좁음, 낮음, 곡선 없음)
    final row2 = find.text('1-1 · 틈 좁음 · 높이차 낮음');
    // 3. 서버 세 번째 항목 (칸·문 없음, 원문 그대로, 넓음, 높음)
    final row3 = find.text('동대문 방면 끝 · 틈 넓음 · 높이차 높음');

    expect(row1, findsOneWidget);
    expect(row2, findsOneWidget);
    expect(row3, findsOneWidget);

    // 서버 순서 그대로 나열되었는지 확인 (y좌표 오름차순)
    final y1 = tester.getTopLeft(row1).dy;
    final y2 = tester.getTopLeft(row2).dy;
    final y3 = tester.getTopLeft(row3).dy;
    expect(y1, lessThan(y2));
    expect(y2, lessThan(y3));
  });

  testWidgets('(5b) 같은 칸은 문 번호 오름차순이고, 틈이 좁은 문 줄도 바텀시트를 열며 닫기로 닫힌다', (
    tester,
  ) async {
    final gaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 당고개 방면 3-4',
        carNumber: 3,
        doorNumber: 4,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 당고개 방면 3-1',
        carNumber: 3,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
    ];

    final journey = _makeTestJourney(id: 'journey-gap-5b', boardingGaps: gaps);
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-5b')));
    await tester.pumpAndSettle();

    // 서버 순서(3-4, 3-1)와 달리 같은 칸 안에서는 문 번호 오름차순이다.
    final lineFinder = find.text('틈이 좁은 문 3-1 · 3-4');
    expect(lineFinder, findsOneWidget);

    await tester.ensureVisible(lineFinder);
    await tester.tap(lineFinder);
    await tester.pumpAndSettle();

    // 바텀시트는 서버 순서 그대로다.
    final row1 = find.text('3-4 · 틈 좁음 · 높이차 낮음');
    final row2 = find.text('3-1 · 틈 좁음 · 높이차 낮음');
    expect(row1, findsOneWidget);
    expect(row2, findsOneWidget);
    expect(tester.getTopLeft(row1).dy, lessThan(tester.getTopLeft(row2).dy));

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(row1, findsNothing);
    expect(row2, findsNothing);
  });

  testWidgets('(6) Semantics 라벨 문자열 정확히', (tester) async {
    final handle = tester.ensureSemantics();
    final boardingGaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 5-1',
        carNumber: 5,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 7-4',
        carNumber: 7,
        doorNumber: 4,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 1-1',
        carNumber: 1,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 2-1',
        carNumber: 2,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 4-1',
        carNumber: 4,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 6-1',
        carNumber: 6,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: false,
      ),
    ];

    final alightingGaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.normal,
        curved: true,
      ),
    ];

    final journey = _makeTestJourney(
      id: 'journey-gap-6',
      boardingGaps: boardingGaps,
      alightingGaps: alightingGaps,
    );
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-6')));
    await tester.pumpAndSettle();

    // 안내 줄 Semantics 검증
    expect(
      find.bySemanticsLabel('탑승 승강장, 틈이 좁은 문 3호차 2번, 5호차 1번, 7호차 4번'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('탑승 승강장, 틈 넓은 곳 4곳, 목록 보기'), findsOneWidget);
    expect(find.bySemanticsLabel('하차 승강장, 틈 넓은 곳 1곳, 목록 보기'), findsOneWidget);

    // 하차 승강장 바텀시트 열기
    final alightingTarget = find.bySemanticsLabel('하차 승강장, 틈 넓은 곳 1곳, 목록 보기');
    await tester.ensureVisible(alightingTarget);
    await tester.tap(alightingTarget);
    await tester.pumpAndSettle();

    // 바텀시트 행 Semantics 검증
    expect(
      find.bySemanticsLabel('3호차 2번 문, 틈 넓음, 높이차 보통, 곡선 승강장'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('(7) 터치 영역 48dp 이상 및 textScale 2.0 잘림 없음', (tester) async {
    final gaps = [
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 3-2',
        carNumber: 3,
        doorNumber: 2,
        gapGrade: PlatformGapGrade.narrow,
        heightDiffGrade: PlatformHeightDiffGrade.low,
        curved: false,
      ),
      const JourneyPlatformGap(
        platformPosition: '본선 오이도 방면 5-1',
        carNumber: 5,
        doorNumber: 1,
        gapGrade: PlatformGapGrade.wide,
        heightDiffGrade: PlatformHeightDiffGrade.high,
        curved: false,
      ),
    ];

    final journey = _makeTestJourney(id: 'journey-gap-7', boardingGaps: gaps);
    final repo = _GapTestRepository(journey);

    await _pumpScreen(tester, repository: repo, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('journey-candidate-journey-gap-7')));
    await tester.pumpAndSettle();

    // 터치 영역 >= 48dp 검증
    final narrowLine = find.ancestor(
      of: find.text('틈이 좁은 문 3-2'),
      matching: find.byType(InkWell),
    );
    final wideLine = find.ancestor(
      of: find.text('틈 넓은 곳 1곳'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(narrowLine).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(wideLine).height, greaterThanOrEqualTo(48));

    // 2.0배 큰 글씨 테스트
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required JourneyRepository repository,
  String mobilityType = 'WHEELCHAIR',
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: JourneySearchScreen(
        repository: repository,
        attestor: const _FakeAttestor(),
        draft: RouteDraft(
          origin: const RouteDraftStation(id: 'station-origin', nameKo: '용산'),
          destination: const RouteDraftStation(
            id: 'station-destination',
            nameKo: '춘천',
          ),
          lastModifiedAt: DateTime.utc(2026, 8, 12),
        ),
        mobilityType: mobilityType,
        onShellBackToHome: () {},
        stationNameResolver: (stationId) async => switch (stationId) {
          'station-origin' => '용산역',
          'station-destination' => '춘천역',
          _ => stationId,
        },
        journeyNow: () => DateTime.utc(2026, 8, 12),
      ),
    ),
  );
}

Journey _makeTestJourney({
  required String id,
  List<JourneyPlatformGap> boardingGaps = const [],
  List<JourneyPlatformGap> alightingGaps = const [],
}) {
  final now = DateTime.utc(2026, 8, 12, 0, 0);
  return Journey(
    journeyId: id,
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now,
    plannedArrivalTime: now.add(const Duration(minutes: 10)),
    realtimeDepartureTime: null,
    realtimeArrivalTime: null,
    durationSeconds: 600,
    transferCount: 0,
    walkingDistanceMeters: 50,
    timeSource: JourneyTimeSource.timetable,
    accessibility: const JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: true,
      reasonCodes: <String>[],
    ),
    legs: <JourneyLeg>[
      const JourneyEntryLeg(
        fromStationId: 'station-origin',
        durationSeconds: 60,
      ),
      JourneyRideLeg(
        lineId: 'line-2',
        tripId: 'trip-1',
        directionStationId: 'station-direction',
        fromStationId: 'station-origin',
        toStationId: 'station-destination',
        plannedDepartureTime: now,
        plannedArrivalTime: now.add(const Duration(minutes: 8)),
        realtimeDepartureTime: null,
        realtimeArrivalTime: null,
        boardingPlatformGaps: boardingGaps,
        alightingPlatformGaps: alightingGaps,
      ),
      const JourneyExitLeg(
        fromStationId: 'station-destination',
        durationSeconds: 60,
      ),
    ],
  );
}

class _FakeAttestor implements JourneyV3IntegrityAttestor {
  const _FakeAttestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class _GapTestRepository implements JourneyRepository {
  _GapTestRepository(this.journey);

  final Journey journey;

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    final now = DateTime.utc(2026, 8, 12);
    return JourneySessionResponse(
      token: 'session-token',
      scope: JourneySessionScope.journeyV3,
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    final now = DateTime.utc(2026, 8, 12);
    return JourneySearchSuccess(
      contractVersion: JourneyContractVersion.journeySearchV3,
      requestId: request.requestId,
      queryId: 'query-1',
      calculatedAt: now,
      validUntil: now.add(const Duration(minutes: 5)),
      effectiveDepartureTime: now,
      serviceDate: JourneyDate.parse('2026-08-12'),
      serviceTimezone: 'Asia/Seoul',
      sourceIdentity: JourneySourceIdentity(
        routeBundleId: 'bundle-1',
        routeBundleSha256: 'a' * 64,
        timetableSnapshotId: 'timetable-1',
        accessibilitySnapshotId: 'accessibility-1',
        realtimeSnapshotId: null,
      ),
      requestPolicy: JourneyRequestPolicy(
        timePolicy: request.timePolicy,
        walkingPace: request.walkingPace,
        mobilityProfile: request.mobilityProfile,
        constraintMode: request.constraintMode,
        maxTransfers: request.maxTransfers,
        alternativeCount: request.alternativeCount,
      ),
      journeys: [journey],
    );
  }

  @override
  Future<JourneyProfileSuccess> profileJourneys(
    JourneyProfileRequest request, {
    required String sessionToken,
  }) async => throw UnimplementedError();

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) async => throw UnimplementedError();
}
