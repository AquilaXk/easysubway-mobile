import 'network_map_models.dart';

Map<String, List<NetworkMapLine>> networkMapStationLinesById(
  NetworkMapData data,
) {
  final linesById = {for (final line in data.lines) line.id: line};
  final stationLinesById = <String, List<NetworkMapLine>>{};

  void addLine(String stationId, String lineId) {
    final line = linesById[lineId];
    if (line == null) {
      return;
    }
    final stationLines = stationLinesById.putIfAbsent(stationId, () => []);
    if (!stationLines.any((existing) => existing.id == line.id)) {
      stationLines.add(line);
    }
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
