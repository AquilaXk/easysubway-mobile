import '../../../generated/journey_v3/journey_v3_contract.dart';
import 'transfer_guide.dart';

/// [journey]의 [legIndex]번 leg가 두 탑승 사이의 환승이면 그 키를 만든다.
/// 환승이 아니거나 앞뒤가 탑승이 아니거나 정차역이 둘 미만이면 null이다.
/// 데이터 계약은 역 안 환승(`fromStationId == toStationId`)만 다루므로 역 밖 환승도 null이다.
TransferGuideKey? transferGuideKeyAt(Journey journey, int legIndex) {
  final legs = journey.legs;
  if (legIndex < 1 || legIndex >= legs.length - 1) return null;
  final transfer = legs[legIndex];
  final previous = legs[legIndex - 1];
  final next = legs[legIndex + 1];
  if (transfer is! JourneyTransferLeg ||
      transfer.fromStationId != transfer.toStationId ||
      previous is! JourneyRideLeg ||
      next is! JourneyRideLeg) {
    return null;
  }
  if (previous.stops.length < 2 || next.stops.length < 2) return null;
  return TransferGuideKey(
    stationId: transfer.fromStationId,
    fromLineId: previous.lineId,
    fromPrevStationId: previous.stops[previous.stops.length - 2].stationId,
    toLineId: next.lineId,
    toNextStationId: next.stops[1].stationId,
  );
}
