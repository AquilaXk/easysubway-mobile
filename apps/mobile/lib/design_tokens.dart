import 'package:flutter/material.dart';

import 'accessible_design.dart';

/// v4 간격 스케일. 박스 대신 여백이 그룹을 만든다 (#1915).
abstract final class EasySubwaySpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// v4 radius 스케일. 라운드는 떠 있는 표면(컨트롤·카드·시트)에만 쓴다.
abstract final class EasySubwayRadius {
  static const control = 8.0;
  static const card = 12.0;
  static const sheet = 16.0;
}

/// v4 의미 색 토큰. 라이트 값은 [EasySubwayAccessibleColors]를 원천으로 한다.
///
/// #1917(다크 모드)이 dark 인스턴스를 추가한다 — 필드를 늘릴 때는
/// 다크 대응 값을 함께 정의할 수 있는지 확인할 것.
@immutable
class EasySubwayTokens extends ThemeExtension<EasySubwayTokens> {
  const EasySubwayTokens({
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.line,
    required this.surface,
    required this.scaffold,
    required this.accent,
    required this.good,
    required this.warn,
    required this.danger,
    required this.mapSelectionAccent,
    required this.mapRegionAccent,
  });

  static const light = EasySubwayTokens(
    ink: EasySubwayAccessibleColors.contentPrimary,
    inkSecondary: EasySubwayAccessibleColors.contentSecondary,
    inkMuted: EasySubwayAccessibleColors.contentMuted,
    line: EasySubwayAccessibleColors.borderSubtle,
    surface: EasySubwayAccessibleColors.surfaceDefault,
    scaffold: EasySubwayAccessibleColors.surfaceScaffold,
    accent: EasySubwayAccessibleColors.interactionPrimary,
    good: EasySubwayAccessibleColors.statusSuccessContent,
    warn: EasySubwayAccessibleColors.statusWarningContent,
    danger: EasySubwayAccessibleColors.statusDangerContent,
    // 지도 오버레이 전용 — 지도 배경 시인성 때문에 accent로 수렴하지 않는다
    // (network_map의 기존 설계 의도 승계).
    mapSelectionAccent: EasySubwayAccessibleColors.mapSelectionAccent,
    mapRegionAccent: EasySubwayAccessibleColors.mapRegionAccent,
  );

  /// 본문 텍스트.
  final Color ink;

  /// 보조 텍스트.
  final Color inkSecondary;

  /// 흐린 텍스트·비활성.
  final Color inkMuted;

  /// 구분선·얇은 테두리.
  final Color line;

  /// 기본 표면.
  final Color surface;

  /// 스캐폴드 배경.
  final Color scaffold;

  /// 브랜드 액센트 — CTA·선택 상태·링크에만 쓴다.
  final Color accent;

  /// 정상·복구 상태 (아이콘+텍스트에만, 배경 틴트 금지).
  final Color good;

  /// 주의 상태 (아이콘+텍스트에만, 배경 틴트 금지).
  final Color warn;

  /// 고장·오류 상태 (아이콘+텍스트에만, 배경 틴트 금지).
  final Color danger;

  /// 지도 위 선택 역 말풍선 톤.
  final Color mapSelectionAccent;

  /// 지도 위 지역 선택 칩 톤.
  final Color mapRegionAccent;

  static EasySubwayTokens of(BuildContext context) =>
      Theme.of(context).extension<EasySubwayTokens>() ?? light;

  @override
  EasySubwayTokens copyWith({
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? line,
    Color? surface,
    Color? scaffold,
    Color? accent,
    Color? good,
    Color? warn,
    Color? danger,
    Color? mapSelectionAccent,
    Color? mapRegionAccent,
  }) {
    return EasySubwayTokens(
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      surface: surface ?? this.surface,
      scaffold: scaffold ?? this.scaffold,
      accent: accent ?? this.accent,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      mapSelectionAccent: mapSelectionAccent ?? this.mapSelectionAccent,
      mapRegionAccent: mapRegionAccent ?? this.mapRegionAccent,
    );
  }

  @override
  EasySubwayTokens lerp(EasySubwayTokens? other, double t) {
    if (other == null) {
      return this;
    }
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return EasySubwayTokens(
      ink: lerpColor(ink, other.ink),
      inkSecondary: lerpColor(inkSecondary, other.inkSecondary),
      inkMuted: lerpColor(inkMuted, other.inkMuted),
      line: lerpColor(line, other.line),
      surface: lerpColor(surface, other.surface),
      scaffold: lerpColor(scaffold, other.scaffold),
      accent: lerpColor(accent, other.accent),
      good: lerpColor(good, other.good),
      warn: lerpColor(warn, other.warn),
      danger: lerpColor(danger, other.danger),
      mapSelectionAccent: lerpColor(
        mapSelectionAccent,
        other.mapSelectionAccent,
      ),
      mapRegionAccent: lerpColor(mapRegionAccent, other.mapRegionAccent),
    );
  }
}

/// 경로 역할색(팬메뉴·출발/경유/도착 라벨·물방울 핀 공통).
///
/// Palette A — City Sophistication (2026-07-22):
/// 흰 노선도·교통약자 UX에 맞춰 원색 힘을 빼고 선명도만 남긴 시티 톤.
/// (Palette B 네온 틸/마젠타는 노선색 충돌·고령 시인성 리스크로 보류.)
/// 예전 SVG 원본(`#176FD1`/`#BF5700`/`#D9252E`)은 탁·갈색으로 보여 폐기.
/// [EasySubwayTokens] 의미 토큰으로 수렴하지 않는다(design_guard 로컬 상수).
abstract final class EasySubwayFanMenuColors {
  static const disabledOpacity = 0.40;
  static const pressedOpacity = 0.84;

  /// City Sky — 맑고 살짝 보랏빛 도는 모던 스카이 블루. 흰 글자 대비 4.5:1을
  /// 넘기도록 같은 색상(hue 210)에서 명도만 낮췄다(#464, 이전 `0A84FF`는 3.65).
  static const departure = Color(0xFF0070E0);
  static const departureSurface = Color(0xFFF2F8FF);
  static const departurePressed = Color(0xFFE1F0FF);

  /// Amber Gold — 갈색 없는 선명한 엠버. 경유 역할이 한눈에 구분되게.
  /// 밝은 면이라 흰 글자(2.06:1) 대신 어두운 글자를 얹는다([waypointRole]).
  static const waypoint = Color(0xFFFF9F0A);
  static const waypointSurface = Color(0xFFFFF8ED);
  static const waypointPressed = Color(0xFFFFEFCC);

  /// Coral Burst — 화사한 코랄 레드. 도착 주목도↑·답답함↓. 흰 글자 대비 4.5:1을
  /// 넘기도록 같은 색상(hue 3)에서 명도만 낮췄다(#464, 이전 `FF3B30`은 3.55).
  static const arrival = Color(0xFFD92B20);
  static const arrivalSurface = Color(0xFFFFF5F4);
  static const arrivalPressed = Color(0xFFFFE8E6);

  /// 물방울 핀 soft drop — rgba(0,0,0,0.25), Y:3, Blur:6.
  static const pinShadow = Color(0x40000000);

  /// 역할색보다 한 톤 진한 외곽(참조: 블루 면 `#2B66F6` → 선 `#1A429F` 대비).
  static const pinEdgeDeparture = Color(0xFF0654A1);

  /// 앰버 면(`FF9F0A`)보다 2.33:1 진해 지도 위에서 핀 윤곽이 구분된다.
  static const pinEdgeWaypoint = Color(0xFFA16506);

  /// 연한 면·흰 면 위에 놓는 경유 글자. 앰버 면과 같은 색상(hue 36)에서 명도만
  /// 낮췄다(흰 면 4.80:1, 연한 면 4.54:1). 핀 외곽선과 값이 같아도 용도가 달라
  /// 따로 둔다(한쪽을 바꿔도 다른 쪽이 움직이지 않게).
  static const waypointInk = Color(0xFFA16506);
  static const pinEdgeArrival = Color(0xFFA1251E);

  /// ✕ — 흰 원 + 헤어라인 + 차분한 잉크.
  static const pinClearBg = Color(0xFFFFFFFF);
  static const pinClearBorder = Color(0xFFE5E5E5);
  static const pinClearInk = Color(0xFF666666);

  /// ✕ soft drop — rgba(0,0,0,0.15), Y:2, Blur:4.
  static const pinClearShadow = Color(0x26000000);
  static const closeSurface = Color(0xFFF5F7FA);
  static const closePressed = Color(0xFFE9EDF2);
  static const closeInk = Color(0xFF475467);
  // 세그먼트 사이 내부 구분선 색. QA 결과 외곽선과 옅기 차이를 두면 위계가
  // 흐릿해 보여, 외곽선(outline)과 동일 톤으로 통일한다(#2200 절충안, 오너
  // 확정 2026-07-17). 굵기 차이(structuralStrokeWidth vs dividerStrokeWidth,
  // station_fan_menu.dart 참고)로만 내부/외곽 위계를 만든다.
  static const border = Color(0xE8404445);
  // 팬 메뉴 도입 전(#2109/PR #2112) 사각형 역 액션 시트가 쓰던 외곽 색을 그대로
  // 계승한다(구 시트 Material color 0xE8404445, 오너 지시 2026-07-16).
  static const outline = Color(0xE8404445);

  /// 팬 메뉴 앵커 역명 라벨의 텍스트 잉크.
  static const ink = Color(0xFF20262E);

  /// 역할별 면과 글자 쌍. 면 색에 따라 얹는 글자색이 달라지므로(출발·도착은
  /// 흰 글자, 경유는 어두운 글자) 한 곳에서 묶어 쓴다.
  static const departureRole = EasySubwayRoleColor(
    face: departure,
    onFace: EasySubwayAccessibleColors.interactionOnPrimary,
    ink: departure,
    surface: departureSurface,
    pressedSurface: departurePressed,
    pinEdge: pinEdgeDeparture,
  );
  static const waypointRole = EasySubwayRoleColor(
    face: waypoint,
    onFace: ink,
    ink: waypointInk,
    surface: waypointSurface,
    pressedSurface: waypointPressed,
    pinEdge: pinEdgeWaypoint,
  );
  static const arrivalRole = EasySubwayRoleColor(
    face: arrival,
    onFace: EasySubwayAccessibleColors.interactionOnPrimary,
    ink: arrival,
    surface: arrivalSurface,
    pressedSurface: arrivalPressed,
    pinEdge: pinEdgeArrival,
  );
}

/// 출발·경유·도착 역할 하나의 색 묶음.
@immutable
class EasySubwayRoleColor {
  const EasySubwayRoleColor({
    required this.face,
    required this.onFace,
    required this.ink,
    required this.surface,
    required this.pressedSurface,
    required this.pinEdge,
  });

  /// 역할을 채우는 면(선택된 팬 메뉴 면, 배지, 핀).
  final Color face;

  /// [face] 위에 얹는 글자·아이콘.
  final Color onFace;

  /// 흰색·연한 면 위에 놓는 역할색 글자.
  final Color ink;

  /// 선택되지 않은 팬 메뉴 면.
  final Color surface;
  final Color pressedSurface;

  /// 지도 핀 외곽선. [face]보다 진해 핀 윤곽이 구분된다.
  final Color pinEdge;
}

/// v4 타이포 위계 — 크기·행간·색으로 위계를 만들고 굵기는 보조로만 쓴다.
///
/// w800+는 화면 타이틀(titleLarge) 한정, 본문 w500, 라벨 w600, 행 강조 w700.
TextTheme easySubwayTextTheme(TextTheme base) {
  return base.copyWith(
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.25,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
