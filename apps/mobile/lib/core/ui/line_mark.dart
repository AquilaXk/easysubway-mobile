import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../accessible_design.dart';

/// 목록 행·상단바·검색 결과가 노선 마크를 그리는 기본 한 변(dp). 마크를 쓰는
/// 화면이 각자 20을 따로 두지 않고 이 값 하나를 쓴다.
const lineMarkDefaultSize = 20.0;

/// 높이가 정해진 칸(상단바, 탭 줄, 지도 위 캡슐, 입력 행) 안에 놓이는 마크가
/// 글자 크기 설정을 따라 커지는 상한. 이런 칸은 마크가 커지면 칸 밖으로 나가므로
/// 그 칸의 마크만 이 값을 넘겨 `maxTextScale`로 쓴다. 마크 안 글자도 같은 비율로
/// 커지므로 상한에서도 글자는 마크 안에 들어간다.
///
/// 1.3은 Flutter Material `NavigationBar`가 고정 높이 칸 안 라벨에 거는 상한
/// (`_kMaxLabelTextScaleFactor = 1.3`, flutter/lib/src/material/navigation_bar.dart)과
/// 같다. 높이가 늘 수 있는 행(검색 결과, 최근 검색, 경로 노드)의 마크는 이 상한
/// 없이 시스템 배율을 그대로 따른다.
const lineMarkFixedChromeMaxTextScale = 1.3;

/// 한 글자 라벨(호선 번호)은 원, 그 밖의 공식 약칭은 알약이다. 마크를 그리는
/// 모든 곳이 이 한 규칙을 쓴다.
bool isLineMarkCircle(String label) => label.length <= 1;

/// [size]를 글자 크기 설정에 맞춰 키운 마크 한 변. [maxTextScale]이 있으면 그
/// 배율에서 멈추고, 없으면 시스템 배율을 그대로 따른다. 번들 PNG 마크와
/// [LineMark]가 같은 값을 쓴다.
double scaledLineMarkSize(
  BuildContext context,
  double size, {
  double? maxTextScale,
}) => _lineMarkScaler(context, maxTextScale).scale(size);

TextScaler _lineMarkScaler(BuildContext context, double? maxTextScale) {
  final scaler = MediaQuery.textScalerOf(context);
  return maxTextScale == null
      ? scaler
      : scaler.clamp(maxScaleFactor: maxTextScale);
}

/// 흰 바탕 위 노선색 글자의 최소 대비(WCAG 2.1 1.4.3 본문 글자 4.5:1).
const _minTextContrastOnWhite = 4.5;

/// 흰 바탕 위에 노선색으로 글자를 쓸 때의 색. 노선색이 흰 바탕과 4.5:1을 넘으면
/// 그대로 쓰고, 못 넘으면 같은 색상(hue)에서 명도만 낮춘다. 경로 역할색 토큰을
/// 만든 방식(design_tokens.dart `EasySubwayFanMenuColors`)과 같다.
Color lineInkOnWhite(Color lineColor) {
  const white = EasySubwayAccessibleColors.surface;
  const lightnessStep = 0.01;
  final hsl = HSLColor.fromColor(lineColor);
  var lightness = hsl.lightness;
  var ink = lineColor;
  while (_contrast(ink, white) < _minTextContrastOnWhite && lightness > 0) {
    lightness = math.max(0, lightness - lightnessStep);
    ink = hsl.withLightness(lightness).toColor();
  }
  return ink;
}

double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 노선 마크 단일 그림. 한 글자 라벨(호선 번호)은 노선색 원 안 흰 글자, 그 밖의
/// 공식 약칭은 노선색 알약 안 흰 글자다. 글자는 배경색과 무관하게 항상 흰색이다.
///
/// [onLineColor]는 노선색 막대 위에 얹는 마크다. 흰 면에 노선색 테두리를 두고,
/// 글자는 노선색 대신 [lineInkOnWhite]로 4.5:1을 맞춘 같은 색상의 어두운 색을
/// 쓴다(상용 지하철 서비스 경로 결과의 구간 막대). 노선색 그대로는 밝은 노선에서
/// 흰 면과의 대비가 모자란다.
///
/// [maxTextScale]은 높이가 정해진 칸 안의 마크만 [lineMarkFixedChromeMaxTextScale]로
/// 넘긴다. 기본 null은 상한이 없어 시스템 글자 배율을 그대로 따른다.
///
/// 알약 비율은 상용 서비스 역 검색 화면 실측(3x 캡처)을 따른다. 높이 18pt 알약의
/// 글자는 약 10.5pt(높이의 0.58배), 좌우 여백은 약 6pt(높이의 0.33배)다.
class LineMark extends StatelessWidget {
  const LineMark({
    required this.label,
    required this.color,
    this.size = lineMarkDefaultSize,
    this.maxTextScale,
    this.onLineColor = false,
    super.key,
  });

  final String label;
  final Color color;
  final double size;
  final double? maxTextScale;
  final bool onLineColor;

  static const _circleFontRatio = 0.6;
  static const _pillFontRatio = 0.58;
  static const _pillPaddingRatio = 0.33;
  static const _minPillFontSize = 10.5;
  static const _onLineRingWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final isCircle = isLineMarkCircle(label);
    final scaler = _lineMarkScaler(context, maxTextScale);
    final markSize = scaler.scale(size);
    final fontSize = scaler.scale(
      isCircle
          ? size * _circleFontRatio
          : math.max(_minPillFontSize, size * _pillFontRatio),
    );
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: onLineColor
            ? lineInkOnWhite(color)
            : EasySubwayAccessibleColors.interactionOnPrimary,
        fontSize: fontSize,
        fontWeight: EasySubwayFontWeight.boldForContrast,
        height: 1.0,
      ),
    );

    final face = onLineColor ? EasySubwayAccessibleColors.surface : color;
    final ring = onLineColor
        ? Border.all(color: color, width: _onLineRingWidth)
        : null;
    if (isCircle) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: face,
          shape: BoxShape.circle,
          border: ring,
        ),
        child: SizedBox.square(
          dimension: markSize,
          child: Center(child: text),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: face,
        border: ring,
        borderRadius: BorderRadius.circular(markSize / 2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: markSize),
        child: SizedBox(
          height: markSize,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: markSize * _pillPaddingRatio,
            ),
            child: Center(widthFactor: 1, child: text),
          ),
        ),
      ),
    );
  }
}
