import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/core/ui/line_mark.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_title.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/onboarding/onboarding.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/core_screen_sweep_fixtures.dart';
import 'support/core_screen_sweep_screens.dart';
import 'support/host_text_contrast.dart';
import 'support/test_viewport.dart';

/// 노선색과 흰색이 맞닿은 글자와 시간 버튼의 글자 대비(#503).
///
/// 글자 굵기를 400·500으로 내리면 Flutter `textContrastGuideline`이 14pt 이상
/// 굵은 글자(w700)에게만 주는 3:1 기준이 사라져 4.5:1이 필요해진다. 노선색과 흰색의
/// 대비는 2호선 3.13, 6호선 3.22, 공항철도 3.55라 w700일 때만 통과한다. 노선색 위
/// 흰 글자도, 흰 바탕 위 노선색 글자("금정 방면" 제목)도 같다.
/// 이 글자들은 화면 의미 구성(`ExcludeSemantics`, "이전역 신림" 접두어)이나
/// `Text.rich`에 가려 화면 전수 검사가 보지 못하므로 호스트마다 직접 검사한다.
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

  group('주변역 패널 방면 제목', () {
    for (final lineName in const ['2호선', '6호선', '공항철도']) {
      testWidgets('$lineName 노선색 이름이 흰 바탕에서 대비 기준을 지킨다', (tester) async {
        await expectHostTextContrast(
          tester,
          Center(
            child: NearbyDirectionTitle(
              label: '금정 방면',
              lineColor: _lineColor(lineName),
            ),
          ),
        );
      });
    }
  });

  group('LineMark 안 흰 글자', () {
    final cases = <(String, Color, double, double)>[
      ('공항철도', _lineColor('공항철도'), 26.0, 1.0),
      ('경춘', const Color(0xFF0C8E72), 20.0, 1.3),
      ('2', _lineColor('2호선'), 26.0, 1.0),
      ('6', _lineColor('6호선'), 24.0, 1.0),
    ];
    for (final (label, color, size, scale) in cases) {
      testWidgets('$label 마크 $size dp 글자 $scale배', (tester) async {
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

    Widget richName(FontWeight weight) => Center(
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 14, fontWeight: weight),
          children: [
            TextSpan(
              text: '금정',
              style: TextStyle(color: _lineColor('2호선')),
            ),
            const TextSpan(
              text: ' 방면',
              style: TextStyle(
                color: EasySubwayAccessibleColors.contentPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    testWidgets('Text.rich의 w500 노선색 span도 잡아낸다', (tester) async {
      final result = await evaluateHostTextContrast(
        tester,
        richName(EasySubwayFontWeight.emphasis),
      );

      expect(result.passed, isFalse);
      expect(result.reason, contains('found 3.13'));
      expect(
        result.reason,
        contains('Expected contrast ratio of at least 4.5'),
      );
    });

    testWidgets('같은 Text.rich가 w700이면 통과한다', (tester) async {
      await expectHostTextContrast(
        tester,
        richName(EasySubwayFontWeight.boldForContrast),
      );
    });

    testWidgets('화면 밖 글자는 조용히 통과하지 않고 실패한다', (tester) async {
      final result = await evaluateHostTextContrast(
        tester,
        Transform.translate(
          offset: const Offset(-1000, 0),
          child: chip(EasySubwayFontWeight.boldForContrast),
        ),
      );

      expect(result.passed, isFalse);
      expect(result.reason, contains('판정에 닿지 못했다'));
    });
  });

  group('경로 검색 시간 버튼', () {
    Future<void> pumpJourney(WidgetTester tester, String departureChip) async {
      useLogicalViewport(tester, const Size(360, 2000));
      const theme = SweepTheme.standard;
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        buildSweepApp(
          navigatorKey: navigatorKey,
          onboardingState: OnboardingState.completed(
            result: OnboardingResult(
              preset: MobilityPreset.standard,
              preferences: theme.preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openSweepJourney(
        SweepScreenContext(
          tester: tester,
          navigatorKey: navigatorKey,
          theme: theme,
        ),
        search: false,
        departureChip: departureChip,
      );
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
          await pumpJourney(tester, chipKey);

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
