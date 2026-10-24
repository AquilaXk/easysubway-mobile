import 'package:flutter/material.dart';

import '../core/format/date_time_labels.dart';
import '../core/ui/line_mark.dart';
import '../features/network_map/application/network_map_nearby_panel_state.dart';
import '../features/network_map/domain/nearby_adjacent_stations.dart';
import '../features/network_map/presentation/nearby_arrival_panel.dart';
import '../features/network_map/presentation/nearby_panel_control_row.dart';
import '../features/network_map/presentation/nearby_station_line_bar.dart';
import '../features/network_map/presentation/network_map_nearby_panel_content.dart';
import '../features/network_map/presentation/nearby_timetable_panel.dart';
import '../features/realtime/realtime_repository.dart';
import '../features/stations/domain/station_line.dart';
import '../features/stations/domain/station_models.dart';
import '../features/stations/presentation/service_pattern_badge.dart';
import '../features/stations/presentation/station_detail_body.dart';
import '../features/stations/presentation/station_line_badges.dart';

/// Network Map adjacent identity를 Station Detail app-composition 값으로 바꾼다.
StationDetailNeighbor? networkMapStationDetailNeighbor(
  NearbyAdjacentStationIdentity? identity,
) {
  if (identity == null) {
    return null;
  }
  return StationDetailNeighbor(
    stationId: identity.stationId,
    nameKo: identity.nameKo,
  );
}

StationSearchLine? networkMapNearbySelectedLine(
  StationSearchResult primary,
  String? selectedLineId,
) {
  if (primary.lines.isEmpty) {
    return null;
  }
  for (final line in primary.lines) {
    if (line.id == selectedLineId) {
      return line;
    }
  }
  return primary.lines.first;
}

/// 주변역 패널의 Stations·Realtime concrete widgets를 app layer에서 조합한다.
NetworkMapNearbyPanelSuccessContent buildNetworkMapNearbyPanelSuccessContent({
  required List<StationSearchResult> results,
  required RealtimeSnapshot realtime,
  required String? selectedLineId,
  required NetworkMapNearbyPanelDataSource dataSource,
  required StationTimetable? timetable,
  required NearbyAdjacentStations adjacentStations,
  VoidCallback? onOpenStationDetail,
  ValueChanged<StationDetailNeighbor>? onSelectNeighbor,
  VoidCallback? onOpenTimetable,
  Widget dataSourceToggle = const SizedBox.shrink(),
  void Function(StationSearchResult station, StationSearchLine line)?
  onRefreshRealtime,
  DateTime? now,
}) {
  final primary = results.first;
  final selectedLine = networkMapNearbySelectedLine(primary, selectedLineId);
  final lineColor = _networkMapNearbySelectedLineColor(selectedLine);
  final selectNeighbor = onSelectNeighbor;
  final previous = networkMapStationDetailNeighbor(
    adjacentStations.previousNeighbor,
  );
  final next = networkMapStationDetailNeighbor(adjacentStations.nextNeighbor);
  final openTimetable = onOpenTimetable;
  final ValueChanged<String>? openDirection = openTimetable == null
      ? null
      : (_) => openTimetable();
  final isRealtime = dataSource == NetworkMapNearbyPanelDataSource.realtime;
  return (
    controlRow: NearbyPanelControlRow(
      toggle: dataSourceToggle,
      receivedAtLabel: isRealtime ? _receivedAtLabel(realtime) : null,
      onRefresh: _refreshAction(
        isRealtime ? onRefreshRealtime : null,
        primary,
        selectedLine,
      ),
    ),
    stationBar: NearbyStationLineBar(
      leftName: adjacentStations.leftName,
      rightName: adjacentStations.rightName,
      stationName: primary.nameKo,
      badgeText: selectedLine?.badgeText ?? '',
      lineColor: lineColor,
      badgeBuilder: selectedLine == null
          ? null
          : (diameter) => StationLineBadge(
              line: selectedLine,
              size: diameter,
              maxTextScale: lineMarkFixedChromeMaxTextScale,
            ),
      line: selectedLine,
      onStationNameTap: onOpenStationDetail,
      onLeftNameTap: selectNeighbor == null || previous == null
          ? null
          : () => selectNeighbor(previous),
      onRightNameTap: selectNeighbor == null || next == null
          ? null
          : () => selectNeighbor(next),
    ),
    dataPanel: isRealtime
        ? NearbyArrivalPanel(
            data: NearbyArrivalPanelData(
              status: switch (realtime.status) {
                RealtimeSnapshotStatus.fresh => NearbyArrivalPanelStatus.fresh,
                RealtimeSnapshotStatus.stale => NearbyArrivalPanelStatus.stale,
                _ => NearbyArrivalPanelStatus.unavailable,
              },
              arrivals: [
                for (final arrival in realtime.arrivals)
                  NearbyArrivalData(
                    direction: arrival.direction,
                    destination: arrival.destination,
                    etaSeconds: arrival.etaSeconds,
                    message: arrival.message,
                    positionMessage: arrival.positionMessage,
                  ),
              ],
            ),
            leftName: adjacentStations.leftName,
            rightName: adjacentStations.rightName,
            onOpenDirection: openDirection,
            now: now,
          )
        : NearbyTimetablePanel(
            data: _networkMapNearbyTimetablePanelData(timetable),
            leftName: adjacentStations.leftName,
            rightName: adjacentStations.rightName,
            expressBadgeBuilder: () => const ServicePatternBadge.express(),
            onOpenDirection: openDirection,
            now: now,
          ),
  );
}

/// 실시간 줄의 새로고침. 다시 받을 노선이 있을 때만 버튼을 둔다.
VoidCallback? _refreshAction(
  void Function(StationSearchResult station, StationSearchLine line)? refresh,
  StationSearchResult station,
  StationSearchLine? line,
) {
  if (refresh == null || line == null) {
    return null;
  }
  return () => refresh(station, line);
}

/// 실시간을 받은 시각. 받은 실시간이 없거나 시각을 해석할 수 없으면 null이라 줄에서 빠진다.
({String visible, String spoken})? _receivedAtLabel(RealtimeSnapshot realtime) {
  final received =
      realtime.status == RealtimeSnapshotStatus.fresh ||
          realtime.status == RealtimeSnapshotStatus.stale
      ? parseServerDateTime(realtime.receivedAt.trim())
      : null;
  if (received == null) {
    return null;
  }
  return (visible: kstClock(received), spoken: kstSpokenClock(received));
}

Color _networkMapNearbySelectedLineColor(StationSearchLine? line) {
  if (line == null) {
    return stationLineColor(stationLineFallbackBrandHex);
  }
  final raw = line.color.trim();
  if (raw.isEmpty) {
    return stationLineColor(
      fallbackLineColorHex(lineId: line.id, lineName: line.name),
    );
  }
  return stationLineColor(raw);
}

NearbyTimetablePanelData? _networkMapNearbyTimetablePanelData(
  StationTimetable? timetable,
) {
  if (timetable == null) {
    return null;
  }
  return NearbyTimetablePanelData(
    directions: [
      for (final direction in timetable.directions)
        NearbyTimetableDirectionData(
          name: direction.name,
          departures: [
            for (final departure in direction.departures)
              NearbyTimetableDepartureData(
                directionName: departure.directionName,
                seconds: departure.seconds,
                timeLabel: departure.timeLabel,
                semanticLabel: departure.semanticLabel,
                isExpress: departure.isExpress,
                destination: departure.destination,
              ),
          ],
        ),
    ],
  );
}
