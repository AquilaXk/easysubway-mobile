import 'dart:math' as math;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    test('타이포 위계 — 타이틀만 w800, 본문 w500, 라벨 w600', () {
      final theme = easySubwayTextTheme(
        ThemeData(useMaterial3: true).textTheme,
      );
      expect(theme.titleLarge?.fontWeight, FontWeight.w800);
      expect(theme.titleMedium?.fontWeight, FontWeight.w700);
      expect(theme.bodyLarge?.fontWeight, FontWeight.w500);
      expect(theme.bodyMedium?.fontWeight, FontWeight.w500);
      expect(theme.labelLarge?.fontWeight, FontWeight.w600);
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

  test('부채꼴 메뉴 v2 색상과 opacity를 고정한다', () {
    expect(EasySubwayFanMenuColors.disabledOpacity, 0.40);
    expect(EasySubwayFanMenuColors.pressedOpacity, 0.84);
    expect(EasySubwayFanMenuColors.departure, const Color(0xFF0070E0));
    expect(EasySubwayFanMenuColors.departureSurface, const Color(0xFFF2F8FF));
    expect(EasySubwayFanMenuColors.departurePressed, const Color(0xFFE1F0FF));
    expect(EasySubwayFanMenuColors.waypoint, const Color(0xFFFF9F0A));
    expect(EasySubwayFanMenuColors.waypointSurface, const Color(0xFFFFF8ED));
    expect(EasySubwayFanMenuColors.waypointPressed, const Color(0xFFFFEFCC));
    expect(EasySubwayFanMenuColors.arrival, const Color(0xFFD92B20));
    expect(EasySubwayFanMenuColors.arrivalSurface, const Color(0xFFFFF5F4));
    expect(EasySubwayFanMenuColors.arrivalPressed, const Color(0xFFFFE8E6));
    expect(EasySubwayFanMenuColors.pinShadow, const Color(0x40000000));
    expect(EasySubwayFanMenuColors.pinEdgeDeparture, const Color(0xFF0654A1));
    expect(EasySubwayFanMenuColors.pinEdgeWaypoint, const Color(0xFFA16506));
    expect(EasySubwayFanMenuColors.pinEdgeArrival, const Color(0xFFA1251E));
    expect(EasySubwayFanMenuColors.pinClearBg, const Color(0xFFFFFFFF));
    expect(EasySubwayFanMenuColors.pinClearBorder, const Color(0xFFE5E5E5));
    expect(EasySubwayFanMenuColors.pinClearInk, const Color(0xFF666666));
    expect(EasySubwayFanMenuColors.pinClearShadow, const Color(0x26000000));
    expect(EasySubwayFanMenuColors.closeSurface, const Color(0xFFF5F7FA));
    expect(EasySubwayFanMenuColors.closePressed, const Color(0xFFE9EDF2));
    expect(EasySubwayFanMenuColors.closeInk, const Color(0xFF475467));
    expect(EasySubwayFanMenuColors.border, const Color(0xE8404445));
    expect(EasySubwayFanMenuColors.outline, const Color(0xE8404445));
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

    // 상용 지하철 서비스와 같은 계열(파랑·빨강)을 유지하면서 흰 글자 대비만 통과시킨
    // 출발·도착 역할색. 이전 색(0A84FF·FF3B30)은 흰 글자 대비 3.65·3.55였다.
    const previousDeparture = Color(0xFF0A84FF);
    const previousArrival = Color(0xFFFF3B30);
    const maxHueShiftDegrees = 4.0;

    final roles = <String, ({Color role, Color previous, Color surface})>{
      '출발': (
        role: EasySubwayFanMenuColors.departure,
        previous: previousDeparture,
        surface: EasySubwayFanMenuColors.departureSurface,
      ),
      '도착': (
        role: EasySubwayFanMenuColors.arrival,
        previous: previousArrival,
        surface: EasySubwayFanMenuColors.arrivalSurface,
      ),
    };

    for (final MapEntry(:key, :value) in roles.entries) {
      test('$key 역할색 위의 흰 글자(경로 카드 배지·팬 메뉴 선택 면)는 4.5:1을 넘는다', () {
        expect(
          contrast(EasySubwayAccessibleColors.interactionOnPrimary, value.role),
          greaterThanOrEqualTo(normalTextRatio),
        );
        expect(
          contrast(EasySubwayColorPrimitives.neutralWhite, value.role),
          greaterThanOrEqualTo(normalTextRatio),
        );
      });

      test('$key 역할색 글자(팬 메뉴 비선택 면의 큰 라벨)는 연한 면 위에서 3:1을 넘는다', () {
        expect(
          contrast(value.role, value.surface),
          greaterThanOrEqualTo(largeTextRatio),
        );
      });

      test('$key 역할색은 이전 색과 색상(hue)이 $maxHueShiftDegrees도 안에서 같다', () {
        final hueShift =
            (HSLColor.fromColor(value.role).hue -
                    HSLColor.fromColor(value.previous).hue)
                .abs();
        expect(hueShift, lessThanOrEqualTo(maxHueShiftDegrees));
      });
    }

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
