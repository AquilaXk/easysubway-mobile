import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../realtime/realtime_repository.dart';

const _stationRealtimeSummaryRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationRealtimeSummary extends StatelessWidget {
  const StationRealtimeSummary({
    required this.snapshot,
    required this.onRetry,
    super.key,
  });

  final RealtimeSnapshot snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = switch (snapshot.status) {
      RealtimeSnapshotStatus.fresh => '도착 정보',
      RealtimeSnapshotStatus.stale => '최근 도착 정보',
      RealtimeSnapshotStatus.unsupported => '실시간 정보 미지원',
      RealtimeSnapshotStatus.unavailable => '실시간 정보 확인 불가',
      RealtimeSnapshotStatus.loading => '실시간 정보 확인 중',
    };
    // 실시간 조회가 실패로 끝난 경우에만 다시 시도를 권한다. 미지원 노선은
    // 재시도해도 결과가 같으므로 버튼을 노출하지 않는다.
    final canRetry = snapshot.status == RealtimeSnapshotStatus.unavailable;
    final summary = snapshot.summaryText.trim().isEmpty
        ? '역 정보와 경로 검색은 계속 이용할 수 있습니다.'
        : snapshot.summaryText.trim();
    final updatedLabel = snapshot.receivedAt.trim().isEmpty
        ? ''
        : '마지막 갱신 ${snapshot.receivedAt}';
    final semanticParts = [
      '실시간 열차',
      title,
      summary,
      if (updatedLabel.isNotEmpty) updatedLabel,
      if (canRetry) '다시 시도할 수 있어요',
    ];
    return Semantics(
      label: semanticParts.join(', '),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surfaceDefault,
          borderRadius: _stationRealtimeSummaryRadius,
          border: Border.all(color: EasySubwayAccessibleColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule,
                  color: EasySubwayAccessibleColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            if (snapshot.arrivals.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final group in _groupRealtimeArrivals(snapshot.arrivals)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    group.direction,
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.secondaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final arrival in group.arrivals)
                  _StationRealtimeRow(arrival: arrival),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(
                summary,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (updatedLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                updatedLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  height: 1.3,
                ),
              ),
            ],
            if (canRetry) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('stationRealtimeRetryButton'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('다시 시도'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RealtimeGroup {
  const _RealtimeGroup({required this.direction, required this.arrivals});
  final String direction;
  final List<RealtimeArrival> arrivals;
}

List<_RealtimeGroup> _groupRealtimeArrivals(List<RealtimeArrival> arrivals) {
  final map = <String, List<RealtimeArrival>>{};
  for (final arrival in arrivals) {
    final dir = arrival.direction.trim().isNotEmpty
        ? arrival.direction.trim()
        : (arrival.destination.trim().isNotEmpty
            ? '${arrival.destination.trim()} 방면'
            : '열차 도착');
    map.putIfAbsent(dir, () => []).add(arrival);
  }
  return [
    for (final entry in map.entries)
      _RealtimeGroup(direction: entry.key, arrivals: entry.value),
  ];
}

class _StationRealtimeRow extends StatelessWidget {
  const _StationRealtimeRow({required this.arrival});
  final RealtimeArrival arrival;

  @override
  Widget build(BuildContext context) {
    final eta = arrival.etaSeconds;
    final pos = arrival.positionMessage.trim();
    final msg = arrival.message.trim();

    final String etaText;
    final bool isSoon;
    if (eta != null && eta > 0) {
      if (eta < 60) {
        etaText = '곧 도착';
        isSoon = true;
      } else if (eta <= 600) {
        final minutes = (eta / 60).round();
        if (minutes <= 0) {
          etaText = '곧 도착';
          isSoon = true;
        } else {
          etaText = '$minutes분뒤 도착';
          isSoon = false;
        }
      } else {
        final arrivalTime = DateTime.now().add(Duration(seconds: eta));
        final hh = arrivalTime.hour.toString().padLeft(2, '0');
        final mm = arrivalTime.minute.toString().padLeft(2, '0');
        etaText = '$hh:$mm';
        isSoon = false;
      }
    } else if (msg == '곧 도착' || msg.contains('도착') || msg.contains('진입')) {
      etaText = msg.isNotEmpty ? msg : (pos.isNotEmpty ? pos : '곧 도착');
      isSoon = true;
    } else if (pos.isNotEmpty) {
      etaText = pos;
      isSoon = false;
    } else {
      etaText = msg.isNotEmpty ? msg : '곧 도착';
      isSoon = etaText == '곧 도착';
    }

    final destination = arrival.destination.trim().isEmpty
        ? '열차'
        : (arrival.destination.trim().endsWith('행')
            ? arrival.destination.trim()
            : '${arrival.destination.trim()}행');

    final isPrevStation = etaText.contains('전역') || pos.contains('전역');
    final Color badgeBg;
    final Color badgeBorder;
    final Color badgeText;
    if (isSoon) {
      badgeBg = EasySubwayColorPrimitives.statusDangerSoft;
      badgeBorder = EasySubwayColorPrimitives.statusDanger;
      badgeText = EasySubwayColorPrimitives.statusDanger;
    } else if (isPrevStation) {
      badgeBg = EasySubwayAccessibleColors.surfaceBrand;
      badgeBorder = EasySubwayAccessibleColors.brandSignatureMedium;
      badgeText = EasySubwayAccessibleColors.primary;
    } else {
      badgeBg = EasySubwayAccessibleColors.surfaceDefault;
      badgeBorder = EasySubwayAccessibleColors.line;
      badgeText = EasySubwayAccessibleColors.text;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surfaceDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Row(
        children: [
          Icon(
            Icons.subway_rounded,
            size: 18,
            color: isSoon
                ? EasySubwayColorPrimitives.statusDanger
                : EasySubwayAccessibleColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              destination,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (pos.isNotEmpty && pos != etaText) ...[
            Text(
              pos,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.secondaryText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeBorder),
            ),
            child: Text(
              etaText,
              style: TextStyle(
                color: badgeText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
