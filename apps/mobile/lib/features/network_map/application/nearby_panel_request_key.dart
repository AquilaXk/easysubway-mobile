/// Nearby realtime/timetable 요청의 immutable identity.
///
/// Station, line, generation이 모두 현재 값과 같을 때만 늦은 async 응답을
/// 적용할 수 있다. Screen lifecycle과 panel visibility는 호출부가 별도로 검사한다.
class NearbyPanelRequestKey {
  const NearbyPanelRequestKey({
    required this.stationId,
    required this.lineId,
    required this.generation,
  });

  final String stationId;
  final String lineId;
  final int generation;

  bool matches({
    required String? stationId,
    required String? lineId,
    required int generation,
  }) {
    return this.stationId == stationId &&
        this.lineId == lineId &&
        this.generation == generation;
  }
}
