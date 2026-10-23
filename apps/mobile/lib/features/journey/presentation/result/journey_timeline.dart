import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../accessible_design.dart';
import '../../../../core/ui/line_mark.dart';
import '../../../../design_tokens.dart';
import 'journey_result_view_model.dart';
import 'journey_result_widgets.dart';

/// 경로 상세의 세로 타임라인. 행마다 왼쪽 선 칸과 오른쪽 내용 칸을 둔다. 선 칸은
/// 탑승 구간이 노선색 굵은 선, 걷는 구간이 회색 점선이고, 승차·하차 단계에는
/// 열차·도보 아이콘 원과 시각 칩을 얹는다.
///
/// 행 구조는 OpenTripPlanner otp-ui `packages/itinerary-body/src/ItineraryBody/
/// place-row.tsx`(MIT)의 LineColumn·PlaceHeader·PlaceDetails 배치와, 같은 저장소
/// `TransitLegBody/index.tsx`·`intermediate-stops.tsx`의 "N개 역 이동" 펼침 행과
/// 정차역 점 목록을 따른다. 값은 서버 경로 응답에서 온 [JourneyTimelineNode]만 쓴다.
class JourneyTimeline extends StatelessWidget {
  const JourneyTimeline({
    required this.nodes,
    required this.isRideExpanded,
    required this.onToggleRide,
    required this.boardingExtras,
    required this.alightingExtras,
    required this.transferExtras,
    this.onOpenStation,
    this.onOpenStationTimetable,
    super.key,
  });

  final List<JourneyTimelineNode> nodes;
  final bool Function(int legIndex) isRideExpanded;
  final ValueChanged<int> onToggleRide;

  /// 승차·하차 단계 아래에 붙는 안내(계단 없는 이동의 승강장 틈 등).
  final Widget Function(JourneyRideNode node) boardingExtras;
  final Widget Function(JourneyRideNode node) alightingExtras;

  /// 환승 줄 아래에 붙는 안내(역 밖 환승 배지, 재승차, 환승 이동 안내).
  final Widget Function(JourneyTransferNode node) transferExtras;

  /// 역 이름 `>`와 실시간 칩이 여는 기존 역 화면. null이면 링크를 그리지 않는다.
  final ValueChanged<String>? onOpenStation;

  /// 시간표 칩이 여는 기존 역 시간표 화면. null이면 칩을 그리지 않는다.
  final ValueChanged<String>? onOpenStationTimetable;

  @override
  Widget build(BuildContext context) {
    final railWidth = _railWidth(MediaQuery.textScalerOf(context));
    final rows = <Widget>[];
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final previous = index > 0 ? nodes[index - 1] : null;
      final next = index + 1 < nodes.length ? nodes[index + 1] : null;
      rows.add(
        KeyedSubtree(
          key: Key('selected-journey-leg-${node.legIndex}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (node) {
              JourneyRideNode() => _rideRows(
                node,
                railWidth: railWidth,
                arrivesFromWalk:
                    previous != null && previous is! JourneyRideNode,
                leavesOnWalk: next != null && next is! JourneyRideNode,
                isFirst: index == 0,
              ),
              JourneyTransferNode() => [
                _row(
                  railWidth: railWidth,
                  rail: const _RailSpec.walk(),
                  showDivider: true,
                  content: _transferContent(node),
                ),
              ],
              JourneyDepartureNode(:final walkLabel, :final semanticsLabel) ||
              JourneyArrivalNode(:final walkLabel, :final semanticsLabel) => [
                _row(
                  railWidth: railWidth,
                  rail: const _RailSpec.walk(),
                  showDivider: index > 0,
                  content: Semantics(
                    label: semanticsLabel,
                    child: ExcludeSemantics(
                      child: Text(walkLabel, style: _secondaryStyle),
                    ),
                  ),
                ),
              ],
            },
          ),
        ),
      );
    }
    return Column(
      key: const Key('journey-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  List<Widget> _rideRows(
    JourneyRideNode node, {
    required double railWidth,
    required bool arrivesFromWalk,
    required bool leavesOnWalk,
    required bool isFirst,
  }) {
    final lineColor = journeyLineColor(node.lineId);
    final ride = _Track.solid(lineColor);
    final expanded = isRideExpanded(node.legIndex);
    return [
      _row(
        railWidth: railWidth,
        rail: _RailSpec(
          above: arrivesFromWalk ? const _Track.walk() : null,
          below: ride,
          marker: _StepMarker(
            icon: Icons.directions_subway_outlined,
            color: lineColor,
            time: node.departureTime,
          ),
        ),
        showDivider: !isFirst,
        content: _boardingContent(node, lineColor),
      ),
      _row(
        railWidth: railWidth,
        rail: _RailSpec(above: ride, below: ride),
        showDivider: true,
        content: _stopsToggle(node, expanded),
      ),
      if (expanded)
        for (final stop in node.intermediateStops)
          _row(
            railWidth: railWidth,
            rail: _RailSpec(above: ride, below: ride, stopDot: true),
            contentPadding: EasySubwaySpacing.xs,
            content: _stopContent(stop),
          ),
      _row(
        railWidth: railWidth,
        rail: _RailSpec(
          above: ride,
          below: leavesOnWalk ? const _Track.walk() : null,
          marker: _StepMarker(
            icon: Icons.directions_walk,
            color: EasySubwayAccessibleColors.mutedText,
            time: node.arrivalTime,
          ),
        ),
        showDivider: true,
        content: _alightingContent(node),
      ),
    ];
  }

  Widget _boardingContent(JourneyRideNode node, Color lineColor) {
    final chips = <Widget>[
      if (onOpenStation case final open?)
        _StationChip(
          key: Key('journey-ride-realtime-${node.legIndex}'),
          label: '실시간',
          semanticsLabel: '${node.boardingHeading} 실시간 도착 정보',
          onPressed: () => open(node.boardingStationId),
        ),
      if (onOpenStationTimetable case final open?)
        _StationChip(
          key: Key('journey-ride-timetable-${node.legIndex}'),
          label: '시간표',
          semanticsLabel: '${node.boardingHeading} 시간표',
          onPressed: () => open(node.boardingStationId),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StationHeading(
          key: Key('journey-ride-heading-${node.legIndex}'),
          lineName: node.lineName,
          lineInk: lineInkOnWhite(lineColor),
          stationHeading: node.boardingHeading,
          semanticsLabel: '${node.lineName} ${node.boardingHeading}',
          onTap: _openStation(node.boardingStationId),
        ),
        const SizedBox(height: EasySubwaySpacing.sm),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: EasySubwaySpacing.sm,
          runSpacing: EasySubwaySpacing.sm,
          children: [
            Semantics(
              label: node.semanticsLabel,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (node.directionLabel case final direction?)
                      Text(direction, style: _bodyStyle),
                    if (node.isExpress) const Text('급행', style: _expressStyle),
                    for (final line in node.carDoorLines)
                      Text(line, style: _bodyStyle),
                  ],
                ),
              ),
            ),
            if (chips.isNotEmpty)
              Wrap(
                spacing: EasySubwaySpacing.sm,
                runSpacing: EasySubwaySpacing.xs,
                children: chips,
              ),
          ],
        ),
        boardingExtras(node),
        const SizedBox(height: EasySubwaySpacing.md),
        _TrainCard(node: node),
      ],
    );
  }

  Widget _stopsToggle(JourneyRideNode node, bool expanded) {
    final label = Text(node.stopToggleLabel, style: _secondaryStyle);
    if (node.intermediateStops.isEmpty) {
      return ExcludeSemantics(child: label);
    }
    void toggle() => onToggleRide(node.legIndex);
    return Semantics(
      button: true,
      expanded: expanded,
      label: node.stopToggleLabel,
      onTap: toggle,
      excludeSemantics: true,
      child: InkWell(
        key: Key('journey-ride-stops-toggle-${node.legIndex}'),
        onTap: toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: EasySubwayTouchTarget.iconOnly,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: EasySubwayAccessibleColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stopContent(JourneyIntermediateStop stop) {
    return MergeSemantics(
      child: Wrap(
        spacing: EasySubwaySpacing.md,
        children: [
          if (stop.time case final time?) Text(time, style: _secondaryStyle),
          Text(stop.heading, style: _bodyStyle),
        ],
      ),
    );
  }

  Widget _alightingContent(JourneyRideNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StationHeading(
          key: Key('journey-alight-heading-${node.legIndex}'),
          stationHeading: node.alightingHeading,
          semanticsLabel: '${node.alightingHeading} 하차, ${node.arrivalTime} 도착',
          onTap: _openStation(node.alightingStationId),
        ),
        alightingExtras(node),
      ],
    );
  }

  Widget _transferContent(JourneyTransferNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: node.semanticsLabel,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.walkLabel, style: _secondaryStyle),
                if (node.waitLabel case final wait?)
                  Text(wait, style: _secondaryStyle),
              ],
            ),
          ),
        ),
        transferExtras(node),
      ],
    );
  }

  VoidCallback? _openStation(String stationId) => switch (onOpenStation) {
    final open? => () => open(stationId),
    null => null,
  };

  Widget _row({
    required double railWidth,
    required _RailSpec rail,
    required Widget content,
    bool showDivider = false,
    double contentPadding = EasySubwaySpacing.md,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: ExcludeSemantics(child: _Rail(spec: rail)),
          ),
          const SizedBox(width: EasySubwaySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDivider)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: EasySubwayAccessibleColors.line,
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: contentPadding),
                  child: content,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _railWidth(TextScaler scaler) {
    final painter = TextPainter(
      text: const TextSpan(text: '00:00', style: _chipStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width + _chipHorizontalPadding * 2 + 2;
    painter.dispose();
    return math.max(_minRailWidth, width);
  }
}

const _minRailWidth = 52.0;
const _chipHorizontalPadding = 6.0;
const _markerDiameter = 30.0;
const _rideTrackWidth = 8.0;
const _walkDotRadius = 3.0;
const _walkDotGap = 10.0;
const _stopDotRadius = 4.0;

const _bodyStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  color: EasySubwayAccessibleColors.text,
);
const _secondaryStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  color: EasySubwayAccessibleColors.secondaryText,
);
const _expressStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  fontWeight: EasySubwayFontWeight.emphasis,
  color: EasySubwayAccessibleColors.statusDangerContent,
);
const _chipStyle = TextStyle(
  fontSize: 13,
  color: EasySubwayAccessibleColors.text,
);

/// 승차·하차 단계 제목(`1호선 소요산역 >`, `창동역 >`). [onTap]이 있으면 역 정보를
/// 여는 버튼이고 `>`를 붙인다.
class _StationHeading extends StatelessWidget {
  const _StationHeading({
    required this.stationHeading,
    required this.semanticsLabel,
    required this.onTap,
    this.lineName,
    this.lineInk,
    super.key,
  });

  final String? lineName;
  final Color? lineInk;
  final String stationHeading;
  final String semanticsLabel;
  final VoidCallback? onTap;

  static const _style = TextStyle(
    fontSize: 19,
    fontWeight: EasySubwayFontWeight.emphasis,
    color: EasySubwayAccessibleColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      TextSpan(
        children: [
          if (lineName case final name?)
            TextSpan(
              text: '$name ',
              style: _style.copyWith(color: lineInk),
            ),
          TextSpan(text: stationHeading),
        ],
      ),
      style: _style,
    );
    final tap = onTap;
    return Semantics(
      button: tap != null,
      header: true,
      label: tap == null ? semanticsLabel : '$semanticsLabel, 역 정보 보기',
      onTap: tap,
      excludeSemantics: true,
      child: tap == null
          ? text
          : InkWell(
              onTap: tap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: EasySubwayTouchTarget.iconOnly,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: text),
                    const Icon(
                      Icons.chevron_right,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 승차 단계 오른쪽의 `실시간`·`시간표` 칩.
class _StationChip extends StatelessWidget {
  const _StationChip({
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            EasySubwayTouchTarget.iconOnly,
            EasySubwayTouchTarget.iconOnly,
          ),
          padding: const EdgeInsets.symmetric(horizontal: EasySubwaySpacing.md),
          foregroundColor: EasySubwayAccessibleColors.text,
          side: const BorderSide(color: EasySubwayAccessibleColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EasySubwayRadius.sheet),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
      ),
    );
  }
}

/// 승차 단계의 열차 카드. 출발 시각과, 서버가 실시간 출발을 준 열차만 남은 분을
/// 빨강으로 쓴다. 행선지와 첫차·막차 표시는 서버 응답에 없어 쓰지 않는다.
class _TrainCard extends StatelessWidget {
  const _TrainCard({required this.node});

  final JourneyRideNode node;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: node.trainSemanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: Key('journey-train-card-${node.legIndex}'),
          decoration: BoxDecoration(
            border: Border.all(color: EasySubwayAccessibleColors.line),
            borderRadius: BorderRadius.circular(EasySubwayRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EasySubwaySpacing.lg,
              vertical: EasySubwaySpacing.md,
            ),
            child: Wrap(
              spacing: EasySubwaySpacing.sm,
              children: [
                Text(
                  node.departureTime,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: EasySubwayFontWeight.emphasis,
                    color: EasySubwayAccessibleColors.text,
                  ),
                ),
                if (node.remainingLabel case final remaining?)
                  Text(
                    remaining,
                    key: Key('journey-train-remaining-${node.legIndex}'),
                    style: const TextStyle(
                      fontSize: 18,
                      color: EasySubwayAccessibleColors.statusDangerContent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 선 칸의 한 구간. 탑승은 노선색 실선, 걷기는 회색 점선이다.
class _Track {
  const _Track.solid(this.color) : dotted = false;
  const _Track.walk() : color = EasySubwayAccessibleColors.line, dotted = true;

  final Color color;
  final bool dotted;
}

class _StepMarker {
  const _StepMarker({
    required this.icon,
    required this.color,
    required this.time,
  });

  final IconData icon;
  final Color color;
  final String time;
}

class _RailSpec {
  const _RailSpec({this.above, this.below, this.marker, this.stopDot = false});

  const _RailSpec.walk()
    : above = const _Track.walk(),
      below = const _Track.walk(),
      marker = null,
      stopDot = false;

  final _Track? above;
  final _Track? below;
  final _StepMarker? marker;
  final bool stopDot;
}

class _Rail extends StatelessWidget {
  const _Rail({required this.spec});

  final _RailSpec spec;

  @override
  Widget build(BuildContext context) {
    final marker = spec.marker;
    return CustomPaint(
      painter: _RailPainter(spec),
      child: marker == null
          ? const SizedBox.expand()
          : Column(
              children: [
                SizedBox(height: EasySubwaySpacing.md),
                _markerIcon(marker),
                _markerTime(marker),
              ],
            ),
    );
  }

  Widget _markerIcon(_StepMarker marker) {
    return SizedBox.square(
      dimension: _markerDiameter,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: EasySubwayAccessibleColors.surface,
          shape: CircleBorder(side: BorderSide(color: marker.color, width: 2)),
        ),
        child: Icon(marker.icon, size: 18, color: marker.color),
      ),
    );
  }

  Widget _markerTime(_StepMarker marker) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border.all(color: EasySubwayAccessibleColors.line),
        borderRadius: BorderRadius.circular(EasySubwayRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _chipHorizontalPadding,
          vertical: 1,
        ),
        child: Text(marker.time, maxLines: 1, style: _chipStyle),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter(this.spec);

  final _RailSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final split = spec.marker != null
        ? EasySubwaySpacing.md + _markerDiameter / 2
        : size.height / 2;
    if (spec.above case final track?) _paintTrack(canvas, track, x, 0, split);
    if (spec.below case final track?) {
      _paintTrack(canvas, track, x, split, size.height);
    }
    if (spec.stopDot) {
      canvas.drawCircle(
        Offset(x, size.height / 2),
        _stopDotRadius,
        Paint()..color = EasySubwayAccessibleColors.surface,
      );
    }
  }

  void _paintTrack(
    Canvas canvas,
    _Track track,
    double x,
    double top,
    double bottom,
  ) {
    final paint = Paint()..color = track.color;
    if (!track.dotted) {
      canvas.drawRect(
        Rect.fromLTRB(
          x - _rideTrackWidth / 2,
          top,
          x + _rideTrackWidth / 2,
          bottom,
        ),
        paint,
      );
      return;
    }
    for (var y = top + _walkDotGap / 2; y < bottom; y += _walkDotGap) {
      canvas.drawCircle(Offset(x, y), _walkDotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_RailPainter oldDelegate) => oldDelegate.spec != spec;
}
