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
    this.positionMessage = '',
  });

  final String direction;
  final String destination;
  final int? etaSeconds;
  final String message;
  final String positionMessage;
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
    this.onSelectTimetable,
    this.now,
    super.key,
  });

  final NearbyArrivalPanelData data;
  final Color lineColor;
  final String? leftName;
  final String? rightName;
  final VoidCallback? onSelectTimetable;
  final DateTime? now;

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
        final dir = _resolveNearbyArrivalDirection(
          arrival,
          leftName: leftName,
          rightName: rightName,
        );
        groups.putIfAbsent(dir, () => []).add(arrival);
      }
      for (final key in groups.keys) {
        dataGroups.add(groups[key]!);
      }
    }
    final dataTitles = [
      for (final group in dataGroups)
        _arrivalDirectionLabel(
          group.first,
          leftName: leftName,
          rightName: rightName,
        ),
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
                destination: arrival.destination.trim().isNotEmpty
                    ? arrival.destination.trim()
                    : _fallbackDestination(arrival.direction),
                eta: _formatArrivalEta(arrival, now: now),
              ),
          ],
        ),
      );
      for (final arrival in visible) {
        final part = [
          _arrivalDirectionLabel(
            arrival,
            leftName: leftName,
            rightName: rightName,
          ),
          arrival.destination.trim().isEmpty
              ? ''
              : '${arrival.destination.trim()}행',
          _formatArrivalEta(arrival, now: now),
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

String _formatArrivalEta(NearbyArrivalData arrival, {DateTime? now}) {
  final eta = arrival.etaSeconds;
  final pos = arrival.positionMessage.trim();
  final msg = arrival.message.trim();

  if (eta != null && eta > 0) {
    if (eta < 60) {
      return '곧 도착';
    }
    if (eta <= 3600) {
      final minutes = (eta / 60).round();
      return minutes <= 0 ? '곧 도착' : '$minutes분 뒤 도착';
    }
    final hours = eta ~/ 3600;
    final minutes = (eta % 3600) ~/ 60;
    return minutes == 0 ? '$hours시간 뒤 도착' : '$hours시간 $minutes분 뒤 도착';
  }

  if (msg == '곧 도착' && pos.isNotEmpty) {
    return pos;
  }
  if (pos.isNotEmpty && msg.isEmpty) {
    return pos;
  }
  if (msg == '곧 도착' ||
      msg.contains('당역') ||
      (!msg.contains('전역') && (msg.contains('도착') || msg.contains('진입')))) {
    return '곧 도착';
  }
  if (msg.contains('전역')) {
    return msg.isNotEmpty ? msg : (pos.isNotEmpty ? pos : '전역 도착');
  }
  if (pos.isNotEmpty) {
    return pos;
  }
  return msg.isNotEmpty ? msg : '곧 도착';
}

String _fallbackDestination(String direction) {
  final clean = direction.replaceAll('방면', '').trim();
  if (clean.isEmpty) return '';
  return clean.endsWith('행') ? clean.substring(0, clean.length - 1) : clean;
}

String _resolveNearbyArrivalDirection(
  NearbyArrivalData arrival, {
  String? leftName,
  String? rightName,
}) {
  final left = leftName?.trim();
  final right = rightName?.trim();
  final rawDir = arrival.direction.trim();
  final dest = arrival.destination.trim();

  final isDown = rawDir.contains('하행') || rawDir.contains('외선');
  final isUp = rawDir.contains('상행') || rawDir.contains('내선');

  final cleanRaw =
      (!rawDir.contains('상행') && !rawDir.contains('하행') && rawDir.endsWith('행'))
      ? rawDir.substring(0, rawDir.length - 1)
      : rawDir;
  final cleanDest = dest.endsWith('행')
      ? dest.substring(0, dest.length - 1)
      : dest;

  if (isDown && !isUp) {
    if (right != null && right.isNotEmpty) {
      return '$right 방면';
    }
    return cleanRaw.endsWith('방면') ? cleanRaw : '$cleanRaw 방면';
  }

  if (isUp && !isDown) {
    if (left != null && left.isNotEmpty) {
      return '$left 방면';
    }
    return cleanRaw.endsWith('방면') ? cleanRaw : '$cleanRaw 방면';
  }

  if (left != null &&
      left.isNotEmpty &&
      (rawDir.contains(left) || dest.contains(left))) {
    return '$left 방면';
  }
  if (right != null &&
      right.isNotEmpty &&
      (rawDir.contains(right) || dest.contains(right))) {
    return '$right 방면';
  }
  if (cleanRaw.isNotEmpty) {
    return cleanRaw.endsWith('방면') ? cleanRaw : '$cleanRaw 방면';
  }
  if (cleanDest.isNotEmpty) {
    return cleanDest.endsWith('방면') ? cleanDest : '$cleanDest 방면';
  }
  return '';
}

String _arrivalDirectionLabel(
  NearbyArrivalData arrival, {
  String? leftName,
  String? rightName,
}) {
  return _resolveNearbyArrivalDirection(
    arrival,
    leftName: leftName,
    rightName: rightName,
  );
}
