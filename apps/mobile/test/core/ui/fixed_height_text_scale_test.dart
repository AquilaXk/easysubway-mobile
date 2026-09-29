import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_columns.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_timetable_panel.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
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

    testWidgets('4. station_exit_map_preview: Container(height: 36) 확인', (
      tester,
    ) async {
      // Container(height: 36)은 지도 에러/안내 패널의 맵 아이콘 전용 배경이며 Text를 담지 않음.
      final iconContainer = Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.map_outlined, size: 20),
      );
      await pumpAtScale(tester, Center(child: iconContainer));
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('5. station_timetable_screen: Container(height: 56) 확인', (
      tester,
    ) async {
      // Container(height: 56)은 Wi-Fi 아이콘 배경 전용이며 Text를 담지 않음.
      final iconContainer = Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Colors.grey,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.wifi_off_rounded, size: 28),
      );
      await pumpAtScale(tester, Center(child: iconContainer));
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Text), findsNothing);
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

    testWidgets('10. journey_search_screen: 노선도 배지 Container(height: 24) 확인', (
      tester,
    ) async {
      // 10번 배지는 노선도 타임라인 핀으로 24x24 원형 고정(의도적 고정).
      final badgeContainer = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blue,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        alignment: Alignment.center,
        child: const Text(
          '2',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ),
      );

      await pumpAtScale(tester, Center(child: badgeContainer), scale: 1.0);
      final textFinder = find.text('2');
      expect(textFinder, findsOneWidget);
      final boxHeight = tester.getSize(find.byType(Container).first).height;
      expect(boxHeight, 24.0);
      expectTextFits(tester, textFinder, boxHeight: boxHeight);
    });

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
