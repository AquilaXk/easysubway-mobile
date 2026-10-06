import 'package:drift/drift.dart';

import '../../../core/database/catalog/catalog_database.dart';
import '../domain/transfer_guide.dart';

/// 설치된 데이터팩의 `transfer_guide_steps`·`transfer_guide_sources`를 읽는다.
/// 이 표가 생기기 전의 데이터팩에는 표가 없으며, 그때는 행 없음으로 본다.
class DriftTransferGuideRepository implements TransferGuideRepository {
  const DriftTransferGuideRepository({required this.database});

  final CatalogDatabase database;

  @override
  Future<List<String>> loadSteps(TransferGuideKey key) async {
    if (!await _hasTable('transfer_guide_steps')) return const [];
    final rows = await database
        .customSelect(
          '''
          SELECT detail FROM transfer_guide_steps
          WHERE station_id = ? AND from_line_id = ?
            AND from_prev_station_id = ? AND to_line_id = ?
            AND to_next_station_id = ?
          ORDER BY step_order
          ''',
          variables: [
            Variable<String>(key.stationId),
            Variable<String>(key.fromLineId),
            Variable<String>(key.fromPrevStationId),
            Variable<String>(key.toLineId),
            Variable<String>(key.toNextStationId),
          ],
        )
        .get();
    return List.unmodifiable([
      for (final row in rows) row.read<String>('detail'),
    ]);
  }

  @override
  Future<List<TransferGuideSource>> loadSources() async {
    if (!await _hasTable('transfer_guide_sources')) return const [];
    final rows = await database.customSelect('''
          SELECT source_snapshot_id, dataset_label, attribution
          FROM transfer_guide_sources
          ORDER BY source_snapshot_id
          ''').get();
    return List.unmodifiable([
      for (final row in rows)
        TransferGuideSource(
          sourceSnapshotId: row.read<String>('source_snapshot_id'),
          datasetLabel: row.read<String>('dataset_label'),
          attribution: row.read<String>('attribution'),
        ),
    ]);
  }

  Future<bool> _hasTable(String name) async {
    final row = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(name)],
        )
        .getSingleOrNull();
    return row != null;
  }
}
