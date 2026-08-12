typedef NearbyAdjacentStationIdentity = ({String stationId, String nameKo});

class NearbyAdjacentStations {
  const NearbyAdjacentStations({
    this.leftName,
    this.rightName,
    this.leftStationId,
    this.rightStationId,
  });

  final String? leftName;
  final String? rightName;
  final String? leftStationId;
  final String? rightStationId;

  NearbyAdjacentStationIdentity? get previousNeighbor =>
      _neighbor(stationId: leftStationId, nameKo: leftName);

  NearbyAdjacentStationIdentity? get nextNeighbor =>
      _neighbor(stationId: rightStationId, nameKo: rightName);
}

NearbyAdjacentStationIdentity? _neighbor({
  required String? stationId,
  required String? nameKo,
}) {
  if (stationId == null || nameKo == null || nameKo.isEmpty) {
    return null;
  }
  return (stationId: stationId, nameKo: nameKo);
}
