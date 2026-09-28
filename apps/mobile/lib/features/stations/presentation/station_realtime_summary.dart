import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../realtime/realtime_repository.dart';

const _stationRealtimeSummaryRadius = BorderRadius.all(Radius.circular(8));

class StationRealtimeSummary extends StatelessWidget {
  const StationRealtimeSummary({
    required this.snapshot,
    required this.onRetry,
    this.previousStation,
    this.nextStation,
    super.key,
  });

  final RealtimeSnapshot snapshot;
  final VoidCallback onRetry;
  final String? previousStation;
  final String? nextStation;

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
              for (final group in _groupRealtimeArrivals(
                snapshot.arrivals,
                previousStation: previousStation,
                nextStation: nextStation,
              )) ...[
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

List<_RealtimeGroup> _groupRealtimeArrivals(
  List<RealtimeArrival> arrivals, {
  String? previousStation,
  String? nextStation,
}) {
  final map = <String, List<RealtimeArrival>>{};
  final prev = previousStation?.trim();
  final next = nextStation?.trim();

  for (final arrival in arrivals) {
    final rawDir = arrival.direction.trim();
    final dest = arrival.destination.trim();

    final isDown = rawDir.contains('하행') || rawDir.contains('외선');
    final isUp = rawDir.contains('상행') || rawDir.contains('내선');

    String dir;
    if (isDown && !isUp) {
      if (next != null && next.isNotEmpty) {
        dir = '$next 방면';
      } else if (rawDir.isNotEmpty) {
        dir = rawDir.endsWith('방면') ? rawDir : '$rawDir 방면';
      } else if (dest.isNotEmpty) {
        final cleanDest = dest.endsWith('행')
            ? dest.substring(0, dest.length - 1)
            : dest;
        dir = cleanDest.endsWith('방면') ? cleanDest : '$cleanDest 방면';
      } else {
        dir = '열차 도착';
      }
    } else if (isUp && !isDown) {
      if (prev != null && prev.isNotEmpty) {
        dir = '$prev 방면';
      } else if (rawDir.isNotEmpty) {
        dir = rawDir.endsWith('방면') ? rawDir : '$rawDir 방면';
      } else if (dest.isNotEmpty) {
        final cleanDest = dest.endsWith('행')
            ? dest.substring(0, dest.length - 1)
            : dest;
        dir = cleanDest.endsWith('방면') ? cleanDest : '$cleanDest 방면';
      } else {
        dir = '열차 도착';
      }
    } else if (prev != null &&
        prev.isNotEmpty &&
        (rawDir.contains(prev) || dest.contains(prev))) {
      dir = '$prev 방면';
    } else if (next != null &&
        next.isNotEmpty &&
        (rawDir.contains(next) || dest.contains(next))) {
      dir = '$next 방면';
    } else if (rawDir.isNotEmpty) {
      dir = rawDir.endsWith('방면') ? rawDir : '$rawDir 방면';
    } else if (dest.isNotEmpty) {
      final cleanDest = dest.endsWith('행')
          ? dest.substring(0, dest.length - 1)
          : dest;
      dir = cleanDest.endsWith('방면') ? cleanDest : '$cleanDest 방면';
    } else {
      dir = '열차 도착';
    }
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
      } else if (eta <= 3600) {
        final minutes = (eta / 60).round();
        if (minutes <= 0) {
          etaText = '곧 도착';
          isSoon = true;
        } else {
          etaText = '$minutes분 뒤 도착';
          isSoon = false;
        }
      } else {
        final hours = eta ~/ 3600;
        final minutes = (eta % 3600) ~/ 60;
        etaText = minutes == 0 ? '$hours시간 뒤 도착' : '$hours시간 $minutes분 뒤 도착';
        isSoon = false;
      }
    } else if (msg == '곧 도착' ||
        msg.contains('당역') ||
        (!msg.contains('전역') && (msg.contains('도착') || msg.contains('진입')))) {
      etaText = '곧 도착';
      isSoon = true;
    } else if (msg.contains('전역')) {
      etaText = msg.isNotEmpty ? msg : (pos.isNotEmpty ? pos : '전역 도착');
      isSoon = false;
    } else if (pos.isNotEmpty) {
      etaText = pos;
      isSoon = false;
    } else {
      etaText = msg.isNotEmpty ? msg : '곧 도착';
      isSoon = etaText == '곧 도착';
    }

    final cleanDest = arrival.destination.trim().isNotEmpty
        ? arrival.destination.trim()
        : arrival.direction.replaceAll('방면', '').trim();
    final destination = cleanDest.isEmpty
        ? '열차'
        : (cleanDest.endsWith('행') ? cleanDest : '$cleanDest행');

    final isWarning =
        !isSoon &&
        (etaText == '1분 뒤 도착' ||
            etaText == '2분 뒤 도착' ||
            etaText == '3분 뒤 도착' ||
            etaText.startsWith('1분') ||
            etaText.startsWith('2분') ||
            etaText.startsWith('3분') ||
            (eta != null && eta > 0 && eta <= 180));
    final isPrevStation =
        !isSoon &&
        !isWarning &&
        (etaText.contains('전역') || pos.contains('전역') || msg.contains('전역'));
    final Color badgeBg;
    final Color badgeBorder;
    final Color badgeText;
    if (isSoon) {
      badgeBg = EasySubwayColorPrimitives.statusDangerSoft;
      badgeBorder = EasySubwayColorPrimitives.statusDanger;
      badgeText = EasySubwayColorPrimitives.statusDanger;
    } else if (isWarning) {
      badgeBg = EasySubwayAccessibleColors.statusWarningSurface;
      badgeBorder = EasySubwayAccessibleColors.amberBorder;
      badgeText = EasySubwayAccessibleColors.amber;
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
                : (isWarning
                      ? EasySubwayAccessibleColors.amber
                      : EasySubwayAccessibleColors.primary),
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
          () {
            final statusSubtext = pos.isNotEmpty
                ? (msg.isNotEmpty && msg != pos && !msg.contains('도착')
                      ? '$pos ($msg)'
                      : pos)
                : (msg.isNotEmpty && msg != etaText ? msg : '');
            if (statusSubtext.isEmpty) {
              return const SizedBox.shrink();
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusSubtext,
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            );
          }(),
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
