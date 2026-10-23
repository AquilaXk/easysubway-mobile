import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/ui/line_mark.dart';
import '../domain/station_line.dart';

class StationLineBadges extends StatelessWidget {
  const StationLineBadges({
    required this.lines,
    this.size = 40,
    this.maxBadgeCount,
    this.runSpacing = 8,
    this.maxTextScale,
    super.key,
  });

  final List<StationSearchLine> lines;
  final double size;
  final int? maxBadgeCount;
  final double runSpacing;
  final double? maxTextScale;

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
      runSpacing: runSpacing,
      children: [
        for (final line in lines.take(visibleLineCount))
          StationLineBadge(line: line, size: size, maxTextScale: maxTextScale),
        if (hiddenLineCount > 0)
          _StationLineOverflowBadge(
            count: hiddenLineCount,
            size: size,
            maxTextScale: maxTextScale,
          ),
      ],
    );
  }
}

class StationLineBadge extends StatelessWidget {
  const StationLineBadge({
    required this.line,
    this.size = 40,
    this.maxTextScale,
    super.key,
  });

  final StationSearchLine line;
  final double size;
  final double? maxTextScale;

  @override
  Widget build(BuildContext context) {
    final badgeText = line.badgeText;
    final assetPath = line.badgeAssetPath;

    if (isLineMarkCircle(badgeText) && assetPath != null) {
      final markSize = scaledLineMarkSize(
        context,
        size,
        maxTextScale: maxTextScale,
      );
      final cachePx = (markSize * MediaQuery.devicePixelRatioOf(context))
          .round();
      final image = Image.asset(
        assetPath,
        width: markSize,
        height: markSize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
      );
      return SizedBox(
        key: Key('stationLineBadge-${line.id}'),
        width: markSize,
        height: markSize,
        child: stationLineBadgeNeedsRoundedCorners(assetPath)
            ? ClipRRect(
                borderRadius: BorderRadius.all(
                  Radius.circular(markSize * 0.16),
                ),
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
      maxTextScale: maxTextScale,
    );
  }
}

/// 호선 선택 탭. [StationLineBadge]와 동일 마크에 선택 밑줄만 얹는다. 탭 줄 높이가
/// 48로 정해져 있어 마크는 [lineMarkFixedChromeMaxTextScale]에서 멈춘다.
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
    final isSingleChar = isLineMarkCircle(line.badgeText);

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
                    child: StationLineBadge(
                      line: line,
                      size: size,
                      maxTextScale: lineMarkFixedChromeMaxTextScale,
                    ),
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
  const _StationLineOverflowBadge({
    required this.count,
    required this.size,
    required this.maxTextScale,
  });

  final int count;
  final double size;
  final double? maxTextScale;

  @override
  Widget build(BuildContext context) {
    final markSize = scaledLineMarkSize(
      context,
      size,
      maxTextScale: maxTextScale,
    );
    return Container(
      key: const Key('stationLineBadgeOverflow'),
      width: markSize,
      height: markSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.scaffoldSurface,
        shape: BoxShape.circle,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Text(
        '+$count',
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontSize: 13 * (markSize / 32),
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
