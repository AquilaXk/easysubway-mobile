import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/features/favorites/data/drift_favorite_repositories.dart';
import 'package:easysubway_mobile/features/preferences/data/drift_notification_settings_repository.dart';
import 'package:easysubway_mobile/features/search_history/data/drift_search_history_repository.dart';
import 'package:easysubway_mobile/features/account/user_data_deletion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 역 즐겨찾기는 user DB에 저장하고 catalog DB 정보로 목록을 만든다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteStation('station-sangnoksu');
    final favorites = await repository.listFavoriteStations();

    expect(saved.stationId, 'station-sangnoksu');
    expect(favorites.single.nameKo, '상록수');
    expect(favorites.single.lines.single.name, '수도권 4호선');

    await repository.removeFavoriteStation('station-sangnoksu');

    expect(await repository.listFavoriteStations(), isEmpty);
  });

  test('호선 단위 즐겨찾기는 lineId로 저장하고 해당 호선만 해제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteStation(
      'station-sangnoksu',
      lineId: 'seoul-4',
    );
    expect(saved.stationId, 'station-sangnoksu');
    expect(saved.lineId, 'seoul-4');

    final favorites = await repository.listFavoriteStations();
    expect(favorites.single.lineId, 'seoul-4');

    await repository.removeFavoriteStation(
      'station-sangnoksu',
      lineId: 'seoul-4',
    );
    expect(await repository.listFavoriteStations(), isEmpty);
  });

  test('레거시 line_id와 호선 단위 행이 공존하면 레거시는 목록에서 제외한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    await repository.saveFavoriteStation('station-sangnoksu');
    await repository.saveFavoriteStation(
      'station-sangnoksu',
      lineId: 'seoul-4',
    );

    final favorites = await repository.listFavoriteStations();
    expect(favorites, hasLength(1));
    expect(favorites.single.lineId, 'seoul-4');
  });

  test('레거시 역 전체 즐겨찾기에서 한 호선만 해제하면 나머지로 펼친다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    await repository.saveFavoriteStation('station-sadang');
    await repository.removeFavoriteStation('station-sadang', lineId: 'seoul-2');

    final favorites = await repository.listFavoriteStations();
    expect(favorites.map((favorite) => favorite.lineId), ['seoul-4']);
  });

  test('흡수 station ID 즐겨찾기는 대표 ID로 이관한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sangnoksu', 'station-sangnoksu-old', 'station-sangnoksu-old')
    ''');
    await userDatabase.customStatement(
      'INSERT INTO favorite_stations (station_id, added_at) VALUES (?, ?), (?, ?)',
      [
        'station-sangnoksu-old',
        DateTime.utc(2026, 7, 13).millisecondsSinceEpoch ~/ 1000,
        'station-sangnoksu',
        DateTime.utc(2026, 7, 14).millisecondsSinceEpoch ~/ 1000,
      ],
    );
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final favorites = await repository.listFavoriteStations();
    final stored = await userDatabase
        .customSelect('SELECT station_id FROM favorite_stations')
        .getSingle();

    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(stored.read<String>('station_id'), 'station-sangnoksu');
  });

  test('흡수 station ID로 저장해도 대표 ID 즐겨찾기만 남긴다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sangnoksu', 'station-sangnoksu-old', 'station-sangnoksu-old')
    ''');
    final repository = DriftFavoriteStationRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteStation('station-sangnoksu-old');

    expect(saved.stationId, 'station-sangnoksu');
    final stored = await userDatabase
        .customSelect('SELECT station_id FROM favorite_stations')
        .getSingle();
    expect(stored.read<String>('station_id'), 'station-sangnoksu');
  });

  test('로컬 시설 즐겨찾기는 데이터팩 catalog 정보와 user DB 보관 시간을 조합한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insert(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: 'facility-sangnoksu-elevator-1',
            stationId: 'station-sangnoksu',
            addedAt: DateTime.utc(2026, 6, 19, 9),
          ),
        );
    final repository = DriftFavoriteFacilityRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final favorites = await repository.listFavoriteFacilities();

    expect(favorites.single.facilityId, 'facility-sangnoksu-elevator-1');
    expect(favorites.single.stationNameKo, '상록수');
    expect(favorites.single.name, '1번 출구 엘리베이터');
    expect(favorites.single.verificationStatusLabel, '');
    expect(favorites.single.lastUpdatedAt, '2026-06-19');
    expect(favorites.single.addedAt, '2026-06-19T09:00:00.000Z');
  });

  test('로컬 시설 즐겨찾기는 시설 field 검증 시각을 최근 확인일로 쓴다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insert(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: 'facility-sangnoksu-accessible-toilet-1',
            stationId: 'station-sangnoksu',
            addedAt: DateTime.utc(2026, 6, 19, 9),
          ),
        );
    final repository = DriftFavoriteFacilityRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final favorites = await repository.listFavoriteFacilities();

    expect(
      favorites.single.facilityId,
      'facility-sangnoksu-accessible-toilet-1',
    );
    expect(favorites.single.verificationStatusLabel, '');
    expect(favorites.single.lastUpdatedAt, '2025-06-01');
  });

  test('로컬 시설 즐겨찾기는 시설 id로 저장하고 삭제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteFacilityRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );

    final saved = await repository.saveFavoriteFacility(
      'facility-sangnoksu-elevator-1',
    );
    final favorites = await repository.listFavoriteFacilities();

    expect(saved.facilityId, 'facility-sangnoksu-elevator-1');
    expect(favorites.single.name, '1번 출구 엘리베이터');

    await repository.removeFavoriteFacility('facility-sangnoksu-elevator-1');

    expect(await repository.listFavoriteFacilities(), isEmpty);
  });

  test(
    'legacy 즐겨찾기 경로 snapshot의 raw bytes와 canonical ID를 읽기만 해도 바꾸지 않는다',
    () async {
      final catalogDatabase = CatalogDatabase.memory();
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(catalogDatabase.close);
      addTearDown(userDatabase.close);
      await catalogDatabase.seedBaselineIfEmpty();
      const routeId = 'server-route-1';
      const rawSnapshot =
          '{"routeSearchId":"server-route-1","originStationId":"station-sangnoksu","originStationName":"상록수","destinationStationId":"station-sadang","destinationStationName":"사당","mobilityType":"SENIOR","status":"FOUND","lineId":"seoul-4","lineName":"수도권 4호선","score":92,"createdAt":"2026-06-19T09:00:00.000Z","transportScope":"SUBWAY"}';
      await userDatabase.transaction(() async {
        await userDatabase
            .into(userDatabase.favoriteRoutes)
            .insert(
              user_db.FavoriteRoutesCompanion.insert(
                routeId: routeId,
                originStationId: 'station-sangnoksu',
                destinationStationId: 'station-sadang',
                mobilityProfile: 'SENIOR',
                addedAt: DateTime.utc(2026, 6, 19, 9),
              ),
            );
        await userDatabase
            .into(userDatabase.appPreferences)
            .insert(
              user_db.AppPreferencesCompanion.insert(
                key: 'favorite_route_snapshot:$routeId',
                value: rawSnapshot,
                updatedAt: DateTime.utc(2026, 6, 19, 9),
              ),
            );
      });
      final repository = DriftFavoriteRouteRepository(
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
      );

      final favorites = await repository.listFavoriteRoutes();
      final stored = await userDatabase
          .customSelect(
            'SELECT value FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:$routeId'),
            ],
          )
          .getSingle();

      expect(favorites.single.favoriteRouteId, routeId);
      expect(favorites.single.routeSearchId, routeId);
      expect(favorites.single.originStationName, '상록수');
      expect(favorites.single.destinationStationName, '사당');
      expect(favorites.single.mobilityType, 'SENIOR');
      expect(favorites.single.status, 'RESEARCH_REQUIRED');
      expect(favorites.single.needsResearch, isTrue);
      expect(favorites.single.score, 0);
      expect(favorites.single.lineId, isEmpty);
      expect(favorites.single.lineName, isEmpty);
      expect(favorites.single.etaSource, isEmpty);
      expect(stored.read<String>('value'), rawSnapshot);
    },
  );

  test('persisted local 경로 행과 snapshot은 목록 조회에서 함께 삭제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-stale-route',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-stale-route',
              value: '{"legacy":true}',
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });

    expect(await repository.listFavoriteRoutes(), isEmpty);
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:local-stale-route'),
            ],
          )
          .get(),
      isEmpty,
    );
  });

  test('정규 저장 ID 뒤에 숨은 local 경로 snapshot도 함께 삭제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    const storedRouteId = 'rc:v1:previously-local-route';
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: storedRouteId,
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:$storedRouteId',
              value:
                  '{"routeSearchId":"local-stale-route","originStationId":"station-sangnoksu","destinationStationId":"station-sadang"}',
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });

    expect(await repository.listFavoriteRoutes(), isEmpty);
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id = ?',
            variables: [Variable.withString(storedRouteId)],
          )
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:$storedRouteId'),
            ],
          )
          .get(),
      isEmpty,
    );
  });

  test('기존 candidate 대상은 보존하고 최종 추가 시각 순으로 정렬한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    const candidateId = 'persisted-candidate-route';
    const targetSnapshot =
        '{"routeSearchId":"target-route","originStationId":"station-sangnoksu","originStationName":"대상 출발","destinationStationId":"station-sadang","destinationStationName":"대상 도착","mobilityType":"SENIOR","status":"FOUND","score":99,"createdAt":"2026-07-02T00:00:00.000Z","steps":[]}';
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: candidateId,
              originStationId: 'target-origin',
              destinationStationId: 'target-destination',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:$candidateId',
              value: targetSnapshot,
              updatedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'middle-route',
              originStationId: 'middle-origin',
              destinationStationId: 'middle-destination',
              mobilityProfile: 'STANDARD',
              addedAt: DateTime.utc(2026, 7, 2),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:middle-route',
              value:
                  '{"routeSearchId":"middle-route","originStationId":"middle-origin","originStationName":"중간 출발","destinationStationId":"middle-destination","destinationStationName":"중간 도착","mobilityType":"STANDARD","status":"FOUND","score":50,"createdAt":"2026-07-02T00:00:00.000Z","steps":[]}',
              updatedAt: DateTime.utc(2026, 7, 2),
            ),
          );
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-duplicate',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'SENIOR',
              addedAt: DateTime.utc(2026, 7, 3),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-duplicate',
              value: jsonEncode({
                'originStationId': 'station-sangnoksu',
                'originStationName': '레거시 출발',
                'destinationStationId': 'station-sadang',
                'destinationStationName': '레거시 도착',
                'mobilityType': 'SENIOR',
                'status': 'FOUND',
                'score': 1,
                'createdAt': '2026-07-01T00:00:00.000Z',
                'objective': 'FASTEST',
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'lineId': 'seoul-4',
                    'serviceClass': 'SUBWAY',
                    'servicePattern': 'LOCAL',
                  },
                ],
              }),
              updatedAt: DateTime.utc(2026, 7, 1),
            ),
          );
    });

    final favorites = await repository.listFavoriteRoutes();

    expect(favorites.map((favorite) => favorite.favoriteRouteId), [
      'middle-route',
      candidateId,
    ]);
    expect(favorites.last.addedAt, '2026-07-01T00:00:00.000Z');
    expect(favorites.last.originStationName, 'target-origin');
    expect(favorites.last.destinationStationName, 'target-destination');
    expect(favorites.last.mobilityType, 'WHEELCHAIR');
    expect(favorites.last.status, 'RESEARCH_REQUIRED');
    expect(favorites.last.needsResearch, isTrue);
    expect(favorites.last.score, 0);
    expect(favorites.last.lineId, isEmpty);
    expect(favorites.last.lineName, isEmpty);
    expect(favorites.last.etaSource, isEmpty);
    final target = await userDatabase
        .customSelect(
          'SELECT value, CAST(updated_at AS INTEGER) AS updated_at_value FROM app_preferences WHERE key = ?',
          variables: [
            Variable.withString('favorite_route_snapshot:$candidateId'),
          ],
        )
        .getSingle();
    expect(target.read<String>('value'), targetSnapshot);
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id = ?',
            variables: [Variable.withString('local-duplicate')],
          )
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:local-duplicate'),
            ],
          )
          .get(),
      isEmpty,
    );
  });

  test('형식이 손상된 local snapshot도 route row와 함께 삭제한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    const snapshot =
        '{"querySnapshot":"not-a-map","originStationId":"station-sangnoksu","originStationName":"상록수","destinationStationId":"station-sadang","destinationStationName":"사당","mobilityType":"SENIOR","status":"FOUND","score":1,"createdAt":"2026-07-01T00:00:00.000Z","steps":[{"stepType":"RIDE","fromStationId":"station-sangnoksu","toStationId":"station-sadang"}]}';
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-corrupt-query-snapshot',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'SENIOR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-corrupt-query-snapshot',
              value: snapshot,
              updatedAt: DateTime.utc(2026, 7),
            ),
          );
    });

    expect(await repository.listFavoriteRoutes(), isEmpty);
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString(
                'favorite_route_snapshot:local-corrupt-query-snapshot',
              ),
            ],
          )
          .get(),
      isEmpty,
    );
  });

  test('손상된 기존 candidate 대상 fallback은 대상 행으로 제거할 수 있다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    const candidateId = 'persisted-candidate-malformed';
    await userDatabase.transaction(() async {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: candidateId,
              originStationId: 'target-origin',
              destinationStationId: 'target-destination',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7, 1),
            ),
          );
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: 'local-newer-duplicate',
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'SENIOR',
              addedAt: DateTime.utc(2026, 7, 2),
            ),
          );
      await userDatabase
          .into(userDatabase.appPreferences)
          .insert(
            user_db.AppPreferencesCompanion.insert(
              key: 'favorite_route_snapshot:local-newer-duplicate',
              value: jsonEncode({
                'originStationId': 'station-sangnoksu',
                'originStationName': '상록수',
                'destinationStationId': 'station-sadang',
                'destinationStationName': '사당',
                'mobilityType': 'SENIOR',
                'status': 'FOUND',
                'score': 1,
                'createdAt': '2026-07-02T00:00:00.000Z',
                'objective': 'FASTEST',
                'steps': [
                  {
                    'stepType': 'RIDE',
                    'fromStationId': 'station-sangnoksu',
                    'toStationId': 'station-sadang',
                    'serviceClass': 'SUBWAY',
                    'servicePattern': 'LOCAL',
                  },
                ],
              }),
              updatedAt: DateTime.utc(2026, 7, 2),
            ),
          );
    });

    final favorite = (await repository.listFavoriteRoutes()).single;

    expect(favorite.favoriteRouteId, candidateId);
    expect(favorite.routeSearchId, candidateId);
    expect(favorite.originStationId, 'target-origin');
    expect(favorite.destinationStationId, 'target-destination');
    expect(favorite.mobilityType, 'WHEELCHAIR');
    expect(favorite.addedAt, '2026-07-01T00:00:00.000Z');
    expect(favorite.needsResearch, isTrue);
    expect(
      await userDatabase
          .customSelect(
            'SELECT route_id FROM favorite_routes WHERE route_id = ?',
            variables: [Variable.withString('local-newer-duplicate')],
          )
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase
          .customSelect(
            'SELECT key FROM app_preferences WHERE key = ?',
            variables: [
              Variable.withString('favorite_route_snapshot:$candidateId'),
            ],
          )
          .get(),
      isEmpty,
    );

    final restarted = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    final reloaded = (await restarted.listFavoriteRoutes()).single;
    expect(reloaded.favoriteRouteId, candidateId);
    expect(reloaded.originStationId, 'target-origin');
    expect(reloaded.destinationStationId, 'target-destination');
    expect(reloaded.mobilityType, 'WHEELCHAIR');
    expect(reloaded.addedAt, '2026-07-01T00:00:00.000Z');
    expect(reloaded.needsResearch, isTrue);

    await restarted.removeFavoriteRoute(reloaded.favoriteRouteId);

    expect(await repository.listFavoriteRoutes(), isEmpty);
  });

  test('어떤 snapshot 형태든 stale local 경로 후보를 복원하거나 표시하지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    await catalogDatabase.customStatement(
      "UPDATE stations SET name_ko = ' 상록수 ' WHERE id = 'station-sangnoksu'",
    );
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    for (final fixture in [
      ('local-missing', null),
      ('local-invalid-json', '{'),
      ('local-invalid-shape', '[]'),
      (
        'local-missing-objective',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'mobilityPreset': 'STEP_FREE',
          'constraintMode': 'STRICT_STEP_FREE',
          'transportScope': 'SUBWAY',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
              'lineId': 'seoul-4',
              'serviceClass': 'SUBWAY',
              'servicePattern': 'LOCAL',
            },
          ],
        }),
      ),
      (
        'local-waypoint',
        jsonEncode({
          'originStationName': '저장 출발',
          'destinationStationName': '저장 도착',
          'waypointStationId': 'station-seonjeongneung',
          'transportScope': 'SUBWAY_AND_ITX_CHEONGCHUN',
        }),
      ),
      (
        'local-query-mismatch',
        jsonEncode({
          'originStationId': 'station-other',
          'originStationName': '다른 출발',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-other',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-query-snapshot-mismatch',
        jsonEncode({
          'querySnapshot': {
            'originStationId': 'station-sangnoksu',
            'destinationStationId': 'station-sadang',
            'mobilityType': 'WHEELCHAIR',
            'constraintMode': 'STRICT_STEP_FREE',
            'transportScope': 'SUBWAY',
            'objective': 'FASTEST',
          },
          'originStationId': 'station-other',
          'originStationName': '다른 출발',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-waypoint-number',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'waypointStationId': 1,
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-invalid-step-type',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'steps': [
            {
              'stepType': 'GARBAGE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
            },
          ],
        }),
      ),
      (
        'local-invalid-ride-service',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'objective': 'FASTEST',
          'steps': [
            {
              'stepType': 'RIDE',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
              'serviceClass': 'BUS',
              'servicePattern': 'RAPID',
            },
          ],
        }),
      ),
      (
        'local-non-ride-service',
        jsonEncode({
          'originStationId': 'station-sangnoksu',
          'originStationName': '상록수',
          'destinationStationId': 'station-sadang',
          'destinationStationName': '사당',
          'mobilityType': 'WHEELCHAIR',
          'status': 'FOUND',
          'score': 1,
          'createdAt': '2026-07-01T00:00:00.000Z',
          'objective': 'FASTEST',
          'steps': [
            {
              'stepType': 'WALK',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sadang',
              'serviceClass': 'SUBWAY',
              'servicePattern': 'LOCAL',
            },
          ],
        }),
      ),
    ]) {
      await userDatabase
          .into(userDatabase.favoriteRoutes)
          .insert(
            user_db.FavoriteRoutesCompanion.insert(
              routeId: fixture.$1,
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityProfile: 'WHEELCHAIR',
              addedAt: DateTime.utc(2026, 7),
            ),
          );
      if (fixture.$2 case final String value) {
        await userDatabase
            .into(userDatabase.appPreferences)
            .insert(
              user_db.AppPreferencesCompanion.insert(
                key: 'favorite_route_snapshot:${fixture.$1}',
                value: value,
                updatedAt: DateTime.utc(2026, 7),
              ),
            );
      }
    }

    expect(await repository.listFavoriteRoutes(), isEmpty);
    expect(
      await userDatabase
          .customSelect('SELECT route_id FROM favorite_routes')
          .get(),
      isEmpty,
    );
    expect(
      await userDatabase.customSelect('SELECT key FROM app_preferences').get(),
      isEmpty,
    );
  });

  test('손상된 레거시 행 하나가 정상 즐겨찾기 목록을 가리지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    final repository = DriftFavoriteRouteRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    await userDatabase
        .into(userDatabase.favoriteRoutes)
        .insert(
          user_db.FavoriteRoutesCompanion.insert(
            routeId: 'bad',
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityProfile: 'SENIOR',
            addedAt: DateTime.utc(2026, 7),
          ),
        );
    await userDatabase
        .into(userDatabase.appPreferences)
        .insert(
          user_db.AppPreferencesCompanion.insert(
            key: 'favorite_route_snapshot:bad',
            value: '[]',
            updatedAt: DateTime.utc(2026, 7),
          ),
        );
    await userDatabase
        .into(userDatabase.favoriteRoutes)
        .insert(
          user_db.FavoriteRoutesCompanion.insert(
            routeId: 'good',
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityProfile: 'SENIOR',
            addedAt: DateTime.utc(2026, 7, 1),
          ),
        );
    await userDatabase
        .into(userDatabase.appPreferences)
        .insert(
          user_db.AppPreferencesCompanion.insert(
            key: 'favorite_route_snapshot:good',
            value:
                '{"routeSearchId":"good","originStationId":"station-sangnoksu","originStationName":"상록수","destinationStationId":"station-sadang","destinationStationName":"사당","mobilityType":"SENIOR","status":"FOUND","lineId":"","lineName":"","score":1,"createdAt":"2026-07-01T00:00:00.000Z"}',
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        );
    final favorites = await repository.listFavoriteRoutes();

    expect(favorites, hasLength(2));
    expect(
      favorites.any((favorite) => favorite.favoriteRouteId == 'good'),
      isTrue,
    );
    expect(
      favorites
          .singleWhere((favorite) => favorite.favoriteRouteId == 'bad')
          .needsResearch,
      isTrue,
    );
  });

  test('로컬 알림 설정과 최근 검색은 app_preferences와 search_history에 보관한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final notificationRepository = DriftNotificationSettingsRepository(
      userDatabase: userDatabase,
    );
    final searchHistoryRepository = DriftSearchHistoryRepository(
      userDatabase: userDatabase,
      maxEntries: 2,
    );

    final defaultSettings = await notificationRepository
        .getNotificationSettings();
    final savedSettings = await notificationRepository.saveNotificationSettings(
      defaultSettings.copyWith(
        favoriteStationFacilityAlerts: true,
        favoriteRouteFacilityAlerts: true,
      ),
    );
    await searchHistoryRepository.recordSearch(' 상록수 ', region: '수도권');
    await searchHistoryRepository.recordSearch('사당', region: '수도권');
    await searchHistoryRepository.recordSearch('상록수', region: '수도권');

    expect(defaultSettings.userId, 'local-user');
    expect(savedSettings.favoriteStationFacilityAlerts, isTrue);
    expect(
      (await notificationRepository.getNotificationSettings())
          .favoriteRouteFacilityAlerts,
      isTrue,
    );
    expect(await searchHistoryRepository.listRecentQueries(), ['상록수', '사당']);
  });

  test('앱 기본 의존성은 user DB가 있으면 개인 데이터 API를 만들지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      enablePushNotifications: false,
    );

    expect(
      dependencies.favoriteRepository,
      isA<DriftFavoriteStationRepository>(),
    );
    expect(
      dependencies.favoriteFacilityRepository,
      isA<DriftFavoriteFacilityRepository>(),
    );
    expect(
      dependencies.favoriteRouteRepository,
      isA<DriftFavoriteRouteRepository>(),
    );
    expect(
      dependencies.userDataDeletionRepository,
      isA<UserDataDeletionLocalRepository>(),
    );
  });

  test('즐겨찾기 저장과 조회는 user DB만 사용한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      enablePushNotifications: false,
    );

    await dependencies.favoriteRepository!.saveFavoriteStation(
      'station-sangnoksu',
    );
    await dependencies.favoriteRepository!.listFavoriteStations();

    expect(
      dependencies.userDataDeletionRepository,
      isA<UserDataDeletionLocalRepository>(),
    );
  });
}
