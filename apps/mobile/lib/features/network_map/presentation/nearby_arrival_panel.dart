import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import 'nearby_direction_columns.dart';
import 'nearby_direction_title.dart';

enum NearbyArrivalPanelStatus { fresh, stale, unavailable }

class NearbyArrivalData {
  const NearbyArrivalData({
    required this.direction,
    required this.destination,
    required this.etaSeconds,
    required this.message,
  });

  final String direction;
  final String destination;
  final int? etaSeconds;
  final String message;
}

class NearbyArrivalPanelData {
  const NearbyArrivalPanelData({
    required this.status,
    this.receivedAt = '',
    this.arrivals = const [],
  });

  final NearbyArrivalPanelStatus status;
  final String receivedAt;
  final List<NearbyArrivalData> arrivals;
}

/// 주변역 패널의 실시간 도착 정보. 열차 정보가 없어도 인접역에서 "○○ 방면"
/// 제목을 유도해 두 열과 대시 skeleton을 유지한다.
class NearbyArrivalPanel extends StatelessWidget {
  const NearbyArrivalPanel({
    required this.data,
    required this.lineColor,
    required this.leftName,
    required this.rightName,
    super.key,
  });

  final NearbyArrivalPanelData data;
  final Color lineColor;
  final String? leftName;
  final String? rightName;

  @override
  Widget build(BuildContext context) {
    final hasData =
        (data.status == NearbyArrivalPanelStatus.fresh ||
            data.status == NearbyArrivalPanelStatus.stale) &&
        data.arrivals.isNotEmpty;
    final dataGroups = <List<NearbyArrivalData>>[];
    if (hasData) {
      final groups = <String, List<NearbyArrivalData>>{};
      for (final arrival in data.arrivals) {
        groups.putIfAbsent(arrival.direction, () => []).add(arrival);
      }
      for (final key in groups.keys) {
        dataGroups.add(groups[key]!);
      }
    }
    final dataTitles = [
      for (final group in dataGroups) _arrivalDirectionLabel(group.first),
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
        columns.add(NearbyPanelColumn(title: slot.title));
        continue;
      }
      final visible = dataGroups[dataIndex].take(2).toList(growable: false);
      columns.add(
        NearbyPanelColumn(
          title: slot.title,
          rows: [
            for (final arrival in visible)
              NearbyArrivalRow(
                destination: arrival.destination.trim(),
                eta: _formatArrivalEta(arrival),
              ),
          ],
        ),
      );
      for (final arrival in visible) {
        final part = [
          _arrivalDirectionLabel(arrival),
          arrival.destination.trim().isEmpty
              ? ''
              : '${arrival.destination.trim()}행',
          _formatArrivalEta(arrival),
        ].where((part) => part.isNotEmpty).join(' ');
        if (part.isNotEmpty) {
          semanticParts.add(part);
        }
      }
    }

    final isStale = data.status == NearbyArrivalPanelStatus.stale && hasData;
    final columnsView = NearbyPanelColumns(
      columns: columns,
      lineColor: lineColor,
    );
    final body = Column(
      key: hasData ? null : const Key('networkMapNearbyArrivalSkeleton'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isStale) ...[
          Text(
            data.receivedAt.trim().isEmpty
                ? '최근 도착 정보'
                : '최근 도착 정보 · ${data.receivedAt.trim()}',
            style: const TextStyle(
              color: EasySubwayAccessibleColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        columnsView,
      ],
    );
    if (semanticParts.isEmpty) {
      return body;
    }
    final dashLabels = [
      for (final slot in slots)
        if (slot.dataIndex == null)
          slot.title.isEmpty ? '정보 없음' : '${slot.title} 정보 없음',
    ];
    return Semantics(
      excludeSemantics: true,
      label: [...semanticParts, ...dashLabels].join(', '),
      child: body,
    );
  }
}

String _formatArrivalEta(NearbyArrivalData arrival) {
  final eta = arrival.etaSeconds;
  if (eta != null && eta > 0) {
    final minutes = (eta / 60).round();
    return minutes <= 0 ? '곧 도착' : '약 $minutes분';
  }
  return arrival.message.trim();
}

String _arrivalDirectionLabel(NearbyArrivalData arrival) {
  final direction = arrival.direction.trim();
  if (direction.isNotEmpty) {
    return direction;
  }
  final destination = arrival.destination.trim();
  return destination.isEmpty ? '' : '$destination 방면';
}
