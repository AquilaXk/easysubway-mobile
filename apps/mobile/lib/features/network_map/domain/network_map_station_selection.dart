import 'network_map_models.dart';

Map<String, List<NetworkMapLine>> networkMapStationLinesById(
  NetworkMapData data,
) {
  final linesById = {for (final line in data.lines) line.id: line};
  final stationLinesById = <String, List<NetworkMapLine>>{};
  final seenLineIdsByStation = <String, Set<String>>{};

  void addLine(String stationId, String lineId) {
    final line = linesById[lineId];
    if (line == null) {
      return;
    }
    final seen = seenLineIdsByStation.putIfAbsent(stationId, () => <String>{});
    if (!seen.add(line.id)) {
      return;
    }
    stationLinesById.putIfAbsent(stationId, () => <NetworkMapLine>[]).add(line);
  }

  if (data.stationLineMemberships.isNotEmpty) {
    for (final membership in data.stationLineMemberships) {
      addLine(membership.stationId, membership.lineId);
    }
  } else {
    for (final station in data.stations) {
      addLine(station.id, station.lineId);
    }
  }
  return stationLinesById;
}

/// O(1) 역 id 및 (id, lineId) 조회 인덱스.
class NetworkMapStationLookup {
  NetworkMapStationLookup.fromStations(List<NetworkMapStation> stations)
    : _byId = <String, NetworkMapStation>{},
      _byIdentity = <(String, String), NetworkMapStation>{} {
    for (final station in stations) {
      _byId.putIfAbsent(station.id, () => station);
      _byIdentity.putIfAbsent((station.id, station.lineId), () => station);
    }
  }

  static final NetworkMapStationLookup empty =
      NetworkMapStationLookup.fromStations(const []);

  final Map<String, NetworkMapStation> _byId;
  final Map<(String, String), NetworkMapStation> _byIdentity;

  NetworkMapStation? byId(String? stationId) =>
      stationId == null ? null : _byId[stationId];

  NetworkMapStation? byIdentity(NetworkMapStation? selectedStation) =>
      selectedStation == null
      ? null
      : _byIdentity[(selectedStation.id, selectedStation.lineId)];
}

NetworkMapStation? networkMapStationById(
  List<NetworkMapStation> stations,
  String? stationId,
) {
  if (stationId == null) {
    return null;
  }
  for (final station in stations) {
    if (station.id == stationId) {
      return station;
    }
  }
  return null;
}

NetworkMapStation? networkMapStationByIdentity(
  List<NetworkMapStation> stations,
  NetworkMapStation? selectedStation,
) {
  if (selectedStation == null) {
    return null;
  }
  for (final station in stations) {
    if (station.id == selectedStation.id &&
        station.lineId == selectedStation.lineId) {
      return station;
    }
  }
  return null;
}
