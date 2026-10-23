import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _station = StationDetail(
  id: 'station-chungmuro',
  nameKo: '충무로',
  nameEn: 'Chungmuro',
  region: '수도권',
  dataQualityLevel: 'LEVEL_1',
  lastVerifiedAt: '2026-10-24',
  lines: [
    StationSearchLine(
      id: 'seoul-3',
      name: '수도권 3호선',
      color: '#EF7C1C',
      stationCode: '331',
    ),
  ],
  confirmedAbsentFacilityTypes: {'WHEELCHAIR_LIFT'},
);

StationExitInfo _exit(
  String number, {
  String description = '',
  bool hasElevatorConnection = false,
  StairOnlyPathStatus stair = StairOnlyPathStatus.unknown,
  String? doorHint,
}) {
  return StationExitInfo(
    id: 'exit-$number',
    stationId: _station.id,
    exitNumber: number,
    name: '$number번 출구',
    description: description,
    hasElevatorConnection: hasElevatorConnection,
    hasStairOnlyPath: stair,
    dataConfidence: 'HIGH',
    nearbyDoorHint: doorHint,
  );
}

final _exits = [
  _exit(
    '1',
    description: '필동주민센터, 남산골한옥마을',
    hasElevatorConnection: true,
    stair: StairOnlyPathStatus.absent,
    doorHint: '오금 방면 4-4, 대화 방면 7-1',
  ),
  _exit('2', description: '대한극장'),
  _exit('3'),
];

const _facilities = [
  StationFacilityInfo(
    id: 'facility-ev-1',
    stationId: 'station-chungmuro',
    exitId: 'exit-1',
    type: 'ELEVATOR',
    name: '1번 출구 엘리베이터',
    floorFrom: 'B1',
    floorTo: '1F',
    description: '1번 출구 지상 연결',
    status: 'NORMAL',
    dataConfidence: 'HIGH',
    lastUpdatedAt: '2026-10-24',
  ),
  StationFacilityInfo(
    id: 'facility-toilet-1',
    stationId: 'station-chungmuro',
    exitId: '',
    type: 'TOILET',
    name: '화장실',
    floorFrom: 'B1',
    floorTo: 'B1',
    description: '개찰구 안 승강장 쪽',
    status: 'NORMAL',
    dataConfidence: 'HIGH',
    lastUpdatedAt: '2026-10-24',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<StationExitInfo>? exits,
  double width = 412,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 4000),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: StationDetailBody(
            state: StationDetailState(
              status: StationDetailStatus.success,
              detail: _station,
              exits: exits ?? _exits,
              facilities: _facilities,
            ),
            onRetryRealtime: () {},
            onOpenFacilityReport: (_) async {},
            mapLauncher: const UrlLauncherKakaoMapLauncher(),
            mapPreviewBuilder:
                ({
                  required station,
                  required exits,
                  required selectedExitId,
                  required onOpenSelected,
                }) => const SizedBox(height: 180),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _currentExit => find.byKey(const Key('stationExitSelectorCurrent'));

String _currentExitNumber(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: _currentExit, matching: find.byType(Text)),
    )
    .first
    .data!;

Finder _tintedBoxAround(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).color ==
            EasySubwayAccessibleColors.surfaceSubtle,
  ),
);

void main() {
  group('역정보', () {
    testWidgets('묶음을 회색 상자로 감싸지 않는다', (tester) async {
      await _pump(tester);

      for (final title in ['시설정보', '교통약자 시설']) {
        expect(find.text(title), findsOneWidget);
        expect(_tintedBoxAround(title), findsNothing);
      }
    });

    testWidgets('시설정보는 라벨과 값을 한 줄 글자로 쓴다', (tester) async {
      await _pump(tester);

      expect(find.text('화장실 개찰구 안'), findsOneWidget);
      final boxedTag = find.ancestor(
        of: find.text('화장실 개찰구 안'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).border != null,
        ),
      );
      expect(boxedTag, findsNothing);
    });

    testWidgets('역정보가 출구정보보다 위에 있다', (tester) async {
      await _pump(tester);

      expect(
        tester.getTopLeft(find.text('역정보')).dy,
        lessThan(tester.getTopLeft(find.text('출구정보')).dy),
      );
    });
  });

  group('출구 선택기', () {
    testWidgets('이전·다음 버튼과 가운데 출구 번호를 둔다', (tester) async {
      await _pump(tester);

      expect(_currentExitNumber(tester), '1');
      expect(
        find.descendant(of: _currentExit, matching: find.text('번 출구')),
        findsOneWidget,
      );
      expect(find.byTooltip('이전 출구'), findsOneWidget);
      expect(find.byTooltip('다음 출구'), findsOneWidget);
      expect(find.byKey(const Key('stationExitPillTabs')), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('이전 출구'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('다음을 누르면 다음 출구의 정보로 바뀐다', (tester) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('다음 출구'));
      await tester.pumpAndSettle();

      expect(_currentExitNumber(tester), '2');
      expect(find.text('대한극장'), findsOneWidget);
      expect(find.text('필동주민센터, 남산골한옥마을'), findsNothing);
    });

    testWidgets('출구 번호를 누르면 목록에서 고를 수 있다', (tester) async {
      await _pump(tester);

      await tester.tap(_currentExit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3번 출구'));
      await tester.pumpAndSettle();

      expect(_currentExitNumber(tester), '3');
      expect(find.text('3번 출구'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('다음 출구'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('선택기는 출구 번호를 버튼으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'^1번 출구, 출구 목록 열기$')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('출구 정보', () {
    testWidgets('주변 시설 문장은 원천 설명 그대로, 제목 없이 쓴다', (tester) async {
      await _pump(tester);

      expect(find.text('필동주민센터, 남산골한옥마을'), findsOneWidget);
      expect(find.text('장소 정보'), findsNothing);
    });

    testWidgets('원천 설명이 없으면 자리표시 문구 없이 숨긴다', (tester) async {
      await _pump(tester, exits: [_exit('3')]);

      expect(find.textContaining('주변 및 연계 시설'), findsNothing);
      expect(_currentExitNumber(tester), '3');
    });

    testWidgets('가까운 하차문은 원천 값이 있을 때만 보인다', (tester) async {
      await _pump(tester);

      expect(find.text('출구와 가까운 하차문'), findsOneWidget);
      expect(find.text('오금 방면 4-4, 대화 방면 7-1'), findsOneWidget);

      await tester.tap(find.byTooltip('다음 출구'));
      await tester.pumpAndSettle();
      expect(find.text('출구와 가까운 하차문'), findsNothing);
    });

    testWidgets('엘리베이터 연결은 원천 확인 근거가 없어 화면과 낭독 모두 숨긴다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(find.textContaining('엘리베이터 연결'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('엘리베이터 연결')), findsNothing);
      handle.dispose();
    });

    testWidgets('확인된 계단 정보는 선택기 아래 상자 없는 한 줄이다', (tester) async {
      await _pump(tester);

      expect(find.text('계단 없는 이동 가능'), findsOneWidget);
      final boxed = find.ancestor(
        of: find.text('계단 없는 이동 가능'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration != null,
        ),
      );
      expect(boxed, findsNothing);
      expect(
        tester.getTopLeft(find.text('계단 없는 이동 가능')).dy,
        greaterThan(tester.getBottomLeft(_currentExit).dy),
      );
    });
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('글자 2.0배, 폭 $width에서 넘치지 않는다', (tester) async {
      await _pump(tester, width: width, textScale: 2);

      expect(tester.takeException(), isNull);
    });
  }
}
