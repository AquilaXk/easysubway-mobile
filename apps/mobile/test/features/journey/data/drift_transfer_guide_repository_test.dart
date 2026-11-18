import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/journey/data/drift_transfer_guide_repository.dart';
import 'package:easysubway_mobile/features/journey/domain/transfer_guide.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = TransferGuideKey(
  stationId: 's-gotermi',
  fromLineId: 'l-9',
  fromPrevStationId: 's-sinbanpo',
  toLineId: 'l-3',
  toNextStationId: 's-jamwon',
);

// data 레포 catalog-schema.sql의 두 테이블과 같은 모양(외래 키 제외).
const _createTables = [
  '''
  CREATE TABLE transfer_guide_sources (
    source_snapshot_id TEXT NOT NULL PRIMARY KEY,
    dataset_label TEXT NOT NULL,
    attribution TEXT NOT NULL,
    raw_sha256 TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE transfer_guide_steps (
    station_id TEXT NOT NULL,
    from_line_id TEXT NOT NULL,
    from_prev_station_id TEXT NOT NULL,
    to_line_id TEXT NOT NULL,
    to_next_station_id TEXT NOT NULL,
    step_order INTEGER NOT NULL,
    detail TEXT NOT NULL,
    source_snapshot_id TEXT NOT NULL,
    PRIMARY KEY (station_id, from_line_id, from_prev_station_id, to_line_id, to_next_station_id, step_order)
  )
  ''',
];

Future<void> _insertStep(
  CatalogDatabase db,
  TransferGuideKey key,
  int order,
  String detail,
) => db.customStatement(
  'INSERT INTO transfer_guide_steps VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  [
    key.stationId,
    key.fromLineId,
    key.fromPrevStationId,
    key.toLineId,
    key.toNextStationId,
    order,
    detail,
    'snap-1',
  ],
);

void main() {
  late CatalogDatabase database;

  setUp(() async {
    database = CatalogDatabase.memory();
    await database.seedBaselineIfEmpty();
  });

  tearDown(() async {
    await database.close();
  });

  group('테이블이 있는 데이터팩', () {
    setUp(() async {
      for (final statement in _createTables) {
        await database.customStatement(statement);
      }
      await database.customStatement(
        "INSERT INTO transfer_guide_sources VALUES ('snap-1', '국토교통부 철도역 환승 이동경로', "
        "'국토교통부 철도역 환승 이동경로(공공데이터포털 15130556)', '${'a' * 64}')",
      );
      // 일부러 step_order와 다른 순서로 넣어 정렬을 확인한다.
      await _insertStep(database, _key, 3, '3) 지하 2층으로 이동');
      await _insertStep(database, _key, 1, '1) 사평 방면 승강장');
      await _insertStep(database, _key, 2, '2) 엘리베이터 이용');
    });

    test('step_order 순서로 detail을 원문 그대로 돌려준다', () async {
      final steps = await DriftTransferGuideRepository(
        database: database,
      ).loadSteps(_key);

      expect(steps, ['1) 사평 방면 승강장', '2) 엘리베이터 이용', '3) 지하 2층으로 이동']);
    });

    test('키가 하나라도 다르면 행이 없다', () async {
      final repository = DriftTransferGuideRepository(database: database);
      const other = TransferGuideKey(
        stationId: 's-gotermi',
        fromLineId: 'l-9',
        fromPrevStationId: 's-sinbanpo',
        toLineId: 'l-3',
        toNextStationId: 's-gyodae',
      );

      expect(await repository.loadSteps(other), isEmpty);
    });

    test('앞뒤 공백·줄바꿈을 포함한 원문도 고치지 않는다', () async {
      const spaced = TransferGuideKey(
        stationId: 's-x',
        fromLineId: 'l-1',
        fromPrevStationId: 's-a',
        toLineId: 'l-2',
        toNextStationId: 's-b',
      );
      await _insertStep(database, spaced, 1, '  1) 하차  \n');

      expect(
        await DriftTransferGuideRepository(
          database: database,
        ).loadSteps(spaced),
        ['  1) 하차  \n'],
      );
    });

    test('출처 표기를 돌려준다', () async {
      final sources = await DriftTransferGuideRepository(
        database: database,
      ).loadSources();

      expect(sources, hasLength(1));
      expect(sources.single.datasetLabel, '국토교통부 철도역 환승 이동경로');
      expect(sources.single.attribution, '국토교통부 철도역 환승 이동경로(공공데이터포털 15130556)');
    });
  });

  group('테이블이 없는 이전 데이터팩', () {
    test('단계 조회는 행 없음으로 본다', () async {
      expect(
        await DriftTransferGuideRepository(database: database).loadSteps(_key),
        isEmpty,
      );
    });

    test('출처 조회도 행 없음으로 본다', () async {
      expect(
        await DriftTransferGuideRepository(database: database).loadSources(),
        isEmpty,
      );
    });
  });
}
