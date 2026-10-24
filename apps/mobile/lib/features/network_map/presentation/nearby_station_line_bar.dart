import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/ui/line_mark.dart';

/// 주변역 패널의 이전-현재-다음역 노선 표시 바 (오너 스펙 2026-07-16, #2200).
///
/// 좌우 바는 선택 노선색 단일 소스([lineColor])를 동일하게 쓰고(2호선이면 양쪽
/// 모두 #00A84D), 바깥 끝만 반원이다. 노선 바를 하나의 연속 바로 먼저 그린 뒤
/// 흰 캡슐을 Stack으로 겹쳐, 캡슐 뒤에서 노선이 끊겨 보이지 않게 한다. 크기는
/// LayoutBuilder로 패널 너비 비율에 맞춘다.
class NearbyStationLineBar extends StatelessWidget {
  const NearbyStationLineBar({
    required this.leftName,
    required this.rightName,
    required this.stationName,
    required this.badgeText,
    required this.lineColor,
    this.badgeBuilder,
    this.line,
    this.onStationNameTap,
    this.onLeftNameTap,
    this.onRightNameTap,
    super.key,
  });

  final String? leftName;
  final String? rightName;
  final String stationName;
  final String badgeText;
  final Color lineColor;
  final Widget Function(double diameter)? badgeBuilder;
  final Object? line;

  /// 현재 역 이름 탭 → 역 상세. null이면 이름만 표시한다.
  final VoidCallback? onStationNameTap;

  /// 이전(왼쪽) 역 탭. null이면 표시만 한다.
  final VoidCallback? onLeftNameTap;

  /// 다음(오른쪽) 역 탭. null이면 표시만 한다.
  final VoidCallback? onRightNameTap;

  @override
  Widget build(BuildContext context) {
    final openDetail = onStationNameTap;
    final hasNeighborActions = onLeftNameTap != null || onRightNameTap != null;
    // 좌·우 이웃 탭이 있으면 자식 Semantics가 담당한다. 없으면 기존처럼
    // 바 전체를 상세 보기 버튼으로 묶는다.
    if (hasNeighborActions) {
      return Semantics(
        container: true,
        label: _semanticsLabel(),
        child: _buildBar(excludeChildSemantics: false),
      );
    }
    return Semantics(
      container: true,
      label: openDetail == null
          ? _semanticsLabel()
          : '${_semanticsLabel()}, 상세 보기',
      button: openDetail != null,
      onTap: openDetail,
      child: ExcludeSemantics(child: _buildBar(excludeChildSemantics: true)),
    );
  }

  String _semanticsLabel() {
    final parts = <String>[];
    final left = leftName;
    if (left != null && left.isNotEmpty) {
      parts.add('이전역 $left');
    }
    parts.add(
      badgeText.isEmpty ? '현재역 $stationName' : '현재역 $badgeText $stationName',
    );
    final right = rightName;
    if (right != null && right.isNotEmpty) {
      parts.add('다음역 $right');
    }
    return parts.join(', ');
  }

  Widget _buildBar({required bool excludeChildSemantics}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth;
        final margin = fullWidth * 0.03476;
        final barWidth = fullWidth - margin * 2;
        final barHeight = barWidth * 28 / 348;
        final nameLen = stationName.length;
        final centerWidthRatio = nameLen >= 7
            ? 0.48
            : (nameLen >= 5 ? 0.43 : 0.37069);
        final centerWidth = barWidth * centerWidthRatio;
        final endRadius = barHeight / 2;
        final capsuleWidth = centerWidth;
        final baseCenterWidth = barWidth * 0.37069;
        final capsuleHeight = baseCenterWidth * 41 / 129;
        final hitHeight = capsuleHeight < 48.0 ? 48.0 : capsuleHeight;
        final badgeDiameter = (capsuleHeight * 0.62).clamp(24.0, 28.0);
        // 알약 마크는 같은 높이 원보다 훨씬 넓어 캡슐 안 이름 자리를 먹는다.
        // 이름이 줄어들지 않게 알약만 더 낮게 그린다.
        final badgeSize = isLineMarkCircle(badgeText)
            ? badgeDiameter
            : math.min(badgeDiameter, lineMarkDefaultSize);
        final stationNameSize = (capsuleHeight * 0.42).clamp(16.0, 20.0);
        final openDetail = onStationNameTap;
        final currentLabel = badgeText.isEmpty
            ? '현재역 $stationName'
            : '현재역 $badgeText $stationName';
        final bar = Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Center(
            child: SizedBox(
              width: barWidth,
              height: hitHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    key: const Key('nearbyStationLineBarTrack'),
                    width: barWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.all(
                        Radius.circular(endRadius),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: barWidth,
                    height: hitHeight,
                    child: Row(
                      children: [
                        Expanded(
                          child: _SideName(
                            name: leftName,
                            semanticsPrefix: '이전역',
                            onTap: onLeftNameTap,
                          ),
                        ),
                        SizedBox(width: centerWidth),
                        Expanded(
                          child: _SideName(
                            name: rightName,
                            semanticsPrefix: '다음역',
                            onTap: onRightNameTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: openDetail != null,
                    label: openDetail == null
                        ? currentLabel
                        : '$currentLabel, 상세 보기',
                    onTap: openDetail,
                    excludeSemantics: openDetail != null,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: openDetail,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: (hitHeight - capsuleHeight) / 2,
                        ),
                        child: Container(
                          key: const Key('nearbyStationLineBarCapsule'),
                          constraints: BoxConstraints(
                            minWidth: capsuleWidth,
                            maxWidth: barWidth * 0.55,
                          ),
                          height: capsuleHeight,
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(
                            horizontal: (capsuleWidth * 0.08).clamp(8.0, 14.0),
                          ),
                          decoration: BoxDecoration(
                            color: EasySubwayAccessibleColors.surfaceDefault,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: lineColor, width: 3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (badgeText.isNotEmpty ||
                                  badgeBuilder != null) ...[
                                badgeBuilder?.call(badgeSize) ??
                                    LineMark(
                                      key: const Key(
                                        'nearbyStationLineBarBadge',
                                      ),
                                      label: badgeText,
                                      color: lineColor,
                                      size: badgeSize,
                                      maxTextScale:
                                          lineMarkFixedChromeMaxTextScale,
                                    ),
                                const SizedBox(width: 7),
                              ],
                              Flexible(
                                child: _StationNameLabel(
                                  stationName: stationName,
                                  fontSize: stationNameSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return excludeChildSemantics ? ExcludeSemantics(child: bar) : bar;
      },
    );
  }
}

class _StationNameLabel extends StatelessWidget {
  const _StationNameLabel({required this.stationName, required this.fontSize});

  final String stationName;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        stationName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: EasySubwayAccessibleColors.contentPrimary,
          fontSize: fontSize,
          fontWeight: EasySubwayFontWeight.emphasis,
          height: 1.1,
        ),
      ),
    );
    return KeyedSubtree(
      key: const Key('nearbyStationLineBarStationName'),
      child: text,
    );
  }
}

/// 노선색 바 위 이웃역 이름. 흰 글자와 노선색의 대비가 3:1~4.5:1인 노선이 많아
/// 큰 글자 기준(14pt 이상 굵게, 3:1)을 받도록 크기를 14pt로 고정한다(에픽 7-48).
/// 글자 배율 때문에 자리를 넘칠 때만 배율을 14pt까지 낮춰 이름을 끝까지 보인다.
class _SideName extends StatelessWidget {
  const _SideName({
    required this.name,
    required this.semanticsPrefix,
    this.onTap,
  });

  static const _style = TextStyle(
    color: EasySubwayAccessibleColors.interactionOnPrimary,
    fontSize: 14,
    fontWeight: EasySubwayFontWeight.boldForContrast,
  );

  final String? name;
  final String semanticsPrefix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = name;
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }
    final isLeft = semanticsPrefix == '이전역';
    final chevron = Icon(
      isLeft ? Icons.chevron_left : Icons.chevron_right,
      size: 16,
      color: EasySubwayAccessibleColors.interactionOnPrimary,
    );
    final label = Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isLeft ? TextAlign.left : TextAlign.right,
          textScaler: _fittingScaler(context, value, constraints.maxWidth),
          style: _style,
        ),
      ),
    );
    final content = Row(
      children: isLeft
          ? [
              const SizedBox(width: 6),
              chevron,
              const SizedBox(width: 4),
              label,
              const SizedBox(width: 2),
            ]
          : [
              const SizedBox(width: 2),
              label,
              const SizedBox(width: 4),
              chevron,
              const SizedBox(width: 6),
            ],
    );

    final tap = onTap;
    if (tap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: content,
      );
    }
    return Semantics(
      button: true,
      label: '$semanticsPrefix $value',
      child: InkWell(
        key: Key(
          isLeft
              ? 'nearbyStationLineBarLeftName'
              : 'nearbyStationLineBarRightName',
        ),
        onTap: tap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: content,
          ),
        ),
      ),
    );
  }

  /// 기기 글자 배율을 따르되, 이름이 [maxWidth]를 넘으면 배율을 맞는 만큼 낮춘다.
  /// 14pt 아래로는 내리지 않고 그때는 말줄임표로 자른다.
  static TextScaler _fittingScaler(
    BuildContext context,
    String value,
    double maxWidth,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final scale = scaler.scale(_style.fontSize!) / _style.fontSize!;
    if (scale <= 1 || !maxWidth.isFinite) {
      return scaler;
    }
    final painter = TextPainter(
      text: TextSpan(text: value, style: _style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final scaledWidth = painter.width;
    painter.dispose();
    if (scaledWidth <= maxWidth) {
      return scaler;
    }
    // 글자 폭은 배율에 정확히 비례하지 않아(자간·반올림) 약간 여유를 둔다.
    final fitting = scale * maxWidth / scaledWidth * _fitMargin;
    return scaler.clamp(maxScaleFactor: fitting < 1 ? 1 : fitting);
  }

  static const _fitMargin = 0.97;
}
