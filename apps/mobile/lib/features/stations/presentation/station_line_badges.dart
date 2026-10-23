import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../domain/station_line.dart';

class StationLineBadges extends StatelessWidget {
  const StationLineBadges({
    required this.lines,
    this.size = 40,
    this.maxBadgeCount,
    super.key,
  });

  final List<StationSearchLine> lines;
  final double size;
  final int? maxBadgeCount;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = maxBadgeCount;
    final shouldCollapse = maxCount != null && lines.length > maxCount;
    final visibleLineCount = shouldCollapse
        ? (maxCount - 1).clamp(1, lines.length).toInt()
        : lines.length;
    final hiddenLineCount = lines.length - visibleLineCount;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final line in lines.take(visibleLineCount))
          StationLineBadge(line: line, size: size),
        if (hiddenLineCount > 0)
          _StationLineOverflowBadge(count: hiddenLineCount, size: size),
      ],
    );
  }
}

class StationLineBadge extends StatelessWidget {
  const StationLineBadge({required this.line, this.size = 40, super.key});

  final StationSearchLine line;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeText = line.badgeText;
    final isSingleChar = badgeText.length <= 1;
    final assetPath = line.badgeAssetPath;

    if (isSingleChar && assetPath != null) {
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
      final image = Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
      );
      return SizedBox(
        key: Key('stationLineBadge-${line.id}'),
        width: size,
        height: size,
        child: stationLineBadgeNeedsRoundedCorners(assetPath)
            ? ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(size * 0.16)),
                child: image,
              )
            : image,
      );
    }

    return LineMark(
      key: Key('stationLineBadge-${line.id}'),
      label: badgeText,
      color: line.badgeColor,
      size: size,
    );
  }
}

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
    final fontSize = isCircle
        ? size * 0.6
        : math.max(_minPillFontSize, size * 0.4);
    return Container(
      width: isCircle ? size : null,
      height: size,
      constraints: BoxConstraints(minWidth: size),
      alignment: Alignment.center,
      padding: isCircle ? null : EdgeInsets.symmetric(horizontal: size * 0.4),
      decoration: BoxDecoration(
        color: color,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(size / 2),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        style: TextStyle(
          color: EasySubwayAccessibleColors.interactionOnPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 호선 선택 탭. [StationLineBadge]와 동일 마크에 선택 밑줄만 얹는다.
class StationLineBadgeTab extends StatelessWidget {
  const StationLineBadgeTab({
    required this.line,
    required this.selected,
    required this.onTap,
    this.size = 32,
    super.key,
  });

  final StationSearchLine line;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isSingleChar = line.badgeText.length <= 1;

    return Semantics(
      button: true,
      selected: selected,
      label: '${line.name} 선택',
      child: InkWell(
        key: Key('stationLineBadgeTab-${line.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 48,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isSingleChar ? 4 : 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: StationLineBadge(line: line, size: size),
                  ),
                  Positioned(
                    bottom: 2,
                    child: Container(
                      width: isSingleChar ? 30 : 42,
                      height: 2,
                      decoration: BoxDecoration(
                        color: selected
                            ? EasySubwayAccessibleColors.interactionPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StationLineOverflowBadge extends StatelessWidget {
  const _StationLineOverflowBadge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stationLineBadgeOverflow'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.scaffoldSurface,
        shape: BoxShape.circle,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Text(
        '+$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontSize: 13 * (size / 32),
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
