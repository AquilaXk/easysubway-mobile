import 'dart:math' as math;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/easy_subway_app_fixture.dart';

void main() {
  group('EasySubwayTokens', () {
    testWidgets('theme 등록이 없어도 of(context)는 light 값을 돌려준다', (tester) async {
      late EasySubwayTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              tokens = EasySubwayTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(tokens, EasySubwayTokens.light);
    });

    test('light 토큰은 시그니처 역할과 지도 오버레이 계약을 소비한다', () {
      const tokens = EasySubwayTokens.light;
      expect(tokens.ink, EasySubwayAccessibleColors.contentPrimary);
      expect(tokens.inkSecondary, EasySubwayAccessibleColors.contentSecondary);
      expect(tokens.inkMuted, EasySubwayAccessibleColors.contentMuted);
      expect(tokens.line, EasySubwayAccessibleColors.borderSubtle);
      expect(tokens.surface, EasySubwayAccessibleColors.surfaceDefault);
      expect(tokens.scaffold, EasySubwayAccessibleColors.surfaceScaffold);
      expect(tokens.accent, EasySubwayAccessibleColors.interactionPrimary);
      expect(tokens.good, EasySubwayAccessibleColors.statusSuccessContent);
      expect(tokens.warn, EasySubwayAccessibleColors.statusWarningContent);
      expect(tokens.danger, EasySubwayAccessibleColors.statusDangerContent);
      // 지도 오버레이는 일반 Theme 색과 분리된 고대비 값이다.
      expect(tokens.mapSelectionAccent, const Color(0xFF007C91));
      expect(tokens.mapRegionAccent, const Color(0xFF006FD6));
    });

    testWidgets('앱 theme에 extension으로 등록되어 of(context)로 조회된다', (tester) async {
      late EasySubwayTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [EasySubwayTokens.light],
            useMaterial3: true,
          ),
          home: Builder(
            builder: (context) {
              tokens = EasySubwayTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(identical(tokens, EasySubwayTokens.light), isTrue);
    });
  });

  group('easySubwayTextTheme', () {
    // 앱이 실제로 쓰는 테마를 읽는다. 테마를 테스트에서 따로 만들면 앱 설정이
    // 바뀌어도 이 테스트는 계속 통과한다.
    Future<TextTheme> pumpAppTextTheme(WidgetTester tester) async {
      await tester.pumpWidget(buildEasySubwayTestApp());
      await tester.pumpAndSettle();
      return Theme.of(tester.element(find.byType(Navigator).first)).textTheme;
    }

    testWidgets('한국어 화면의 역할별 굵기는 Material 3 기본 타이포와 같다', (tester) async {
      final textTheme = await pumpAppTextTheme(tester);
      // 한국어는 ScriptCategory.dense다(flutter_localizations MaterialLocalizationKo).
      final material3 = Typography.material2021().dense;
      final roles = <String, TextStyle? Function(TextTheme)>{
        'displayLarge': (t) => t.displayLarge,
        'headlineSmall': (t) => t.headlineSmall,
        'titleLarge': (t) => t.titleLarge,
        'titleMedium': (t) => t.titleMedium,
        'titleSmall': (t) => t.titleSmall,
        'bodyLarge': (t) => t.bodyLarge,
        'bodyMedium': (t) => t.bodyMedium,
        'bodySmall': (t) => t.bodySmall,
        'labelLarge': (t) => t.labelLarge,
        'labelMedium': (t) => t.labelMedium,
        'labelSmall': (t) => t.labelSmall,
      };
      roles.forEach((role, of) {
        expect(
          of(textTheme)?.fontWeight,
          of(material3)?.fontWeight,
          reason: role,
        );
      });
    });

    testWidgets('본문 역할은 400, 소제목·라벨 역할은 강조 500이다', (tester) async {
      final textTheme = await pumpAppTextTheme(tester);
      expect(EasySubwayFontWeight.regular, FontWeight.w400);
      expect(EasySubwayFontWeight.emphasis, FontWeight.w500);
      expect(textTheme.bodyLarge?.fontWeight, EasySubwayFontWeight.regular);
      expect(textTheme.titleLarge?.fontWeight, EasySubwayFontWeight.regular);
      expect(textTheme.titleMedium?.fontWeight, EasySubwayFontWeight.emphasis);
      expect(textTheme.labelLarge?.fontWeight, EasySubwayFontWeight.emphasis);
    });
  });

  group('EasySubwaySpacing / EasySubwayRadius', () {
    test('간격·radius 스케일 고정', () {
      expect(EasySubwaySpacing.xs, 4.0);
      expect(EasySubwaySpacing.sm, 8.0);
      expect(EasySubwaySpacing.md, 12.0);
      expect(EasySubwaySpacing.lg, 16.0);
      expect(EasySubwaySpacing.xl, 24.0);
      expect(EasySubwaySpacing.xxl, 32.0);
      expect(EasySubwayRadius.control, 8.0);
      expect(EasySubwayRadius.card, 12.0);
      expect(EasySubwayRadius.sheet, 16.0);
    });
  });

  test('경로 역할 핀 색상과 비활성 opacity를 고정한다', () {
    expect(EasySubwayFanMenuColors.disabledOpacity, 0.40);
    expect(EasySubwayFanMenuColors.departure, const Color(0xFF0070E0));
    expect(EasySubwayFanMenuColors.waypoint, const Color(0xFFFF9F0A));
    expect(EasySubwayFanMenuColors.arrival, const Color(0xFFD92B20));
    expect(EasySubwayFanMenuColors.pinShadow, const Color(0x40000000));
    expect(EasySubwayFanMenuColors.pinEdgeDeparture, const Color(0xFF0654A1));
    expect(EasySubwayFanMenuColors.pinEdgeWaypoint, const Color(0xFFA16506));
    expect(EasySubwayFanMenuColors.waypointInk, const Color(0xFFA16506));
    expect(EasySubwayFanMenuColors.pinEdgeArrival, const Color(0xFFA1251E));
    expect(EasySubwayFanMenuColors.pinClearBg, const Color(0xFFFFFFFF));
    expect(EasySubwayFanMenuColors.pinClearBorder, const Color(0xFFE5E5E5));
    expect(EasySubwayFanMenuColors.pinClearInk, const Color(0xFF666666));
    expect(EasySubwayFanMenuColors.pinClearShadow, const Color(0x26000000));
  });

  group('접근성 대비(WCAG 2.1)', () {
    // 일반 텍스트 4.5:1, 큰 텍스트(18pt 이상) 3:1.
    const normalTextRatio = 4.5;
    const largeTextRatio = 3.0;

    double contrast(Color a, Color b) {
      final lighter = math.max(a.computeLuminance(), b.computeLuminance());
      final darker = math.min(a.computeLuminance(), b.computeLuminance());
      return (lighter + 0.05) / (darker + 0.05);
    }

    // 상용 지하철 서비스와 같은 계열(파랑·앰버·빨강)을 유지한다. 출발·도착은 같은
    // 색상에서 명도만 낮춰 흰 글자 대비를 통과시켰다(이전 0A84FF·FF3B30은 3.65·3.55).
    // 경유는 밝은 앰버 면을 그대로 두고 어두운 글자를 얹는다(흰 글자는 2.06).
    const maxHueShiftDegrees = 4.0;
    const minPinEdgeRatio = 1.5;

    final roles =
        <
          String,
          ({
            EasySubwayRoleColor role,
            Color previousFace,
            double maxFaceHueShift,
          })
        >{
          '출발': (
            role: EasySubwayFanMenuColors.departureRole,
            previousFace: const Color(0xFF0A84FF),
            maxFaceHueShift: maxHueShiftDegrees,
          ),
          '경유': (
            role: EasySubwayFanMenuColors.waypointRole,
            previousFace: const Color(0xFFFF9F0A),
            maxFaceHueShift: 0,
          ),
          '도착': (
            role: EasySubwayFanMenuColors.arrivalRole,
            previousFace: const Color(0xFFFF3B30),
            maxFaceHueShift: maxHueShiftDegrees,
          ),
        };

    double hueGap(Color a, Color b) =>
        (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue).abs();

    for (final MapEntry(:key, :value) in roles.entries) {
      final role = value.role;

      test('$key 면 위의 글자(경로 카드 배지)는 4.5:1을 넘는다', () {
        expect(
          contrast(role.onFace, role.face),
          greaterThanOrEqualTo(normalTextRatio),
        );
      });

      test('$key 핀 외곽선은 면보다 $minPinEdgeRatio:1 이상 진해 윤곽이 구분된다', () {
        expect(
          contrast(role.face, role.pinEdge),
          greaterThanOrEqualTo(minPinEdgeRatio),
        );
      });

      test('$key 면은 이전 색과 색상(hue)이 ${value.maxFaceHueShift}도 안에서 같다', () {
        expect(
          hueGap(role.face, value.previousFace),
          lessThanOrEqualTo(value.maxFaceHueShift),
        );
      });
    }

    test('역 말풍선 흰 글자는 두 바탕에서 4.5:1, 역할 핀은 3:1을 넘는다', () {
      for (final surface in [
        EasySubwayPopoverColors.surface,
        EasySubwayPopoverColors.actionSurface,
      ]) {
        expect(
          contrast(EasySubwayPopoverColors.onSurface, surface),
          greaterThanOrEqualTo(normalTextRatio),
        );
      }
      for (final pin in [
        EasySubwayPopoverColors.originPin,
        EasySubwayPopoverColors.waypointPin,
        EasySubwayPopoverColors.destinationPin,
      ]) {
        expect(
          contrast(pin, EasySubwayPopoverColors.surface),
          greaterThanOrEqualTo(largeTextRatio),
        );
      }
    });

    test('경유 면은 원래 앰버 값을 그대로 두고 어두운 글자를 얹는다', () {
      expect(
        EasySubwayFanMenuColors.waypointRole.face,
        const Color(0xFFFF9F0A),
      );
      expect(
        contrast(
          EasySubwayFanMenuColors.waypointRole.onFace,
          EasySubwayFanMenuColors.waypointRole.face,
        ),
        greaterThanOrEqualTo(normalTextRatio),
      );
      expect(
        contrast(
          EasySubwayAccessibleColors.interactionOnPrimary,
          EasySubwayFanMenuColors.waypointRole.face,
        ),
        lessThan(normalTextRatio),
        reason: '흰 글자는 앰버 면에서 4.5:1에 못 미쳐 어두운 글자를 쓴다',
      );
    });

    test('설정 섹션 제목 글자(secondaryText)는 화면 배경 위에서 4.5:1을 넘는다', () {
      expect(
        contrast(
          EasySubwayAccessibleColors.secondaryText,
          EasySubwayAccessibleColors.scaffoldSurface,
        ),
        greaterThanOrEqualTo(normalTextRatio),
      );
    });
  });
}
