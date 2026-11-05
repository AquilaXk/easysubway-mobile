import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/application/station_detail_controller.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_body.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  StationDetail? detail,
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
              detail: detail ?? _station,
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

    testWidgets('다음·이전을 누르면 그 출구의 정보로 바뀐다', (tester) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('다음 출구'));
      await tester.pumpAndSettle();

      expect(_currentExitNumber(tester), '2');
      expect(find.text('대한극장'), findsOneWidget);
      expect(find.text('필동주민센터, 남산골한옥마을'), findsNothing);

      await tester.tap(find.byTooltip('이전 출구'));
      await tester.pumpAndSettle();
      expect(_currentExitNumber(tester), '1');
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

  group('역무실 전화', () {
    const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

    List<String> captureLaunchedUrls() {
      final launched = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, (call) async {
            if (call.method == 'launch' || call.method == 'canLaunch') {
              final args = call.arguments;
              if (call.method == 'launch' && args is Map) {
                final url = args['url'];
                if (url is String) {
                  launched.add(url);
                }
              }
              return true;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, null);
      });
      return launched;
    }

    const singleContactStation = StationDetail(
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
      contacts: [
        StationContact(
          lineId: 'seoul-3',
          lineName: '수도권 3호선',
          phone: '02-6110-3281',
        ),
      ],
    );

    const multiContactStation = StationDetail(
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
        StationSearchLine(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A5DE',
          stationCode: '423',
        ),
      ],
      confirmedAbsentFacilityTypes: {'WHEELCHAIR_LIFT'},
      contacts: [
        StationContact(
          lineId: 'seoul-3',
          lineName: '수도권 3호선',
          phone: '02-6110-3311',
        ),
        StationContact(lineId: 'seoul-4', phone: '02-6110-4231'),
      ],
    );

    testWidgets('연락처가 없으면 역무실 전화 섹션을 노출하지 않는다', (tester) async {
      await _pump(tester, detail: _station);

      expect(find.text('역무실 전화'), findsNothing);
      expect(
        find.byKey(const Key('stationOfficeContactSection')),
        findsNothing,
      );
    });

    testWidgets('연락처 1건일 때 역무실 전화 버튼을 표시하고 탭하면 tel: 링크를 실행한다', (tester) async {
      final launched = captureLaunchedUrls();
      await _pump(tester, detail: singleContactStation);

      expect(find.text('역무실 전화'), findsOneWidget);
      final button = find.text('역무실 전화 02-6110-3281');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(launched, ['tel:02-6110-3281']);
    });

    testWidgets('전화 실행이 false를 반환하거나 플랫폼 예외가 발생하면 오류를 보고하고 안내 스낵바를 표시한다', (
      tester,
    ) async {
      final reportedErrors = <FlutterErrorDetails>[];
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, null);
      });

      await runWithMobileErrorReporter(reportedErrors.add, () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, (call) async {
              if (call.method == 'launch') {
                return false;
              }
              return true;
            });

        await _pump(tester, detail: singleContactStation);
        await tester.tap(find.text('역무실 전화 02-6110-3281'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('전화 앱을 열 수 없어요. 02-6110-3281 번호로 직접 연락해 주세요.'),
          findsOneWidget,
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, (call) async {
              throw PlatformException(code: 'LAUNCH_FAILED', message: 'failed');
            });

        await tester.tap(find.text('역무실 전화 02-6110-3281'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('전화 앱을 열 수 없어요. 02-6110-3281 번호로 직접 연락해 주세요.'),
          findsOneWidget,
        );
      });

      expect(reportedErrors, hasLength(2));
      expect(reportedErrors[0].exception, isA<StateError>());
      expect(reportedErrors[1].exception, isA<PlatformException>());
      expect(
        reportedErrors.every(
          (details) =>
              details.context?.toDescription().contains(
                '역무실 전화 연결 실행 중 예외가 발생했습니다.',
              ) ??
              false,
        ),
        isTrue,
      );
    });

    testWidgets('타 운영사 노선과 만나는 환승역에서 연락처가 1건뿐이어도 관할 노선명을 함께 표시한다', (
      tester,
    ) async {
      const transferSingleContactStation = StationDetail(
        id: 'station-yangjae',
        nameKo: '양재',
        nameEn: 'Yangjae',
        region: '수도권',
        dataQualityLevel: 'LEVEL_1',
        lastVerifiedAt: '2026-10-24',
        lines: [
          StationSearchLine(
            id: 'seoul-3',
            name: '수도권 3호선',
            color: '#EF7C1C',
            stationCode: '342',
          ),
          StationSearchLine(
            id: 'shinbundang',
            name: '신분당선',
            color: '#D4003B',
            stationCode: 'D08',
          ),
        ],
        confirmedAbsentFacilityTypes: {'WHEELCHAIR_LIFT'},
        contacts: [
          StationContact(
            lineId: 'seoul-3',
            lineName: '수도권 3호선',
            phone: '02-6110-3421',
          ),
        ],
      );

      final handle = tester.ensureSemantics();
      await _pump(tester, detail: transferSingleContactStation);

      expect(find.text('수도권 3호선'), findsOneWidget);
      expect(find.text('역무실 전화 02-6110-3421'), findsOneWidget);
      expect(
        find.bySemanticsLabel('수도권 3호선, 역무실에 전화하기, 02 6110 3421'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('환승역 복수 노선 연락처는 노선명과 함께 목록으로 표시하고 탭하면 해당 번호로 연결한다', (
      tester,
    ) async {
      final launched = captureLaunchedUrls();
      await _pump(tester, detail: multiContactStation);

      expect(find.text('역무실 전화'), findsOneWidget);
      expect(find.text('수도권 3호선'), findsOneWidget);
      expect(find.text('역무실 전화 02-6110-3311'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('역무실 전화 02-6110-4231'), findsOneWidget);

      await tester.tap(find.text('역무실 전화 02-6110-4231'));
      await tester.pumpAndSettle();

      expect(launched, ['tel:02-6110-4231']);
    });

    testWidgets('Semantics 라벨(button: true, 하이픈 공백 치환)과 최소 터치 영역 48dp를 만족한다', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, detail: singleContactStation);

      final semanticsFinder = find.bySemanticsLabel('역무실에 전화하기, 02 6110 3281');
      expect(semanticsFinder, findsOneWidget);
      final semanticsNode = tester.getSemantics(semanticsFinder);
      expect(semanticsNode.getSemanticsData().flagsCollection.isButton, isTrue);

      final buttonFinder = find.byKey(
        const Key('stationOfficeCallButton-seoul-3'),
      );
      expect(buttonFinder, findsOneWidget);
      final size = tester.getSize(buttonFinder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    for (final width in [320.0, 412.0]) {
      testWidgets('역무실 전화(단일·복수 노선)가 글자 2.0배, 폭 $width에서 넘치거나 잘리지 않는다', (
        tester,
      ) async {
        await _pump(
          tester,
          detail: singleContactStation,
          width: width,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);

        await _pump(
          tester,
          detail: multiContactStation,
          width: width,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
