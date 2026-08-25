import 'package:flutter_test/flutter_test.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';

void main() {
  late CatalogDatabase catalogDatabase;
  late UserDatabase userDatabase;
  late NextTrainWidgetRepository repository;

  setUp(() async {
    catalogDatabase = CatalogDatabase.memory();
    userDatabase = UserDatabase.memory();
    await catalogDatabase.customSelect('SELECT 1').get();
    await userDatabase.customSelect('SELECT 1').get();
    repository = NextTrainWidgetRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      timetableRepository: _RecordingServerTimetableFake(),
    );
    await _seedStations(catalogDatabase);
  });

  tearDown(() async {
    await catalogDatabase.close();
    await userDatabase.close();
  });

  test('선택 목록은 서버 시간표와 독립적으로 catalog station-line을 사용한다', () async {
    await _favorite(userDatabase, 'station-sadang');

    final selections = await repository.availableSelections();

    expect(selections.map((item) => '${item.stationId}|${item.lineId}'), [
      'station-sadang|seoul-2',
      'station-sadang|seoul-4',
    ]);
  });

  test('위젯은 NEXT_DEPARTURES 서버 결과를 한 번만 양방향으로 표시한다', () async {
    final now = DateTime.utc(2026, 8, 11, 15, 50);
    final fake = _RecordingServerTimetableFake(
      timetable: _serverTimetable(
        stationId: _sadangLine4.stationId,
        lineId: _sadangLine4.lineId,
        departureAt: DateTime.utc(2026, 8, 11, 16),
      ),
    );
    final serverRepository = NextTrainWidgetRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      timetableRepository: fake,
    );

    final data = await serverRepository.load(_sadangLine4, now);

    expect(fake.nextRequests, 1);
    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.directions.map((item) => item.name), ['상록수 방면', '사당 방면']);
    expect(data.directions.first.departureLabel, '01:00');
  });

  test('서버 시간표 실패는 previous data 없이 unavailable이다', () async {
    final serverRepository = NextTrainWidgetRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      timetableRepository: _RecordingServerTimetableFake(
        error: StateError('unavailable'),
      ),
    );

    final data = await serverRepository.load(
      _sadangLine4,
      DateTime.utc(2026, 8, 11),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('흡수 station ID 즐겨찾기도 대표 station-line으로 선택한다', () async {
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sadang', 'station-sadang-old', 'station-sadang-old')
    ''');
    await _favorite(userDatabase, 'station-sadang-old');

    final selections = await repository.availableSelections();

    expect(selections.map((item) => '${item.stationId}|${item.lineId}'), [
      'station-sadang|seoul-2',
      'station-sadang|seoul-4',
    ]);
  });

  test('흡수 station ID로 저장된 위젯 선택도 대표 ID로 시간표를 조회한다', () async {
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sadang', 'station-sadang-old', 'station-sadang-old')
    ''');
    final serverRepository = NextTrainWidgetRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      timetableRepository: _RecordingServerTimetableFake(
        timetable: _serverTimetable(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          departureAt: DateTime.utc(2026, 7, 9, 20),
        ),
      ),
    );

    final data = await serverRepository.load(
      const WidgetStationSelection(
        stationId: 'station-sadang-old',
        lineId: 'seoul-4',
        stationName: '사당',
        lineName: '수도권 4호선',
      ),
      DateTime.utc(2026, 7, 9, 20),
    );

    expect(data.selection.stationId, 'station-sadang');
    expect(data.status, NextTrainWidgetStatus.available);
  });
}

const _sadangLine4 = WidgetStationSelection(
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  stationName: '사당',
  lineName: '수도권 4호선',
);

Future<void> _seedStations(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO operators (id, name_ko, name_en)
    VALUES ('seoul-metro', '서울교통공사', 'Seoul Metro')
  ''');
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES
      ('seoul-2', 'seoul-metro', '수도권 2호선', 'Line 2', '#00A84D'),
      ('seoul-4', 'seoul-metro', '수도권 4호선', 'Line 4', '#00A5DE')
  ''');
  await database.customStatement('''
    INSERT INTO stations (
      id, name_ko, name_en, name_sub, normalized_name, region,
      data_quality_level, data_source_type
    ) VALUES ('station-sadang', '사당', 'Sadang', '', '사당', '수도권',
      'LEVEL_2', 'OFFICIAL_FILE')
  ''');
  await database.customStatement('''
    INSERT INTO station_lines (
      station_id, line_id, station_code, line_sequence, platform_info
    ) VALUES
      ('station-sadang', 'seoul-2', '226', 26, '내선 / 외선'),
      ('station-sadang', 'seoul-4', '433', 28, '당고개 / 오이도')
  ''');
}

Future<void> _favorite(UserDatabase database, String stationId) async {
  await database.customStatement(
    'INSERT INTO favorite_stations (station_id, added_at) VALUES (?, ?)',
    [stationId, DateTime.utc(2026, 7, 10).millisecondsSinceEpoch ~/ 1000],
  );
}

class _RecordingServerTimetableFake implements StationTimetableRepository {
  _RecordingServerTimetableFake({this.timetable, this.error});

  final StationTimetable? timetable;
  final Object? error;
  int nextRequests = 0;

  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async {
    nextRequests++;
    if (error != null) throw error!;
    return timetable!;
  }

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) => throw UnimplementedError();

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) => throw UnimplementedError();
}

StationTimetable _serverTimetable({
  required String stationId,
  required String lineId,
  required DateTime departureAt,
}) => StationTimetable(
  stationId: stationId,
  lineId: lineId,
  dayType: StationTimetableDayType.weekday,
  directions: [
    StationTimetableDirection(
      name: '상록수 방면',
      departures: [
        StationTimetableDeparture(
          directionName: '상록수 방면',
          seconds: 90000,
          departureAt: departureAt,
        ),
      ],
    ),
    StationTimetableDirection(
      name: '사당 방면',
      departures: [
        StationTimetableDeparture(
          directionName: '사당 방면',
          seconds: 90300,
          departureAt: departureAt.add(const Duration(minutes: 5)),
        ),
      ],
    ),
  ],
);
