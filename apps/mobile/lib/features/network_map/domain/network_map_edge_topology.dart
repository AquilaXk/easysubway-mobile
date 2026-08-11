import 'network_map_models.dart';

String _stationLineKey(String stationId, String lineId) => '$stationId:$lineId';

NetworkMapStation? networkMapStationForMapEdgeEndpoint({
  required String endpoint,
  required String lineId,
  required Iterable<NetworkMapStation> stations,
}) {
  final stationsById = <String, List<NetworkMapStation>>{};
  final stationByLineKey = <String, NetworkMapStation>{};
  for (final station in stations) {
    stationsById.putIfAbsent(station.id, () => []).add(station);
    stationByLineKey[_stationLineKey(station.id, station.lineId)] = station;
  }
  return _stationForEdgeEndpoint(
    endpoint,
    lineId,
    stationByLineKey,
    stationsById,
  );
}

NetworkMapStation? _stationForEdgeEndpoint(
  String endpoint,
  String lineId,
  Map<String, NetworkMapStation> stationByLineKey,
  Map<String, List<NetworkMapStation>> stationsById,
) {
  final endpointStations = stationsById[endpoint];
  return stationByLineKey[endpoint] ??
      stationByLineKey[_stationLineKey(endpoint, lineId)] ??
      (endpointStations == null || endpointStations.isEmpty
          ? null
          : endpointStations.first);
}

/// 노선도 하단 패널의 이전/다음 역을 카탈로그 topology edge에서 고른다.
({
  String? leftName,
  String? rightName,
  String? leftStationId,
  String? rightStationId,
})
networkMapAdjacentStationPair({
  required Iterable<NetworkMapStation> stations,
  required Iterable<NetworkMapEdge> edges,
  required String stationId,
  String? lineId,
}) {
  final selectedStations = stations
      .where((station) => station.id == stationId)
      .toList(growable: false);
  if (selectedStations.isEmpty) {
    return (
      leftName: null,
      rightName: null,
      leftStationId: null,
      rightStationId: null,
    );
  }
  final selectedLineId = lineId?.trim();
  final selected = selectedLineId == null || selectedLineId.isEmpty
      ? selectedStations.first
      : selectedStations.firstWhere(
          (station) => station.lineId == selectedLineId,
          orElse: () => selectedStations.first,
        );

  NetworkMapStation? left;
  NetworkMapStation? right;
  for (final edge in edges) {
    if (edge.lineId != selected.lineId) {
      continue;
    }
    final from = networkMapStationForMapEdgeEndpoint(
      endpoint: edge.fromStationId,
      lineId: edge.lineId,
      stations: stations,
    );
    final to = networkMapStationForMapEdgeEndpoint(
      endpoint: edge.toStationId,
      lineId: edge.lineId,
      stations: stations,
    );
    NetworkMapStation? candidate;
    if (_sameStation(from, selected)) {
      candidate = to;
    } else if (_sameStation(to, selected)) {
      candidate = from;
    }
    if (candidate == null) {
      continue;
    }
    if (candidate.sequence < selected.sequence) {
      if (left == null || candidate.sequence > left.sequence) {
        left = candidate;
      }
    } else if (candidate.sequence > selected.sequence) {
      if (right == null || candidate.sequence < right.sequence) {
        right = candidate;
      }
    }
  }

  return (
    leftName: left?.nameKo,
    rightName: right?.nameKo,
    leftStationId: left?.id,
    rightStationId: right?.id,
  );
}

bool _sameStation(NetworkMapStation? a, NetworkMapStation b) {
  return a != null && a.id == b.id && a.lineId == b.lineId;
}
