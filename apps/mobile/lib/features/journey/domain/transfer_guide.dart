/// 환승 이동 안내 단계를 찾는 키. 데이터팩 `transfer_guide_steps`의 키 열과 같다.
final class TransferGuideKey {
  const TransferGuideKey({
    required this.stationId,
    required this.fromLineId,
    required this.fromPrevStationId,
    required this.toLineId,
    required this.toNextStationId,
  });

  /// 환승 leg의 `fromStationId`.
  final String stationId;

  /// 직전 탑승 leg의 `lineId`.
  final String fromLineId;

  /// 직전 탑승의 끝에서 두 번째 정차역(내리기 직전에 지난 역).
  final String fromPrevStationId;

  /// 다음 탑승 leg의 `lineId`.
  final String toLineId;

  /// 다음 탑승의 둘째 정차역(탄 뒤 첫 번째로 지나는 역).
  final String toNextStationId;

  @override
  bool operator ==(Object other) =>
      other is TransferGuideKey &&
      other.stationId == stationId &&
      other.fromLineId == fromLineId &&
      other.fromPrevStationId == fromPrevStationId &&
      other.toLineId == toLineId &&
      other.toNextStationId == toNextStationId;

  @override
  int get hashCode => Object.hash(
    stationId,
    fromLineId,
    fromPrevStationId,
    toLineId,
    toNextStationId,
  );
}

/// 환승 이동 안내 문장의 출처 표기(데이터팩 `transfer_guide_sources`).
final class TransferGuideSource {
  const TransferGuideSource({
    required this.sourceSnapshotId,
    required this.datasetLabel,
    required this.attribution,
  });

  final String sourceSnapshotId;
  final String datasetLabel;
  final String attribution;
}

abstract interface class TransferGuideRepository {
  /// 환승 이동 안내 단계 문장을 `step_order` 순서로, 원문 그대로 돌려준다.
  /// 행이 없거나 데이터팩에 표가 없으면 빈 목록이다.
  Future<List<String>> loadSteps(TransferGuideKey key);

  /// 환승 이동 안내의 출처 표기. 행이 없거나 표가 없으면 빈 목록이다.
  Future<List<TransferGuideSource>> loadSources();
}
