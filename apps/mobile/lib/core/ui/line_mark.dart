import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../accessible_design.dart';

/// 마크가 글자 크기 설정을 따라 커지는 상한. 마크는 이름 옆에 놓이는 기호라 그
/// 이상 키우면 이름이 들어갈 폭을 먹는다. 마크 안 글자도 같은 비율로 커지므로
/// 이 상한에서도 글자는 마크 안에 들어간다.
const lineMarkMaxTextScale = 1.3;

/// 한 글자 라벨(호선 번호)은 원, 그 밖의 공식 약칭은 알약이다. 마크를 그리는
/// 모든 곳이 이 한 규칙을 쓴다.
bool isLineMarkCircle(String label) => label.length <= 1;

/// [size]를 글자 크기 설정에 맞춰 키운 마크 한 변. [lineMarkMaxTextScale]에서
/// 멈춘다. 번들 PNG 마크와 [LineMark]가 같은 값을 쓴다.
double scaledLineMarkSize(BuildContext context, double size) =>
    _lineMarkScaler(context).scale(size);

TextScaler _lineMarkScaler(BuildContext context) => MediaQuery.textScalerOf(
  context,
).clamp(maxScaleFactor: lineMarkMaxTextScale);

/// 노선 마크 단일 그림. 한 글자 라벨(호선 번호)은 노선색 원 안 흰 글자, 그 밖의
/// 공식 약칭은 노선색 알약 안 흰 글자다. 글자는 배경색과 무관하게 항상 흰색이다.
///
/// 알약 비율은 상용 서비스 역 검색 화면 실측(3x 캡처)을 따른다. 높이 18pt 알약의
/// 글자는 약 10.5pt(높이의 0.58배), 좌우 여백은 약 6pt(높이의 0.33배)다.
class LineMark extends StatelessWidget {
  const LineMark({
    required this.label,
    required this.color,
    this.size = 20,
    super.key,
  });

  final String label;
  final Color color;
  final double size;

  static const _circleFontRatio = 0.6;
  static const _pillFontRatio = 0.58;
  static const _pillPaddingRatio = 0.33;
  static const _minPillFontSize = 10.5;

  @override
  Widget build(BuildContext context) {
    final isCircle = isLineMarkCircle(label);
    final scaler = _lineMarkScaler(context);
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
        color: EasySubwayAccessibleColors.interactionOnPrimary,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1.0,
      ),
    );

    if (isCircle) {
      return DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: SizedBox.square(
          dimension: markSize,
          child: Center(child: text),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
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
