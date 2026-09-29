import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_profile_models.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/journey_session_provider.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_columns.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_timetable_panel.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAtScale(
  WidgetTester tester,
  Widget child, {
  double scale = 2.0,
  Size size = const Size(360, 640),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void expectTextFits(
  WidgetTester tester,
  Finder text, {
  required double boxHeight,
}) {
  final p = tester.renderObject<RenderParagraph>(text);
  final textHeight = p.textSize.height;
  debugPrint(
    'TEXT MEASURE: text="${p.text.toPlainText()}", textHeight=$textHeight, boxHeight=$boxHeight',
  );
  expect(
    textHeight,
    lessThanOrEqualTo(boxHeight + 0.01),
    reason:
        '${p.text.toPlainText()} 잘림 (필요 높이: $textHeight, 박스 높이: $boxHeight)',
  );
}

const _testStation = StationDetail(
  id: 'station-sangnoksu',
  nameKo: '상록수',
  nameEn: 'Sangnoksu',
  region: '수도권',
  dataQualityLevel: 'LEVEL_1',
  lastVerifiedAt: '2026-09-27',
  latitude: 37.302,
  longitude: 126.865,
  lines: [
    StationSearchLine(
      id: 'seoul-4',
      name: '수도권 4호선',
      color: '#00A5DE',
      stationCode: '450',
    ),
  ],
);

Widget _buildDetailBody() {
  return StationDetailBody(
    state: const StationDetailState(
      status: StationDetailStatus.success,
      detail: _testStation,
      exits: [],
      facilities: [],
    ),
    onRetryRealtime: () {},
    onOpenFacilityReport: (_) async {},
    mapLauncher: const UrlLauncherKakaoMapLauncher(),
  );
}

void _ignoreHorizontalOverflow() {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by') &&
        details.exceptionAsString().contains('pixels on the right')) {
      // Excluded: 폭(가로) 잘림
      return;
    }
    originalOnError?.call(details);
  };
}

class _BadgeAttestor implements JourneyV3IntegrityAttestor {
  const _BadgeAttestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class _BadgeRepository implements JourneyRepository {
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
      journeys: [
        Journey(
          journeyId: 'journey-1',
          status: JourneyStatus.found,
          planSource: JourneyPlanSource.serverTimetableRaptor,
          plannedDepartureTime: now,
          plannedArrivalTime: now.add(const Duration(minutes: 20)),
          realtimeDepartureTime: null,
          realtimeArrivalTime: null,
          durationSeconds: 1200,
          transferCount: 1,
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
              lineId: 'gyeongui-jungang',
              tripId: 'trip-1',
              directionStationId: 'station-direction',
              fromStationId: 'station-origin',
              toStationId: 'station-transfer',
              plannedDepartureTime: now,
              plannedArrivalTime: now.add(const Duration(minutes: 10)),
              realtimeDepartureTime: null,
              realtimeArrivalTime: null,
            ),
            const JourneyTransferLeg(
              fromStationId: 'station-transfer',
              toStationId: 'station-destination',
              durationSeconds: 120,
            ),
            JourneyRideLeg(
              lineId: 'line-2',
              tripId: 'trip-2',
              directionStationId: 'station-direction',
              fromStationId: 'station-transfer',
              toStationId: 'station-destination',
              plannedDepartureTime: now.add(const Duration(minutes: 12)),
              plannedArrivalTime: now.add(const Duration(minutes: 18)),
              realtimeDepartureTime: null,
              realtimeArrivalTime: null,
            ),
            const JourneyExitLeg(
              fromStationId: 'station-destination',
              durationSeconds: 60,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<JourneyProfileSuccess> profileJourneys(
    JourneyProfileRequest request, {
    required String sessionToken,
  }) async => throw UnimplementedError('badge test does not profile');

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) async => throw UnimplementedError('badge test does not search timetables');
}

void main() {
  group('후보 10곳 큰 글자(2.0배) 고정 높이 텍스트 잘림 측정', () {
    testWidgets('1. nearby_timetable_panel: 운행 종료', (tester) async {
      await pumpAtScale(
        tester,
        NearbyTimetablePanel(
          data: const NearbyTimetablePanelData(
            directions: [
              NearbyTimetableDirectionData(
                name: '오이도',
                departures: [
                  NearbyTimetableDepartureData(
                    directionName: '오이도',
                    seconds: 20880,
                    timeLabel: '05:48',
                    semanticLabel: '오이도, 05시 48분 출발',
                    isExpress: false,
                  ),
                  NearbyTimetableDepartureData(
                    directionName: '오이도',
                    seconds: 84600,
                    timeLabel: '23:30',
                    semanticLabel: '오이도, 23시 30분 출발',
                    isExpress: false,
                  ),
                ],
              ),
            ],
          ),
          lineColor: Colors.blue,
          leftName: '반월',
          rightName: '한대앞',
          now: DateTime(2026, 9, 27, 23, 50),
          expressBadgeBuilder: () => const SizedBox(),
        ),
      );

      final textFinder = find.text('운행 종료');
      expect(textFinder, findsOneWidget);
      final boxFinder = find.ancestor(
        of: textFinder,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 46,
        ),
      );
      final boxHeight = tester.getSize(boxFinder.first).height;
      expectTextFits(tester, textFinder, boxHeight: boxHeight);
    });

    testWidgets('2. nearby_direction_columns: 데이터 없는 열 대시(-)', (tester) async {
      await pumpAtScale(
        tester,
        const NearbyPanelColumns(
          columns: [NearbyPanelColumn(title: '건대입구 방면')],
          lineColor: Colors.blue,
        ),
      );

      final textFinder = find.text('-');
      expect(textFinder, findsOneWidget);
      final boxFinder = find.ancestor(
        of: textFinder,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 46,
        ),
      );
      final boxHeight = tester.getSize(boxFinder.first).height;
      expectTextFits(tester, textFinder, boxHeight: boxHeight);
    });

    testWidgets('3. nearby_direction_columns: standalone no-data 대시(-)', (
      tester,
    ) async {
      await pumpAtScale(tester, const NearbyDataUnavailable());

      final textFinder = find.byKey(
        const Key('networkMapNearbyDataUnavailable'),
      );
      expect(textFinder, findsOneWidget);
      final boxFinder = find.ancestor(
        of: textFinder,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 46,
        ),
      );
      final boxHeight = tester.getSize(boxFinder.first).height;
      expectTextFits(tester, textFinder, boxHeight: boxHeight);
    });

    testWidgets('6. station_detail_body: [출발] 버튼 Container(height: 48)', (
      tester,
    ) async {
      _ignoreHorizontalOverflow();
      await pumpAtScale(tester, _buildDetailBody());

      final originFinder = find.descendant(
        of: find.byKey(const Key('stationDetailSetOriginButton')),
        matching: find.text('출발'),
      );
      expect(originFinder, findsOneWidget);
      final originBoxFinder = find
          .ancestor(of: originFinder, matching: find.byType(Container))
          .first;
      final originBoxHeight = tester.getSize(originBoxFinder).height;
      expectTextFits(tester, originFinder, boxHeight: originBoxHeight);
    });

    testWidgets('7. station_detail_body: [도착] 버튼 Container(height: 48)', (
      tester,
    ) async {
      _ignoreHorizontalOverflow();
      await pumpAtScale(tester, _buildDetailBody());

      final destFinder = find.descendant(
        of: find.byKey(const Key('stationDetailSetDestinationButton')),
        matching: find.text('도착'),
      );
      expect(destFinder, findsOneWidget);
      final destBoxFinder = find
          .ancestor(of: destFinder, matching: find.byType(Container))
          .first;
      final destBoxHeight = tester.getSize(destBoxFinder).height;
      expectTextFits(tester, destFinder, boxHeight: destBoxHeight);
    });

    testWidgets('8. station_detail_body: [전체 시간표] 버튼 Container(height: 48)', (
      tester,
    ) async {
      _ignoreHorizontalOverflow();
      await pumpAtScale(tester, _buildDetailBody());

      final timetableFinder = find.descendant(
        of: find.byKey(const Key('stationTimetableButton')),
        matching: find.text('전체 시간표'),
      );
      expect(timetableFinder, findsOneWidget);
      final timetableBoxFinder = find
          .ancestor(of: timetableFinder, matching: find.byType(Container))
          .first;
      final timetableBoxHeight = tester.getSize(timetableBoxFinder).height;
      expectTextFits(tester, timetableFinder, boxHeight: timetableBoxHeight);
    });

    testWidgets('9. station_detail_body: [첫차·막차] 버튼 Container(height: 48)', (
      tester,
    ) async {
      _ignoreHorizontalOverflow();
      await pumpAtScale(tester, _buildDetailBody());

      final firstLastFinder = find.descendant(
        of: find.byKey(const Key('stationDetailBottomFirstLastButton')),
        matching: find.text('첫차·막차'),
      );
      expect(firstLastFinder, findsOneWidget);
      final firstLastBoxFinder = find
          .ancestor(of: firstLastFinder, matching: find.byType(Container))
          .first;
      final firstLastBoxHeight = tester.getSize(firstLastBoxFinder).height;
      expectTextFits(tester, firstLastFinder, boxHeight: firstLastBoxHeight);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('10. journey_search_screen: 타임라인 노선 배지가 $scale배에서 잘리지 않는다', (
        tester,
      ) async {
        // 배지와 무관한 화면 내 다른 가로 overflow는 이 측정의 범위 밖이다.
        _ignoreHorizontalOverflow();
        await pumpAtScale(
          tester,
          JourneySearchScreen(
            repository: _BadgeRepository(),
            attestor: const _BadgeAttestor(),
            draft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-origin',
                nameKo: '용산',
              ),
              destination: const RouteDraftStation(
                id: 'station-destination',
                nameKo: '춘천',
              ),
              lastModifiedAt: DateTime.utc(2026, 8, 12),
            ),
            mobilityType: 'STANDARD',
            onShellBackToHome: () {},
            journeyNow: () => DateTime.utc(2026, 8, 12),
          ),
          scale: scale,
          size: const Size(412, 900),
        );
        await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('journey-candidate-journey-1')));
        await tester.pumpAndSettle();

        for (final badge in ['2', '경의']) {
          final textFinder = find.text(badge);
          expect(textFinder, findsOneWidget, reason: '배지 $badge');
          await tester.ensureVisible(textFinder);
          final paragraph = tester.renderObject<RenderParagraph>(textFinder);
          final boxFinder = find
              .ancestor(of: textFinder, matching: find.byType(Container))
              .first;
          final box = tester.getSize(boxFinder);
          debugPrint(
            'BADGE MEASURE: scale=$scale, badge="$badge", '
            'text=${paragraph.textSize}, box=$box',
          );
          expect(
            paragraph.textSize.height,
            lessThanOrEqualTo(box.height + 0.01),
            reason: '$badge 배지 높이 잘림',
          );
          expect(
            paragraph.textSize.width,
            lessThanOrEqualTo(box.width + 0.01),
            reason: '$badge 배지 폭 잘림',
          );
          if (scale == 1.0) {
            expect(box, const Size(24, 24), reason: '$badge 1.0배 24x24 유지');
          }
        }
      });
    }

    testWidgets('station_detail_body 하단 액션 버튼 1.0배 기준 높이가 정확히 48dp이다', (
      tester,
    ) async {
      await pumpAtScale(tester, _buildDetailBody(), scale: 1.0);

      final originFinder = find.descendant(
        of: find.byKey(const Key('stationDetailSetOriginButton')),
        matching: find.text('출발'),
      );
      final originBox = find
          .ancestor(of: originFinder, matching: find.byType(Container))
          .first;
      expect(tester.getSize(originBox).height, 48.0);

      final destFinder = find.descendant(
        of: find.byKey(const Key('stationDetailSetDestinationButton')),
        matching: find.text('도착'),
      );
      final destBox = find
          .ancestor(of: destFinder, matching: find.byType(Container))
          .first;
      expect(tester.getSize(destBox).height, 48.0);

      final timetableFinder = find.descendant(
        of: find.byKey(const Key('stationTimetableButton')),
        matching: find.text('전체 시간표'),
      );
      final timetableBox = find
          .ancestor(of: timetableFinder, matching: find.byType(Container))
          .first;
      expect(tester.getSize(timetableBox).height, 48.0);

      final firstLastFinder = find.descendant(
        of: find.byKey(const Key('stationDetailBottomFirstLastButton')),
        matching: find.text('첫차·막차'),
      );
      final firstLastBox = find
          .ancestor(of: firstLastFinder, matching: find.byType(Container))
          .first;
      expect(tester.getSize(firstLastBox).height, 48.0);
    });
  });
}
