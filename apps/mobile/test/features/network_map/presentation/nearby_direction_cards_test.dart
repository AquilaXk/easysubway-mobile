import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_arrival_panel.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_timetable_panel.dart';
import 'package:easysubway_mobile/features/stations/presentation/service_pattern_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _line3Orange = Color(0xFFEF7C1C);

Widget _host(Widget child, {double width = 390, double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

NearbyArrivalPanel _realtime({
  List<NearbyArrivalData> arrivals = const [],
  NearbyArrivalPanelStatus status = NearbyArrivalPanelStatus.fresh,
  VoidCallback? onOpenDirection,
}) {
  return NearbyArrivalPanel(
    data: NearbyArrivalPanelData(status: status, arrivals: arrivals),
    leftName: '을지로3가',
    rightName: '동대입구',
    onOpenDirection: onOpenDirection,
    now: DateTime(2026, 10, 24, 12, 37),
  );
}

NearbyTimetablePanel _timetable(
  NearbyTimetablePanelData? data, {
  required DateTime now,
}) {
  return NearbyTimetablePanel(
    data: data,
    leftName: '을지로3가',
    rightName: '동대입구',
    expressBadgeBuilder: () => const ServicePatternBadge.express(),
    now: now,
    enableTicker: false,
  );
}

NearbyTimetableDirectionData _direction(String name, List<int> secondsList) {
  return NearbyTimetableDirectionData(
    name: name,
    departures: [
      for (final seconds in secondsList)
        NearbyTimetableDepartureData(
          directionName: name,
          seconds: seconds,
          timeLabel:
              '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
              '${(seconds % 3600 ~/ 60).toString().padLeft(2, '0')}',
          semanticLabel: '$name 방면 출발',
          isExpress: false,
          destination: '오금',
        ),
    ],
  );
}

Text _textWidget(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text));

void main() {
  group('방면 카드 제목', () {
    testWidgets('제목은 노선색이 아니라 본문 검정 강조 글자다', (tester) async {
      await tester.pumpWidget(_host(_realtime()));

      for (final title in ['을지로3가 방면', '동대입구 방면']) {
        final style = _textWidget(tester, title).style!;
        expect(style.color, EasySubwayAccessibleColors.contentPrimary);
        expect(style.fontWeight, EasySubwayFontWeight.emphasis);
      }
      final lineColored = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            _spanColors(widget.text).contains(_line3Orange),
      );
      expect(lineColored, findsNothing);
    });

    testWidgets('카드를 누르면 그 방면을 연다. 콜백이 없으면 꺽쇠도 없다', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(_realtime(onOpenDirection: () => opened += 1)),
      );

      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
      await tester.tap(find.text('동대입구 방면'));
      expect(opened, 1);

      await tester.pumpWidget(_host(_realtime()));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });

  group('실시간 카드 본문', () {
    testWidgets('행선지는 왼쪽 보조 글자, 남은 시간은 오른쪽 빨강 강조 글자다', (tester) async {
      await tester.pumpWidget(
        _host(
          _realtime(
            arrivals: const [
              NearbyArrivalData(
                direction: '하행',
                destination: '약수',
                etaSeconds: 19 * 60,
                message: '',
              ),
            ],
          ),
        ),
      );

      final destination = _textWidget(tester, '약수').style!;
      expect(destination.color, EasySubwayAccessibleColors.contentSecondary);
      final eta = _textWidget(tester, '19분').style!;
      expect(eta.color, EasySubwayAccessibleColors.statusDestructive);
      expect(eta.fontWeight, EasySubwayFontWeight.emphasis);
      expect(
        tester.getCenter(find.text('19분')).dx,
        greaterThan(tester.getCenter(find.text('약수')).dx),
      );
      expect(find.text('약수행'), findsNothing);
      expect(find.textContaining('뒤 도착'), findsNothing);
    });

    testWidgets('1시간이 넘으면 시간과 분으로 쓴다', (tester) async {
      await tester.pumpWidget(
        _host(
          _realtime(
            arrivals: const [
              NearbyArrivalData(
                direction: '하행',
                destination: '오금',
                etaSeconds: 65 * 60,
                message: '',
              ),
            ],
          ),
        ),
      );

      expect(find.text('1시간 5분'), findsOneWidget);
    });

    testWidgets('긴 도착 안내는 행선지 옆에 끼우지 않고 아래 줄 전체 폭을 쓴다', (tester) async {
      await tester.pumpWidget(
        _host(
          _realtime(
            arrivals: const [
              NearbyArrivalData(
                direction: '하행',
                destination: '불암산',
                etaSeconds: null,
                message: '[3]번째 전역 (고잔)',
              ),
            ],
          ),
        ),
      );

      final destination = tester.getRect(find.text('불암산'));
      final eta = tester.getRect(find.text('[3]번째 전역 (고잔)'));
      expect(eta.top, greaterThanOrEqualTo(destination.bottom));
      expect(eta.left, closeTo(destination.left, 0.5));
    });

    testWidgets('짧은 남은 시간은 행선지와 같은 줄 오른쪽 끝에 둔다', (tester) async {
      await tester.pumpWidget(
        _host(
          _realtime(
            arrivals: const [
              NearbyArrivalData(
                direction: '하행',
                destination: '약수',
                etaSeconds: 19 * 60,
                message: '',
              ),
            ],
          ),
        ),
      );

      final destination = tester.getRect(find.text('약수'));
      final eta = tester.getRect(find.text('19분'));
      expect(eta.center.dy, closeTo(destination.center.dy, 0.5));
      final card = tester.getRect(
        find
            .ancestor(of: find.text('19분'), matching: find.byType(Material))
            .first,
      );
      expect(card.right - eta.right, lessThan(card.width / 4));
    });

    testWidgets('도착 정보가 없는 방면은 실시간 정보 없음과 시간표 안내를 보인다', (tester) async {
      await tester.pumpWidget(_host(_realtime()));

      expect(find.text('실시간 정보 없음'), findsNWidgets(2));
      expect(find.text('(시간표를 확인해 주세요.)'), findsNWidgets(2));
      expect(find.text('-'), findsNothing);
    });

    testWidgets('실시간을 받지 못한 상태도 같은 문구다', (tester) async {
      await tester.pumpWidget(
        _host(_realtime(status: NearbyArrivalPanelStatus.unavailable)),
      );

      expect(find.text('실시간 정보 없음'), findsNWidgets(2));
    });

    testWidgets('실시간에는 운행 종료 신호가 없어 운행종료를 그리지 않는다', (tester) async {
      await tester.pumpWidget(_host(_realtime()));

      expect(find.text('운행종료'), findsNothing);
    });

    testWidgets('카드마다 제목과 본문을 한 번에 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          _realtime(
            onOpenDirection: () {},
            arrivals: const [
              NearbyArrivalData(
                direction: '하행',
                destination: '약수',
                etaSeconds: 19 * 60,
                message: '',
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('동대입구 방면')),
        isSemantics(
          label: '동대입구 방면, 약수행 19분',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        find.bySemanticsLabel('을지로3가 방면, 실시간 정보 없음 (시간표를 확인해 주세요.)'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('시간표 카드 본문', () {
    testWidgets('남은 출발이 없는 방면은 운행종료다', (tester) async {
      await tester.pumpWidget(
        _host(
          _timetable(
            NearbyTimetablePanelData(
              directions: [
                _direction('을지로3가', [6 * 3600, 23 * 3600]),
                _direction('동대입구', [6 * 3600, 23 * 3600 + 50 * 60]),
              ],
            ),
            now: DateTime(2026, 10, 24, 23, 30),
          ),
        ),
      );

      expect(find.text('운행종료'), findsOneWidget);
      expect(find.text('20분'), findsOneWidget);
      final ended = _textWidget(tester, '운행종료').style!;
      expect(ended.color, EasySubwayAccessibleColors.contentMuted);
    });

    testWidgets('시간표가 없으면 방면마다 시간표 정보 없음이다', (tester) async {
      await tester.pumpWidget(
        _host(_timetable(null, now: DateTime(2026, 10, 24, 12))),
      );

      expect(find.text('시간표 정보 없음'), findsNWidgets(2));
      expect(find.text('-'), findsNothing);
    });
  });

  group('큰 글자와 대비', () {
    for (final width in [320.0, 390.0]) {
      testWidgets('글자 2.0배, 폭 $width에서 넘치지 않는다', (tester) async {
        await tester.pumpWidget(
          _host(
            _realtime(
              onOpenDirection: () {},
              arrivals: const [
                NearbyArrivalData(
                  direction: '하행',
                  destination: '동대문역사문화공원',
                  etaSeconds: 65 * 60,
                  message: '',
                ),
              ],
            ),
            width: width,
            textScale: 2,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('카드 글자는 4.5:1 대비를 넘는다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          _realtime(
            arrivals: const [
              NearbyArrivalData(
                direction: '하행',
                destination: '약수',
                etaSeconds: 19 * 60,
                message: '',
              ),
            ],
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}

Set<Color> _spanColors(InlineSpan span) {
  final colors = <Color>{};
  span.visitChildren((child) {
    final color = child.style?.color;
    if (color != null) {
      colors.add(color);
    }
    return true;
  });
  return colors;
}
