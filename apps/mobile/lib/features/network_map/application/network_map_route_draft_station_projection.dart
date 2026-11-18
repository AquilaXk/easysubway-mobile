import '../../route_draft/domain/route_draft.dart';
import '../domain/network_map_models.dart';

RouteDraftStation networkMapRouteDraftStation(
  NetworkMapStation station,
  NetworkMapData? data,
) {
  NetworkMapLine? line;
  final lineId = station.lineId.trim();
  if (data != null && lineId.isNotEmpty) {
    for (final candidate in data.lines) {
      if (candidate.id == lineId) {
        line = candidate;
        break;
      }
    }
  }
  return RouteDraftStation(
    id: station.id,
    nameKo: station.nameKo,
    lineId: lineId,
    lineName: line?.name ?? '',
    lineColor: line?.color ?? '',
    stationCode: station.stationCode,
  );
}
