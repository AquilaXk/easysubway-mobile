import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import 'nearby_direction_columns.dart';
import 'nearby_direction_title.dart';

enum NearbyArrivalPanelStatus { loading, fresh, stale, unavailable }

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
    this.arrivals = const [],
  });

  final NearbyArrivalPanelStatus status;
  final List<NearbyArrivalData> arrivals;
}

/// 주변역 패널의 실시간 도착 정보. 열차 정보가 없어도 인접역에서 "○○ 방면"
/// 제목을 유도해 방면 카드 두 개를 유지한다. 응답을 기다리는 중에는 빈 카드에 대시를,
/// 받았는데 열차가 없으면 실시간 정보 없음을 쓴다.
class NearbyArrivalPanel extends StatelessWidget {
  const NearbyArrivalPanel({
    required this.data,
    required this.leftName,
    required this.rightName,
    this.onOpenDirection,
    this.now,
    super.key,
  });

  /// 상용 지하철 서비스가 실시간 도착이 없는 방면에 쓰는 문구.
  static const unavailableMessage = ['실시간 정보 없음', '(시간표를 확인해 주세요.)'];

  final NearbyArrivalPanelData data;
  final String? leftName;
  final String? rightName;
  final VoidCallback? onOpenDirection;
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
      dataGroups.addAll(groups.values);
    }
    final slots = resolveNearbyColumnSlots(
      dataTitles: [
        for (final group in dataGroups)
          _resolveNearbyArrivalDirection(
            group.first,
            leftName: leftName,
            rightName: rightName,
          ),
      ],
      leftName: leftName,
      rightName: rightName,
    );
    final loading = data.status == NearbyArrivalPanelStatus.loading;
    if (slots.isEmpty) {
      return NearbyDataUnavailable(lines: unavailableMessage, loading: loading);
    }

    final columns = [
      for (final slot in slots)
        switch (slot.dataIndex) {
          null => NearbyPanelColumn(
            title: slot.title,
            emptyMessage: unavailableMessage,
            loading: loading,
          ),
          final index => _arrivalColumn(slot.title, dataGroups[index]),
        },
    ];

    final isStale = data.status == NearbyArrivalPanelStatus.stale && hasData;
    return Column(
      key: hasData ? null : const Key('networkMapNearbyArrivalSkeleton'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isStale) ...[
          const Text(
            '최근 도착 정보',
            style: TextStyle(
              color: EasySubwayAccessibleColors.mutedText,
              fontSize: 12,
              fontWeight: EasySubwayFontWeight.regular,
            ),
          ),
          const SizedBox(height: 6),
        ],
        NearbyPanelColumns(columns: columns, onOpenDirection: onOpenDirection),
      ],
    );
  }

  NearbyPanelColumn _arrivalColumn(
    String title,
    List<NearbyArrivalData> arrivals,
  ) {
    final visible = arrivals.take(2).toList(growable: false);
    final rows = [
      for (final arrival in visible)
        (
          destination: _destinationOf(arrival),
          eta: _formatArrivalEta(arrival, now: now),
        ),
    ];
    return NearbyPanelColumn(
      title: title,
      rows: [
        for (final row in rows)
          NearbyArrivalRow(
            destination: nearbyDestinationName(row.destination),
            eta: row.eta,
          ),
      ],
      rowsLabel: [
        for (final row in rows)
          [
            _destinationSpoken(row.destination),
            row.eta,
          ].where((part) => part.isNotEmpty).join(' '),
      ].join(', '),
    );
  }
}

String _destinationOf(NearbyArrivalData arrival) {
  final destination = arrival.destination.trim();
  return destination.isNotEmpty
      ? destination
      : _fallbackDestination(arrival.direction);
}

/// 스크린리더는 `약수행`처럼 행선지임을 읽는다.
String _destinationSpoken(String destination) {
  if (destination.isEmpty ||
      nearbyDirectionWords.contains(destination) ||
      destination.endsWith('행')) {
    return destination;
  }
  return '$destination행';
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
      return minutes <= 0 ? '곧 도착' : '$minutes분';
    }
    final hours = eta ~/ 3600;
    final minutes = (eta % 3600) ~/ 60;
    return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
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
  if (clean == '상행' || clean == '하행') return clean;
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
