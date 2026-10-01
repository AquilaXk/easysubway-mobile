import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../accessible_design.dart';
import '../../../stations/domain/station_line.dart';
import 'journey_result_view_model.dart';

/// 노선 ID의 대표 색.
Color journeyLineColor(String lineId) =>
    stationLineColor(fallbackLineColorHex(lineId: lineId));

/// 후보 경로를 서버 순서대로 보여 주는 가로 탭.
class JourneyRouteTabs extends StatelessWidget {
  const JourneyRouteTabs({
    required this.tabs,
    required this.selectedJourneyId,
    required this.onSelect,
    super.key,
  });

  final List<JourneyRouteTab> tabs;
  final String? selectedJourneyId;

  /// null이면 탭을 누를 수 없다(알림 전환 중).
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            _tab(tabs[index]),
          ],
        ],
      ),
    );
  }

  Widget _tab(JourneyRouteTab tab) {
    final selected = tab.journeyId == selectedJourneyId;
    final select = onSelect;
    final onTap = select == null ? null : () => select(tab.journeyId);
    final foreground = selected
        ? EasySubwayAccessibleColors.onPrimary
        : EasySubwayAccessibleColors.text;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: Key('journey-candidate-${tab.journeyId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          key: selected ? Key('selected-journey-${tab.journeyId}') : null,
          constraints: const BoxConstraints(minWidth: 96, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? EasySubwayAccessibleColors.primary
                : EasySubwayAccessibleColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < tab.labels.length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Text(
                      tab.labels[index],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? EasySubwayAccessibleColors.onPrimary
                            : (tab.labels[index] == '무단차'
                                  ? EasySubwayAccessibleColors.mint
                                  : EasySubwayAccessibleColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                tab.durationLabel,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              Text(
                tab.transferLabel,
                style: TextStyle(fontSize: 12, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 요약: 소요시간(크게), 출발·도착 시각, 환승·운임·도보.
class JourneyResultSummaryView extends StatelessWidget {
  const JourneyResultSummaryView({required this.summary, super.key});

  final JourneyResultSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: summary.semanticsLabel,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.durationLabel,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.text,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      summary.timesLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: EasySubwayAccessibleColors.text,
                      ),
                    ),
                    if (summary.isRealtime)
                      const Text(
                        '실시간 반영',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: EasySubwayAccessibleColors.statusInfoContent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summary.detailLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (summary.isStairFree) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.statusSuccessSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '♿ 무단차 경로',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EasySubwayAccessibleColors.mint,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 전체 이동을 구간별 가로 막대 한 줄로 보여 준다. 폭은 구간 시간 비율이다.
class JourneySegmentBar extends StatelessWidget {
  const JourneySegmentBar({
    required this.segments,
    required this.semanticsLabel,
    super.key,
  });

  final List<JourneyResultSegment> segments;
  final String semanticsLabel;

  static const double _minSegmentWidth = 6;
  static const double _minLabelWidth = 36;
  static const double _gap = 2;

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: EasySubwayColorPrimitives.neutralWhite,
  );

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = segments.length;
            // 모든 구간이 0초여도 나눗셈이 되도록 분모를 1 이상으로 둔다.
            final totalSeconds = math.max(
              1,
              segments.fold<int>(0, (sum, segment) => sum + segment.seconds),
            );
            final flexibleWidth = math.max(
              0.0,
              constraints.maxWidth -
                  _gap * (count - 1) -
                  _minSegmentWidth * count,
            );
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < count; index++) ...[
                    if (index > 0) const SizedBox(width: _gap),
                    _segment(
                      segments[index],
                      width:
                          _minSegmentWidth +
                          flexibleWidth *
                              segments[index].seconds /
                              totalSeconds,
                      textScaler: textScaler,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _segment(
    JourneyResultSegment segment, {
    required double width,
    required TextScaler textScaler,
  }) {
    final label = segment.minutesLabel;
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final showLabel = width >= _minLabelWidth && painter.width + 8 <= width;
    painter.dispose();
    final lineId = segment.lineId;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lineId == null
            ? EasySubwayAccessibleColors.mutedText
            : journeyLineColor(lineId),
        borderRadius: BorderRadius.circular(4),
      ),
      child: showLabel
          ? Text(label, maxLines: 1, softWrap: false, style: _labelStyle)
          : null,
    );
  }
}
