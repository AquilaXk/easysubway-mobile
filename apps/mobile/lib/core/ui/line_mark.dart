import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../accessible_design.dart';

/// 노선 마크 단일 그림. 한 글자 라벨(호선 번호)은 노선색 원 안 흰 글자, 그 밖의
/// 공식 약칭은 노선색 알약 안 흰 글자다. 글자는 배경색과 무관하게 항상 흰색이다.
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

  static const _minPillFontSize = 10.5;

  @override
  Widget build(BuildContext context) {
    final isCircle = label.length <= 1;
    final scaler = MediaQuery.textScalerOf(context);
    final markSize = scaler.scale(size);
    final fontSize = scaler.scale(
      isCircle ? size * 0.6 : math.max(_minPillFontSize, size * 0.4),
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
            padding: EdgeInsets.symmetric(horizontal: markSize * 0.4),
            child: Center(widthFactor: 1, child: text),
          ),
        ),
      ),
    );
  }
}
