import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show listEquals, precisionErrorTolerance;
import 'package:flutter/rendering.dart';

import '../../../../accessible_design.dart';
import '../../../../core/ui/line_mark.dart';
import '../../../../design_tokens.dart';
import '../../../stations/domain/station_line.dart';
import 'journey_result_view_model.dart';

/// 노선 ID의 대표 색.
Color journeyLineColor(String lineId) =>
    stationLineColor(fallbackLineColorHex(lineId: lineId));

/// 결과 기준 탭(`최단시간`·`최소환승`)과 오른쪽 `막차`. 상용 지하철 서비스처럼
/// 고른 탭은 굵은 글자와 밑줄이고, 탭 줄 아래에 얇은 구분선을 둔다.
class JourneyCriterionTabBar extends StatelessWidget {
  const JourneyCriterionTabBar({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.lastTrainSelected,
    required this.onLastTrain,
    super.key,
  });

  final List<JourneyCriterionTab> tabs;
  final JourneyCriterion? selected;

  /// null이면 탭을 누를 수 없다(알림 전환 중).
  final ValueChanged<JourneyCriterionTab>? onSelect;
  final bool lastTrainSelected;
  final VoidCallback? onLastTrain;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Wrap(
              spacing: EasySubwaySpacing.lg,
              children: [
                for (final tab in tabs)
                  _tab(
                    key: Key('journey-criterion-${tab.criterion.name}'),
                    label: tab.label,
                    selected: tab.criterion == selected,
                    onTap: switch (onSelect) {
                      final select? => () => select(tab),
                      null => null,
                    },
                  ),
              ],
            ),
          ),
          _tab(
            key: const Key('journey-last-train-tab'),
            label: '막차',
            icon: Icons.schedule,
            selected: lastTrainSelected,
            onTap: onLastTrain,
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    IconData? icon,
  }) {
    final color = selected
        ? EasySubwayAccessibleColors.text
        : EasySubwayAccessibleColors.secondaryText;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? EasySubwayAccessibleColors.text
                    : Colors.transparent,
                width: _selectedUnderline,
              ),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: EasySubwayTouchTarget.iconOnly,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EasySubwaySpacing.xs,
              ),
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: color),
                      const SizedBox(width: EasySubwaySpacing.xs),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: selected
                              ? EasySubwayFontWeight.emphasis
                              : EasySubwayFontWeight.regular,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _selectedUnderline = 3.0;
}

/// 요약: 큰 총시간(`2시간 17분`, 숫자만 크게), 그 아래 `오전 5:11 - 오전 7:28 | 2,850원`.
/// 운임이 없으면 운임 칸을 숨긴다.
class JourneyResultSummaryView extends StatelessWidget {
  const JourneyResultSummaryView({
    required this.summary,
    required this.showStairStatus,
    super.key,
  });

  final JourneyResultSummary summary;

  /// false면 계단 없는 경로 표시를 하지 않는다(#441 QA).
  final bool showStairStatus;

  static const _number = TextStyle(
    fontSize: 36,
    height: 1.2,
    fontWeight: EasySubwayFontWeight.emphasis,
    color: EasySubwayAccessibleColors.text,
  );
  static const _unit = TextStyle(
    fontSize: 20,
    fontWeight: EasySubwayFontWeight.regular,
    color: EasySubwayAccessibleColors.text,
  );
  static const _line = TextStyle(
    fontSize: 18,
    color: EasySubwayAccessibleColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final fare = summary.fareLabel;
    final showStairFree = showStairStatus && summary.isStairFree;
    return Column(
      key: const Key('journey-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: [
            summary.semanticsLabel,
            if (showStairFree) journeyStairFreeCategoryLabel,
          ].join(', '),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      for (final (index, (number, unit))
                          in summary.durationParts.indexed) ...[
                        if (index > 0) const TextSpan(text: ' ', style: _unit),
                        TextSpan(text: number, style: _number),
                        TextSpan(text: unit, style: _unit),
                      ],
                    ],
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: EasySubwaySpacing.sm,
                  children: [
                    Text(summary.timesLabel, style: _line),
                    if (fare != null) ...[
                      const SizedBox(
                        height: 16,
                        child: VerticalDivider(
                          width: 1,
                          color: EasySubwayAccessibleColors.line,
                        ),
                      ),
                      Text(fare, style: _line),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        if (showStairFree) ...[
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.statusSuccessSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                journeyStairFreeCategoryLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: EasySubwayFontWeight.emphasis,
                  color: EasySubwayAccessibleColors.mint,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 구간 막대. 탑승 구간은 노선색 막대 안에 흰 노선 원과 `N분`, 막대 위에 출발
/// 시각, 아래에 승차역 이름(노선 글자색)을 둔다. 걷는 구간은 회색 막대다. 폭은
/// 구간 시간 비율이되 어느 구간도 자기 내용의 최소 폭 아래로 줄이지 않는다. 모두
/// 한 줄에 못 들어가면(큰 글자, 환승이 많을 때) 구간을 다음 줄로 넘긴다.
///
/// 막대 묶음은 OpenTripPlanner otp-react-redux `lib/components/narrative/metro/
/// metro-itinerary-routes.tsx`(MIT)처럼 그림은 스크린리더에서 숨기고 경로 전체를
/// 한 라벨로 읽게 하며, 넘치면 줄을 바꾼다(`flex-wrap: wrap`).
class JourneySegmentBar extends StatelessWidget {
  const JourneySegmentBar({
    required this.segments,
    required this.semanticsLabel,
    super.key,
  });

  final List<JourneyResultSegment> segments;
  final String semanticsLabel;

  static const double _walkMinWidth = 6;
  static const double _gap = 2;
  static const double _barHeight = 24;

  static const _minutesStyle = TextStyle(
    fontSize: 13,
    fontWeight: EasySubwayFontWeight.markGlyph,
    color: EasySubwayColorPrimitives.neutralWhite,
  );
  static const _timeStyle = TextStyle(
    fontSize: 15,
    color: EasySubwayAccessibleColors.text,
  );
  static const _stationStyle = TextStyle(
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.emphasis,
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final barHeight = scaler.scale(_barHeight);
    // 걷는 막대를 탑승 막대와 같은 높이에 두려고 출발 시각 줄 높이만큼 내린다.
    final timeLine = (TextPainter(
      text: const TextSpan(text: '00:00', style: _timeStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout());
    final walkTop = timeLine.height;
    timeLine.dispose();
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: _ProportionalWrap(
          key: const Key('journey-segment-bar'),
          weights: [for (final segment in segments) segment.seconds],
          children: [
            for (final segment in segments)
              switch (segment.lineId) {
                final lineId? => _ride(segment, lineId, barHeight),
                null => Padding(
                  padding: EdgeInsets.only(top: walkTop),
                  child: SizedBox(
                    width: _walkMinWidth,
                    height: barHeight,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: EasySubwayAccessibleColors.line,
                      ),
                    ),
                  ),
                ),
              },
          ],
        ),
      ),
    );
  }

  Widget _ride(JourneyResultSegment segment, String lineId, double barHeight) {
    final color = journeyLineColor(lineId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(segment.departureTime!, maxLines: 1, style: _timeStyle),
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(barHeight / 2),
          ),
          child: Row(
            children: [
              LineMark(
                label: segment.lineMarkLabel!,
                color: color,
                size: barHeight,
                maxTextScale: 1,
                onLineColor: true,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EasySubwaySpacing.xs,
                  ),
                  child: Text(
                    segment.minutesLabel,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: _minutesStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          segment.boardingStationName!,
          maxLines: 1,
          softWrap: false,
          style: _stationStyle.copyWith(color: lineInkOnWhite(color)),
        ),
      ],
    );
  }
}

/// 자식을 가로로 놓되 폭은 [weights] 비율로 남는 폭을 나눠 받고, 자식의 최소 고유
/// 폭 아래로 줄이지 않는다. 최소 폭 합이 줄 폭을 넘으면 최소 폭으로 줄을 바꿔 놓는다.
class _ProportionalWrap extends MultiChildRenderObjectWidget {
  const _ProportionalWrap({
    required this.weights,
    required super.children,
    super.key,
  });

  final List<int> weights;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProportionalWrap(weights);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderProportionalWrap renderObject,
  ) {
    renderObject.weights = weights;
  }
}

class _ProportionalWrapParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderProportionalWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ProportionalWrapParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _ProportionalWrapParentData
        > {
  _RenderProportionalWrap(this._weights);

  static const _gap = JourneySegmentBar._gap;
  static const _runGap = EasySubwaySpacing.sm;

  List<int> _weights;

  set weights(List<int> value) {
    if (listEquals(value, _weights)) return;
    _weights = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ProportionalWrapParentData) {
      child.parentData = _ProportionalWrapParentData();
    }
  }

  List<RenderBox> get _children {
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    return children;
  }

  @override
  void performLayout() {
    final children = _children;
    final maxWidth = constraints.maxWidth;
    final minimums = [
      for (final child in children)
        math.min(maxWidth, child.getMinIntrinsicWidth(double.infinity)),
    ];
    final needed =
        minimums.fold<double>(0, (sum, width) => sum + width) +
        _gap * math.max(0, children.length - 1);
    final fits = needed <= maxWidth;
    final totalWeight = math.max(
      1,
      _weights.fold<int>(0, (sum, weight) => sum + weight),
    );
    final spare = fits ? maxWidth - needed : 0.0;
    var x = 0.0;
    var y = 0.0;
    var runHeight = 0.0;
    var width = 0.0;
    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      final childWidth =
          minimums[index] + spare * _weights[index] / totalWeight;
      if (x > 0 && x + childWidth > maxWidth + precisionErrorTolerance) {
        x = 0;
        y += runHeight + _runGap;
        runHeight = 0;
      }
      child.layout(
        BoxConstraints.tightFor(width: childWidth),
        parentUsesSize: true,
      );
      (child.parentData! as _ProportionalWrapParentData).offset = Offset(x, y);
      x += childWidth + _gap;
      width = math.max(width, x - _gap);
      runHeight = math.max(runHeight, child.size.height);
    }
    size = constraints.constrain(Size(fits ? maxWidth : width, y + runHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// `오전 12:36 기준 (출발 대기 4시간 35분)` 줄. 위아래 구분선으로 요약과 상세를 나눈다.
class JourneyBasisRow extends StatelessWidget {
  const JourneyBasisRow({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, color: EasySubwayAccessibleColors.line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: EasySubwaySpacing.md),
          child: Text(
            label,
            key: const Key('journey-basis-row'),
            style: const TextStyle(
              fontSize: 16,
              color: EasySubwayAccessibleColors.secondaryText,
            ),
          ),
        ),
        const Divider(height: 1, color: EasySubwayAccessibleColors.line),
      ],
    );
  }
}

/// 경로 후보 위의 계단 상태 안내(#441). 안내마다 한 덩어리로 읽힌다.
class JourneyStairStatusNotices extends StatelessWidget {
  const JourneyStairStatusNotices({required this.notices, super.key});

  final List<JourneyStairStatusNotice> notices;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < notices.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _notice(notices[index]),
        ],
      ],
    );
  }

  Widget _notice(JourneyStairStatusNotice notice) {
    const content = EasySubwayAccessibleColors.statusWarningContent;
    return Semantics(
      container: true,
      label: notice.semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          key: Key('journey-stair-status-${notice.kind.name}'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.statusWarningSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: EasySubwayFontWeight.emphasis,
                  color: content,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                notice.body,
                style: const TextStyle(
                  fontSize: 13,
                  color: EasySubwayAccessibleColors.contentSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 계단 없는 경로만 요청했는데 그런 경로가 없을 때(422
/// `ACCESSIBILITY_CONSTRAINT_UNSATISFIED`) 사실과 다음 행동을 보여 준다(#441).
class JourneyStepFreeUnavailablePanel extends StatelessWidget {
  const JourneyStepFreeUnavailablePanel({
    required this.copy,
    required this.onShowStandardRoutes,
    required this.onReselectStations,
    super.key,
  });

  final JourneyFailureCopy copy;

  /// null이면 누를 수 없다(알림 전환 중).
  final VoidCallback? onShowStandardRoutes;
  final VoidCallback onReselectStations;

  @override
  Widget build(BuildContext context) {
    final detail = copy.detail;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: [copy.message, ?detail].join(' '),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.message,
                  key: const Key('journey-failure-message'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: EasySubwayFontWeight.emphasis,
                    color: EasySubwayAccessibleColors.text,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    key: const Key('journey-failure-detail'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: EasySubwayAccessibleColors.contentSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('journey-show-standard-routes-button'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: EasySubwayAccessibleColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onShowStandardRoutes,
          child: const Text('일반 경로 보기'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('journey-failure-action-button'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onReselectStations,
          child: const Text('출발·도착역 다시 선택'),
        ),
      ],
    );
  }
}

/// 환승 노드 아래의 이동 안내 단계(#451). 단계 문장은 원천 문장 그대로이고,
/// 토글에는 단계 수만 적는다. 단계가 없으면 아무것도 그리지 않는다.
class JourneyTransferGuideSteps extends StatelessWidget {
  const JourneyTransferGuideSteps({
    required this.legIndex,
    required this.steps,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final int legIndex;
  final List<String> steps;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final label = '이동 방법 ${steps.length}단계';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: label,
          onTap: onToggle,
          excludeSemantics: true,
          child: InkWell(
            key: Key('journey-transfer-guide-toggle-$legIndex'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: EasySubwayFontWeight.regular,
                        color: EasySubwayAccessibleColors.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Column(
            key: Key('journey-transfer-guide-steps-$legIndex'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    step,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
