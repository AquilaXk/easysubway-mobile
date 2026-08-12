import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import 'nearby_direction_columns.dart';

class NearbyTimetablePanelData {
  const NearbyTimetablePanelData({required this.directions});

  final List<NearbyTimetableDirectionData> directions;
}

class NearbyTimetableDirectionData {
  const NearbyTimetableDirectionData({
    required this.name,
    required this.departures,
  });

  final String name;
  final List<NearbyTimetableDepartureData> departures;
}

class NearbyTimetableDepartureData {
  const NearbyTimetableDepartureData({
    required this.directionName,
    required this.seconds,
    required this.timeLabel,
    required this.semanticLabel,
    required this.isExpress,
  });

  final String directionName;
  final int seconds;
  final String timeLabel;
  final String semanticLabel;
  final bool isExpress;
}

class NearbyTimetablePanel extends StatelessWidget {
  const NearbyTimetablePanel({
    required this.data,
    required this.lineColor,
    required this.leftName,
    required this.rightName,
    required this.expressBadgeBuilder,
    this.now,
    super.key,
  });

  final NearbyTimetablePanelData? data;
  final Color lineColor;
  final String? leftName;
  final String? rightName;
  final Widget Function() expressBadgeBuilder;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // 로컬 조회 중이어도 스피너 대신 인접역 방면·대시 골격을 즉시 그린다(#2453).
    final departures = _nextTimetableDepartures(data, now ?? DateTime.now());
    // 방면별로 그룹핑(실시간과 동일한 열 구성 원칙 적용).
    final dataGroups = <List<_NextTimetableDeparture>>[];
    for (final departure in departures) {
      if (dataGroups.isEmpty ||
          dataGroups.last.first.directionLabel != departure.directionLabel) {
        dataGroups.add([departure]);
      } else {
        dataGroups.last.add(departure);
      }
    }
    final dataTitles = [
      for (final group in dataGroups) group.first.directionLabel,
    ];
    final slots = resolveNearbyColumnSlots(
      dataTitles: dataTitles,
      leftName: leftName,
      rightName: rightName,
    );
    if (slots.isEmpty) {
      return const NearbyDataUnavailable();
    }

    final columns = <NearbyPanelColumn>[];
    final semanticParts = <String>[];
    for (final slot in slots) {
      final dataIndex = slot.dataIndex;
      if (dataIndex == null) {
        // 대시 열 의미는 NearbyPanelColumns 열 단위 Semantics가 담당한다.
        columns.add(NearbyPanelColumn(title: slot.title));
        continue;
      }
      final group = dataGroups[dataIndex];
      final rows = <Widget>[];
      for (var row = 0; row < group.length; row++) {
        if (row > 0) {
          rows.add(const SizedBox(height: 4));
        }
        rows.add(
          _NearbyTimetableDepartureView(
            data: group[row],
            expressBadgeBuilder: expressBadgeBuilder,
          ),
        );
        semanticParts.add(group[row].departure.semanticLabel);
      }
      columns.add(NearbyPanelColumn(title: slot.title, rows: rows));
    }

    final hasData = departures.isNotEmpty;
    final columnsView = KeyedSubtree(
      key: hasData ? null : const Key('networkMapNearbyTimetableSkeleton'),
      child: NearbyPanelColumns(columns: columns, lineColor: lineColor),
    );
    // 골격↔데이터 갱신 시 liveRegion 재발화를 피한다.
    // 순수 골격은 열 단위 Semantics, 데이터 혼재 시 부모 라벨에 대시 열도 합친다.
    if (semanticParts.isEmpty) {
      return columnsView;
    }
    final dashLabels = [
      for (final slot in slots)
        if (slot.dataIndex == null)
          slot.title.isEmpty ? '정보 없음' : '${slot.title} 정보 없음',
    ];
    return Semantics(
      excludeSemantics: true,
      label: [...semanticParts, ...dashLabels].join(', '),
      child: columnsView,
    );
  }
}

class _NextTimetableDeparture {
  const _NextTimetableDeparture({
    required this.directionLabel,
    required this.departure,
  });

  final String directionLabel;
  final NearbyTimetableDepartureData departure;
}

List<_NextTimetableDeparture> _nextTimetableDepartures(
  NearbyTimetablePanelData? data,
  DateTime now,
) {
  if (data == null) {
    return const [];
  }
  final currentSeconds =
      now.hour * Duration.secondsPerHour +
      now.minute * Duration.secondsPerMinute +
      now.second;
  final result = <_NextTimetableDeparture>[];
  var visibleDirectionCount = 0;
  for (final direction in data.directions) {
    final departures = direction.departures
        .where((candidate) => candidate.seconds >= currentSeconds)
        .take(2)
        .toList(growable: false);
    if (departures.isEmpty) {
      continue;
    }
    final rawDirection = direction.name.trim().isEmpty
        ? departures.first.directionName.trim()
        : direction.name.trim();
    final label = rawDirection.endsWith('방면')
        ? rawDirection
        : '$rawDirection 방면';
    for (final departure in departures) {
      result.add(
        _NextTimetableDeparture(directionLabel: label, departure: departure),
      );
    }
    visibleDirectionCount++;
    if (visibleDirectionCount == 2) {
      break;
    }
  }
  return result;
}

class _NearbyTimetableDepartureView extends StatelessWidget {
  const _NearbyTimetableDepartureView({
    required this.data,
    required this.expressBadgeBuilder,
  });

  final _NextTimetableDeparture data;
  final Widget Function() expressBadgeBuilder;

  @override
  Widget build(BuildContext context) {
    final time = Text(
      data.departure.timeLabel,
      style: const TextStyle(
        color: EasySubwayAccessibleColors.statusDangerContent,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!data.departure.isExpress) {
      return time;
    }
    // 급행 출발은 시각 옆에 배지를 붙인다. text scale·좁은 폭·landscape에서
    // 시각과 배지가 겹치지 않게 Wrap으로 다음 줄 배치한다(clipping 금지).
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [time, expressBadgeBuilder()],
    );
  }
}
