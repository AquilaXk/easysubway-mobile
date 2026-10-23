import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/host_text_contrast.dart';
import 'support/journey_result_fixture.dart';

/// 노선색 면 위 흰 글자와 시간 버튼의 글자 대비(#503).
///
/// 글자 굵기를 400·500으로 내리면 Flutter `textContrastGuideline`이 14pt 이상
/// 굵은 글자(w700)에게만 주는 3:1 기준이 사라져 4.5:1이 필요해진다. 노선색 위
/// 흰 글자는 라인 2호선 3.13, 6호선 3.22, 공항철도 3.55라 w700일 때만 통과한다.
/// 이 글자들은 화면 의미 구성(`ExcludeSemantics`, "이전역 신림" 접두어)에 가려
/// 화면 전수 검사가 보지 못하므로 호스트마다 직접 검사한다.
Color _lineColor(String lineName) =>
    stationLineColor(fallbackLineColorHex(lineName: lineName));

void main() {
  group('주변역 바 이웃역 이름', () {
    for (final (lineName, badge) in const [
      ('2호선', '2'),
      ('6호선', '6'),
      ('공항철도', ''),
    ]) {
      testWidgets('$lineName 노선색 위 흰 이름이 대비 기준을 지킨다', (tester) async {
        await expectHostTextContrast(
          tester,
          SizedBox(
            width: 340,
            child: NearbyStationLineBar(
              stationName: '신도림',
              leftName: '서울대입구',
              rightName: '신림',
              badgeText: badge,
              lineColor: _lineColor(lineName),
              onStationNameTap: () {},
              onLeftNameTap: () {},
              onRightNameTap: () {},
            ),
          ),
        );
      });
    }

    testWidgets('탭 동작이 없는 바도 같은 기준을 지킨다', (tester) async {
      await expectHostTextContrast(
        tester,
        SizedBox(
          width: 340,
          child: NearbyStationLineBar(
            stationName: '신도림',
            leftName: '서울대입구',
            rightName: '신림',
            badgeText: '2',
            lineColor: _lineColor('2호선'),
          ),
        ),
      );
    });
  });

  group('LineMark 안 흰 글자', () {
    for (final (label, lineName, size, scale) in const [
      ('공항철도', '공항철도', 26.0, 1.0),
      ('경춘', '경춘선', 20.0, 1.3),
      ('2', '2호선', 26.0, 1.0),
      ('6', '6호선', 24.0, 1.0),
    ]) {
      testWidgets('$label 마크 $size dp 글자 $scale배', (tester) async {
        final color = label == '경춘'
            ? const Color(0xFF0C8E72)
            : _lineColor(lineName);
        await expectHostTextContrast(
          tester,
          Center(
            child: LineMark(
              label: label,
              color: color,
              size: size,
              maxTextScale: scale == 1.0
                  ? null
                  : lineMarkFixedChromeMaxTextScale,
            ),
          ),
          textScale: scale,
        );
      });
    }
  });

  group('검사 도우미', () {
    Widget chip(FontWeight weight) => Center(
      child: Container(
        color: const Color(0xFF0090D2),
        padding: const EdgeInsets.all(8),
        child: Text(
          '공항철도',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: weight,
          ),
        ),
      ),
    );

    testWidgets('의미 노드에 가려진 w400 흰 글자도 잡아낸다', (tester) async {
      final result = await evaluateHostTextContrast(
        tester,
        ExcludeSemantics(child: chip(EasySubwayFontWeight.regular)),
      );

      expect(result.passed, isFalse);
      expect(result.reason, contains('found 3.55'));
    });

    testWidgets('같은 글자가 w700이면 통과한다', (tester) async {
      await expectHostTextContrast(
        tester,
        ExcludeSemantics(child: chip(EasySubwayFontWeight.boldForContrast)),
      );
    });
  });

  group('경로 검색 시간 버튼', () {
    Future<void> pumpJourney(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 2000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            textTheme: easySubwayTextTheme(
              ThemeData(useMaterial3: true).textTheme,
            ),
          ),
          home: JourneySearchScreen(
            repository: FixtureJourneyRepository(),
            attestor: const FixtureIntegrityAttestor(),
            draft: fixtureRouteDraft(),
            mobilityType: 'WHEELCHAIR',
            onShellBackToHome: () {},
            stationNameResolver: fixtureStationName,
            transferGuideRepository: const FixtureTransferGuideRepository(),
            journeyNow: () => DateTime.utc(2026, 8, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (mode, chipKey, buttonKey, label) in const [
      (
        '예약',
        'journey-departure-scheduled',
        'journey-scheduled-time',
        '출발 시간 선택',
      ),
      ('구간', 'journey-departure-window', 'journey-window-time', '출발 대안 시간대 선택'),
      (
        '막차',
        'journey-departure-last-connection',
        'journey-last-connection-date',
        '안심 막차 운행일 선택',
      ),
    ]) {
      testWidgets('$mode 모드 시간 버튼 글자가 4.5:1을 넘는다', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await pumpJourney(tester);
          await tester.ensureVisible(find.byKey(Key(chipKey)));
          await tester.tap(find.byKey(Key(chipKey)));
          await tester.pumpAndSettle();

          // 가이드라인은 의미 라벨과 글자가 같은 노드만 본다. 버튼 라벨이 글자와
          // 같아야 이 검사가 실제로 그 글자에 닿는다.
          expect(tester.getSemantics(find.byKey(Key(buttonKey))).label, label);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        } finally {
          semantics.dispose();
        }
      });
    }
  });
}
