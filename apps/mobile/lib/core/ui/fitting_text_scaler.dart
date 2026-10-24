import 'package:flutter/widgets.dart';

/// 글자 폭은 배율에 정확히 비례하지 않아(자간·반올림) 약간 여유를 둔다.
const _fitMargin = 0.97;

/// [text]가 [maxWidth] 한 줄에 들어가도록 시스템 글자 배율을 낮춘 배율. 시스템
/// 배율로 들어가면 그대로 두고, 기본 크기(1.0) 아래로는 내리지 않는다. 그래도 넘치면
/// 줄을 바꾸게 둔다. 한글 이름이 단어 중간에서 끊기는 것을 큰 글자 설정을 지키는
/// 범위에서만 막는다.
TextScaler fittingTextScaler(
  BuildContext context, {
  required String text,
  required TextStyle style,
  required double maxWidth,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final fontSize = style.fontSize!;
  final scale = scaler.scale(fontSize) / fontSize;
  if (scale <= 1 || !maxWidth.isFinite) {
    return scaler;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final scaledWidth = painter.width;
  painter.dispose();
  if (scaledWidth <= maxWidth) {
    return scaler;
  }
  final fitting = scale * maxWidth / scaledWidth * _fitMargin;
  return scaler.clamp(maxScaleFactor: fitting < 1 ? 1 : fitting);
}
