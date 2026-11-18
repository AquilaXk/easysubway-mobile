import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/catalog/canonical_station_id.dart';
import '../../../core/database/catalog/catalog_database.dart';
import '../../../core/database/user/user_database.dart' as user_db;
import '../favorite_facility.dart';
import '../../stations/domain/station_models.dart';
import '../../stations/domain/station_line.dart';
import '../../stations/domain/station_repositories.dart';
import '../domain/favorite_route.dart';

const _localUserId = 'local-user';
const _routeSnapshotPrefix = 'favorite_route_snapshot:';
const _sqliteInClauseChunkSize = 500;

class DriftFavoriteStationRepository implements FavoriteStationRepository {
  DriftFavoriteStationRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final user_db.UserDatabase userDatabase;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final favoriteRows = await userDatabase
        .customSelect(
          '''
          SELECT
            station_id,
            line_id,
            CAST(added_at AS INTEGER) AS added_at_value
          FROM favorite_stations
          ORDER BY added_at DESC
          ''',
          readsFrom: {userDatabase.favoriteStations},
        )
        .get();
    if (favoriteRows.isEmpty) {
      return const [];
    }

    final storedIds = <String>{
      for (final row in favoriteRows) row.read<String>('station_id'),
    }.toList(growable: false);
    final canonicalByStoredId = await _resolveCanonicalStationIdsBatch(
      storedIds,
    );

    // 호선 단위 행이 있는 역은 레거시(line_id='') 행을 건너뛰어 중복 노출을 막는다.
    final stationsWithLineScoped = <String>{};
    final pendingMigrations =
        <
          ({
            String storedStationId,
            String canonicalStationId,
            String lineId,
            int addedAt,
          })
        >[];
    final resolvedRows =
        <({String stationId, String favoritedLineId, int addedAt})>[];
    for (final favoriteRow in favoriteRows) {
      final storedStationId = favoriteRow.read<String>('station_id');
      final favoritedLineId = favoriteRow.read<String>('line_id');
      final stationId = canonicalByStoredId[storedStationId];
      if (stationId == null) {
        continue;
      }
      final addedAt = favoriteRow.read<int>('added_at_value');
      if (stationId != storedStationId) {
        pendingMigrations.add((
          storedStationId: storedStationId,
          canonicalStationId: stationId,
          lineId: favoritedLineId,
          addedAt: addedAt,
        ));
      }
      if (favoritedLineId.isNotEmpty) {
        stationsWithLineScoped.add(stationId);
      }
      resolvedRows.add((
        stationId: stationId,
        favoritedLineId: favoritedLineId,
        addedAt: addedAt,
      ));
    }

    if (pendingMigrations.isNotEmpty) {
      await _migrateFavoriteStationIdsBatch(pendingMigrations);
    }

    final uniqueStationIds = <String>{
      for (final resolved in resolvedRows) resolved.stationId,
    }.toList(growable: false);
    final stationMetadataById = await _loadFavoriteStationMetadataBatch(
      uniqueStationIds,
    );

    final favorites = <FavoriteStation>[];
    final seenKeys = <String>{};
    for (final resolved in resolvedRows) {
      final stationId = resolved.stationId;
      final favoritedLineId = resolved.favoritedLineId;
      if (favoritedLineId.isEmpty &&
          stationsWithLineScoped.contains(stationId)) {
        continue;
      }
      final key = favoriteStationLineKey(stationId, favoritedLineId);
      if (!seenKeys.add(key)) {
        continue;
      }
      final metadata = stationMetadataById[stationId];
      if (metadata == null) {
        continue;
      }
      final lines = <StationSearchLine>[];
      for (final line in metadata.lines) {
        // 호선 단위 즐겨찾기는 해당 호선만, 레거시(빈 line_id)는 전 호선.
        if (favoritedLineId.isNotEmpty && line.id != favoritedLineId) {
          continue;
        }
        lines.add(line);
      }
      favorites.add(
        FavoriteStation(
          userId: _localUserId,
          stationId: stationId,
          lineId: favoritedLineId,
          nameKo: metadata.nameKo,
          nameEn: metadata.nameEn,
          region: metadata.region,
          dataQualityLevel: metadata.dataQualityLevel,
          dataSourceType: metadata.dataSourceType,
          lastVerifiedAt: metadata.lastVerifiedAt,
          lines: List.unmodifiable(lines),
          addedAt: _isoFromEpoch(resolved.addedAt),
        ),
      );
    }

    return favorites;
  }

  Future<Map<String, String?>> _resolveCanonicalStationIdsBatch(
    List<String> storedIds,
  ) async {
    final candidatesById = <String, Set<String>>{
      for (final id in storedIds) id: <String>{},
    };
    for (final chunk in _chunkValues(storedIds)) {
      final directRows = await catalogDatabase
          .customSelect(
            'SELECT id FROM stations WHERE id IN (${_sqlPlaceholders(chunk.length)})',
            variables: [for (final id in chunk) Variable.withString(id)],
            readsFrom: {catalogDatabase.stations},
          )
          .get();
      for (final row in directRows) {
        final id = row.read<String>('id');
        candidatesById[id]?.add(id);
      }

      final aliasCandidates = [
        for (final id in chunk)
          if (id.startsWith('station-')) id,
      ];
      if (aliasCandidates.isNotEmpty) {
        final aliasRows = await catalogDatabase
            .customSelect(
              '''
              SELECT sa.alias, sa.station_id
              FROM station_aliases sa
              JOIN stations s ON s.id = sa.station_id
              WHERE sa.alias IN (${_sqlPlaceholders(aliasCandidates.length)})
                AND sa.alias LIKE 'station-%'
              ''',
              variables: [
                for (final id in aliasCandidates) Variable.withString(id),
              ],
              readsFrom: {
                catalogDatabase.stationAliases,
                catalogDatabase.stations,
              },
            )
            .get();
        for (final row in aliasRows) {
          final alias = row.read<String>('alias');
          final stationId = row.read<String>('station_id');
          candidatesById[alias]?.add(stationId);
        }
      }
    }
    return {
      for (final entry in candidatesById.entries)
        entry.key: entry.value.length == 1 ? entry.value.first : null,
    };
  }

  Future<Map<String, _BatchStationMetadata>> _loadFavoriteStationMetadataBatch(
    List<String> stationIds,
  ) async {
    final metadataById = <String, _BatchStationMetadata>{};
    for (final chunk in _chunkValues(stationIds)) {
      final stationRows = await catalogDatabase
          .customSelect(
            '''
            SELECT
              s.id,
              s.name_ko,
              s.name_en,
              s.region,
              s.data_quality_level,
              s.data_source_type,
              CAST(s.last_verified_at AS INTEGER) AS last_verified_at_value,
              l.id AS line_id,
              l.name_ko AS line_name,
              l.color AS line_color,
              sl.station_code
            FROM stations s
            LEFT JOIN station_lines sl ON sl.station_id = s.id
            LEFT JOIN lines l ON l.id = sl.line_id
            WHERE s.id IN (${_sqlPlaceholders(chunk.length)})
            ORDER BY sl.line_sequence
            ''',
            variables: [for (final id in chunk) Variable.withString(id)],
            readsFrom: {
              catalogDatabase.stations,
              catalogDatabase.stationLines,
              catalogDatabase.lines,
            },
          )
          .get();
      for (final row in stationRows) {
        final stationId = row.read<String>('id');
        final metadata = metadataById.putIfAbsent(
          stationId,
          () => _BatchStationMetadata(
            nameKo: row.read<String>('name_ko'),
            nameEn: row.read<String?>('name_en') ?? '',
            region: row.read<String?>('region') ?? '',
            dataQualityLevel: row.read<String?>('data_quality_level') ?? '',
            dataSourceType: row.read<String?>('data_source_type') ?? '',
            lastVerifiedAt: _dateLabelFromEpoch(
              row.read<int?>('last_verified_at_value'),
            ),
          ),
        );
        final lineId = row.read<String?>('line_id');
        if (lineId != null) {
          metadata.lines.add(
            StationSearchLine(
              id: lineId,
              name: row.read<String>('line_name'),
              color: row.read<String>('line_color'),
              stationCode: row.read<String>('station_code'),
            ),
          );
        }
      }
    }
    return metadataById;
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(
    String stationId, {
    String? lineId,
  }) async {
    final trimmedStationId = stationId.trim();
    final normalizedLineId = (lineId ?? '').trim();
    final canonicalStationId = await catalogDatabase.findCanonicalStationId(
      trimmedStationId,
    );
    if (canonicalStationId == null) {
      throw const FavoriteStationException('즐겨찾기 역을 저장하지 못했어요.');
    }
    await _ensureStationExists(canonicalStationId);
    if (normalizedLineId.isNotEmpty) {
      await _ensureStationLineExists(canonicalStationId, normalizedLineId);
    }
    await userDatabase
        .into(userDatabase.favoriteStations)
        .insertOnConflictUpdate(
          user_db.FavoriteStationsCompanion.insert(
            stationId: canonicalStationId,
            lineId: Value(normalizedLineId),
            addedAt: DateTime.now().toUtc(),
          ),
        );
    return (await listFavoriteStations()).firstWhere(
      (favorite) =>
          favorite.stationId == canonicalStationId &&
          favorite.lineId == normalizedLineId,
    );
  }

  @override
  Future<void> removeFavoriteStation(String stationId, {String? lineId}) async {
    final trimmedStationId = stationId.trim();
    final normalizedLineId = (lineId ?? '').trim();
    final canonicalStationId = await catalogDatabase.findCanonicalStationId(
      trimmedStationId,
    );
    final resolvedStationId = canonicalStationId ?? trimmedStationId;
    if (normalizedLineId.isEmpty) {
      await userDatabase.customStatement(
        'DELETE FROM favorite_stations WHERE station_id = ? OR station_id = ?',
        [trimmedStationId, resolvedStationId],
      );
      return;
    }

    await userDatabase.transaction(() async {
      await userDatabase.customStatement(
        '''
        DELETE FROM favorite_stations
        WHERE (station_id = ? OR station_id = ?) AND line_id = ?
        ''',
        [trimmedStationId, resolvedStationId, normalizedLineId],
      );

      // 레거시 역 전체 즐겨찾기가 있으면, 해제한 호선만 빼고 나머지로 펼친다.
      final legacy = await userDatabase
          .customSelect(
            '''
            SELECT CAST(added_at AS INTEGER) AS added_at_value
            FROM favorite_stations
            WHERE (station_id = ? OR station_id = ?) AND line_id = ''
            LIMIT 1
            ''',
            variables: [
              Variable.withString(trimmedStationId),
              Variable.withString(resolvedStationId),
            ],
            readsFrom: {userDatabase.favoriteStations},
          )
          .getSingleOrNull();
      if (legacy == null) {
        return;
      }
      final addedAt = legacy.read<int>('added_at_value');
      final otherLineIds = await _lineIdsForStation(resolvedStationId);
      await userDatabase.customStatement(
        '''
        DELETE FROM favorite_stations
        WHERE (station_id = ? OR station_id = ?) AND line_id = ''
        ''',
        [trimmedStationId, resolvedStationId],
      );
      for (final otherLineId in otherLineIds) {
        if (otherLineId == normalizedLineId) {
          continue;
        }
        await userDatabase.customStatement(
          '''
          INSERT INTO favorite_stations (station_id, line_id, added_at)
          VALUES (?, ?, ?)
          ON CONFLICT(station_id, line_id) DO UPDATE SET
            added_at = MAX(favorite_stations.added_at, excluded.added_at)
          ''',
          [resolvedStationId, otherLineId, addedAt],
        );
      }
    });
  }

  Future<void> _migrateFavoriteStationIdsBatch(
    List<
      ({
        String storedStationId,
        String canonicalStationId,
        String lineId,
        int addedAt,
      })
    >
    migrations,
  ) async {
    await userDatabase.transaction(() async {
      for (final migration in migrations) {
        await userDatabase.customStatement(
          '''
          INSERT INTO favorite_stations (station_id, line_id, added_at)
          VALUES (?, ?, ?)
          ON CONFLICT(station_id, line_id) DO UPDATE SET
            added_at = MAX(favorite_stations.added_at, excluded.added_at)
          ''',
          [migration.canonicalStationId, migration.lineId, migration.addedAt],
        );
        await userDatabase.customStatement(
          '''
          DELETE FROM favorite_stations
          WHERE station_id = ? AND line_id = ?
          ''',
          [migration.storedStationId, migration.lineId],
        );
      }
    });
  }

  Future<void> _ensureStationExists(String stationId) async {
    final row = await catalogDatabase
        .customSelect(
          'SELECT id FROM stations WHERE id = ?',
          variables: [Variable.withString(stationId)],
          readsFrom: {catalogDatabase.stations},
        )
        .getSingleOrNull();
    if (row == null) {
      throw const FavoriteStationException('즐겨찾기 역을 저장하지 못했어요.');
    }
  }

  Future<void> _ensureStationLineExists(String stationId, String lineId) async {
    final row = await catalogDatabase
        .customSelect(
          '''
          SELECT station_id
          FROM station_lines
          WHERE station_id = ? AND line_id = ?
          LIMIT 1
          ''',
          variables: [
            Variable.withString(stationId),
            Variable.withString(lineId),
          ],
          readsFrom: {catalogDatabase.stationLines},
        )
        .getSingleOrNull();
    if (row == null) {
      throw const FavoriteStationException('즐겨찾기 역을 저장하지 못했어요.');
    }
  }

  Future<List<String>> _lineIdsForStation(String stationId) async {
    final rows = await catalogDatabase
        .customSelect(
          '''
          SELECT line_id
          FROM station_lines
          WHERE station_id = ?
          ORDER BY line_sequence
          ''',
          variables: [Variable.withString(stationId)],
          readsFrom: {catalogDatabase.stationLines},
        )
        .get();
    return [for (final row in rows) row.read<String>('line_id')];
  }
}

class DriftFavoriteFacilityRepository implements FavoriteFacilityRepository {
  DriftFavoriteFacilityRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final user_db.UserDatabase userDatabase;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final favoriteRows = await userDatabase
        .customSelect(
          '''
          SELECT facility_id, station_id, CAST(added_at AS INTEGER) AS added_at_value
          FROM favorite_facilities
          ORDER BY added_at DESC
          ''',
          readsFrom: {userDatabase.favoriteFacilities},
        )
        .get();
    if (favoriteRows.isEmpty) {
      return const [];
    }

    final facilityIds = <String>{
      for (final row in favoriteRows) row.read<String>('facility_id'),
    }.toList(growable: false);
    final rowsByFacilityId = <String, QueryRow>{};
    final qualityByFacilityId = <String, ({String? level, int? checkedAt})>{};

    for (final chunk in _chunkValues(facilityIds)) {
      final variables = [for (final id in chunk) Variable.withString(id)];
      final facilityRows = await catalogDatabase
          .customSelect(
            '''
            SELECT
              f.id,
              f.station_id,
              f.exit_id,
              f.type,
              f.name,
              f.floor_from,
              f.floor_to,
              f.description,
              f.status,
              s.name_ko AS station_name_ko,
              s.name_en AS station_name_en,
              s.data_source_type,
              CAST(s.last_verified_at AS INTEGER) AS last_verified_at_value
            FROM facilities f
            JOIN stations s ON s.id = f.station_id
            WHERE f.id IN (${_sqlPlaceholders(chunk.length)})
              AND f.installation_status <> 'NOT_INSTALLED'
            ''',
            variables: variables,
            readsFrom: {catalogDatabase.facilities, catalogDatabase.stations},
          )
          .get();
      if (facilityRows.isEmpty) {
        continue;
      }
      final matchedIds = <String>[];
      for (final row in facilityRows) {
        final id = row.read<String>('id');
        rowsByFacilityId[id] = row;
        matchedIds.add(id);
      }

      final qualityRows = await catalogDatabase
          .customSelect(
            '''
            WITH ranked_quality AS (
              SELECT
                q.target_id,
                q.quality_level,
                q.checked_at,
                ROW_NUMBER() OVER (
                  PARTITION BY q.target_id
                  ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
                ) AS rn
              FROM data_quality_records q
              WHERE UPPER(q.target_type) = 'FACILITY'
                AND q.target_id IN (${_sqlPlaceholders(matchedIds.length)})
            )
            SELECT target_id, quality_level, checked_at
            FROM ranked_quality
            WHERE rn = 1
            ''',
            variables: [for (final id in matchedIds) Variable.withString(id)],
            readsFrom: {catalogDatabase.dataQualityRecords},
          )
          .get();
      for (final row in qualityRows) {
        qualityByFacilityId[row.read<String>('target_id')] = (
          level: row.read<String?>('quality_level'),
          checkedAt: row.read<int?>('checked_at'),
        );
      }
    }

    final favorites = <FavoriteFacility>[];
    for (final favoriteRow in favoriteRows) {
      final facilityId = favoriteRow.read<String>('facility_id');
      final row = rowsByFacilityId[facilityId];
      if (row == null) {
        continue;
      }
      final quality = qualityByFacilityId[facilityId];
      final fieldQualityLevel = quality?.level;
      final fieldCheckedAt = quality?.checkedAt;
      favorites.add(
        FavoriteFacility(
          userId: _localUserId,
          facilityId: row.read<String>('id'),
          stationId: row.read<String>('station_id'),
          stationNameKo: row.read<String>('station_name_ko'),
          stationNameEn: row.read<String?>('station_name_en') ?? '',
          exitId: row.read<String?>('exit_id') ?? '',
          type: row.read<String?>('type') ?? '',
          name: row.read<String?>('name') ?? '',
          floorFrom: row.read<String?>('floor_from') ?? '',
          floorTo: row.read<String?>('floor_to') ?? '',
          description: row.read<String?>('description') ?? '',
          status: row.read<String?>('status') ?? '',
          dataConfidence: 'MEDIUM',
          dataSourceType: row.read<String?>('data_source_type') ?? '',
          fieldValidationStatus: _fieldValidationStatus(
            fieldQualityLevel,
            fieldCheckedAt,
          ),
          lastUpdatedAt: _dateLabelFromEpoch(
            fieldCheckedAt ?? row.read<int?>('last_verified_at_value'),
          ),
          addedAt: _isoFromEpoch(favoriteRow.read<int?>('added_at_value')),
        ),
      );
    }
    return favorites;
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    final trimmedFacilityId = facilityId.trim();
    final row = await _facilityCatalogRow(trimmedFacilityId);
    if (row == null) {
      throw const FavoriteFacilityException('즐겨찾기 시설을 바꾸지 못했어요.');
    }
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insertOnConflictUpdate(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: trimmedFacilityId,
            stationId: row.read<String>('station_id'),
            addedAt: DateTime.now().toUtc(),
          ),
        );
    return (await listFavoriteFacilities()).singleWhere(
      (favorite) => favorite.facilityId == trimmedFacilityId,
    );
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {
    await userDatabase.customStatement(
      'DELETE FROM favorite_facilities WHERE facility_id = ?',
      [facilityId.trim()],
    );
  }

  Future<QueryRow?> _facilityCatalogRow(String facilityId) {
    return catalogDatabase
        .customSelect(
          '''
          SELECT id, station_id
          FROM facilities
          WHERE id = ?
            AND installation_status <> 'NOT_INSTALLED'
          ''',
          variables: [Variable.withString(facilityId)],
          readsFrom: {catalogDatabase.facilities},
        )
        .getSingleOrNull();
  }
}

class DriftFavoriteRouteRepository implements FavoriteRouteRepository {
  DriftFavoriteRouteRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final user_db.UserDatabase userDatabase;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    final rows = await userDatabase
        .customSelect(
          '''
          SELECT route_id, origin_station_id, destination_station_id,
                 mobility_profile, CAST(added_at AS INTEGER) AS added_at_value
          FROM favorite_routes
          ORDER BY added_at DESC
          ''',
          readsFrom: {userDatabase.favoriteRoutes},
        )
        .get();
    if (rows.isEmpty) {
      return const [];
    }

    final snapshotKeys = <String>[
      for (final row in rows)
        if (!row.read<String>('route_id').startsWith('local-'))
          '$_routeSnapshotPrefix${row.read<String>('route_id')}',
    ];
    final snapshotsByRouteId = await _readRouteSnapshotsBatch(snapshotKeys);

    final staleRouteIds = <String>[];
    final validRows =
        <
          ({
            String routeId,
            String originStationId,
            String destinationStationId,
            String mobilityType,
            String addedAt,
          })
        >[];
    final stationIds = <String>{};
    for (final row in rows) {
      final routeId = row.read<String>('route_id');
      final snapshot = snapshotsByRouteId[routeId];
      if (routeId.startsWith('local-') ||
          _isStaleLocalRouteSnapshot(snapshot)) {
        staleRouteIds.add(routeId);
        continue;
      }
      final originStationId = row.read<String>('origin_station_id');
      final destinationStationId = row.read<String>('destination_station_id');
      stationIds.add(originStationId);
      stationIds.add(destinationStationId);
      validRows.add((
        routeId: routeId,
        originStationId: originStationId,
        destinationStationId: destinationStationId,
        mobilityType: row.read<String>('mobility_profile'),
        addedAt: _isoFromEpoch(row.read<int?>('added_at_value')),
      ));
    }

    if (staleRouteIds.isNotEmpty) {
      await _removeStaleLocalFavoriteRoutesBatch(staleRouteIds);
    }

    final stationNamesById = stationIds.isEmpty
        ? const <String, String>{}
        : await _stationNamesBatch(stationIds.toList(growable: false));
    final favorites = [
      for (final row in validRows)
        FavoriteRoute(
          userId: _localUserId,
          favoriteRouteId: row.routeId,
          routeSearchId: row.routeId,
          originStationId: row.originStationId,
          originStationName:
              stationNamesById[row.originStationId] ?? row.originStationId,
          destinationStationId: row.destinationStationId,
          destinationStationName:
              stationNamesById[row.destinationStationId] ??
              row.destinationStationId,
          mobilityType: row.mobilityType,
          status: 'RESEARCH_REQUIRED',
          lineId: '',
          lineName: '',
          score: 0,
          routeCreatedAt: row.addedAt,
          addedAt: row.addedAt,
          needsResearch: true,
        ),
    ];
    favorites.sort((left, right) => right.addedAt.compareTo(left.addedAt));
    return favorites;
  }

  bool _isStaleLocalRouteSnapshot(Map<String, Object?>? snapshot) {
    final routeSearchId = snapshot?['routeSearchId'];
    return routeSearchId is String && routeSearchId.trim().startsWith('local-');
  }

  Future<void> _removeStaleLocalFavoriteRoutesBatch(List<String> routeIds) {
    return userDatabase.transaction(() async {
      for (final chunk in _chunkValues(routeIds)) {
        final placeholders = _sqlPlaceholders(chunk.length);
        await userDatabase.customStatement(
          'DELETE FROM favorite_routes WHERE route_id IN ($placeholders)',
          chunk,
        );
        await userDatabase.customStatement(
          'DELETE FROM app_preferences WHERE key IN ($placeholders)',
          [for (final id in chunk) '$_routeSnapshotPrefix$id'],
        );
      }
    });
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {
    final routeId = favoriteRouteId.trim();
    await userDatabase.transaction(() async {
      await userDatabase.customStatement(
        'DELETE FROM favorite_routes WHERE route_id = ?',
        [routeId],
      );
      await userDatabase.customStatement(
        'DELETE FROM app_preferences WHERE key = ?',
        ['$_routeSnapshotPrefix$routeId'],
      );
    });
  }

  Future<Map<String, Map<String, Object?>>> _readRouteSnapshotsBatch(
    List<String> keys,
  ) async {
    if (keys.isEmpty) {
      return const {};
    }
    final snapshots = <String, Map<String, Object?>>{};
    for (final chunk in _chunkValues(keys)) {
      final rows = await userDatabase
          .customSelect(
            'SELECT key, value FROM app_preferences WHERE key IN (${_sqlPlaceholders(chunk.length)})',
            variables: [for (final key in chunk) Variable.withString(key)],
            readsFrom: {userDatabase.appPreferences},
          )
          .get();
      for (final row in rows) {
        final key = row.read<String>('key');
        final routeId = key.startsWith(_routeSnapshotPrefix)
            ? key.substring(_routeSnapshotPrefix.length)
            : key;
        try {
          final decoded = jsonDecode(row.read<String>('value'));
          if (decoded is Map<String, Object?>) {
            snapshots[routeId] = decoded;
          }
        } on FormatException {
          continue;
        }
      }
    }
    return snapshots;
  }

  Future<Map<String, String>> _stationNamesBatch(
    List<String> stationIds,
  ) async {
    final namesById = <String, String>{};
    for (final chunk in _chunkValues(stationIds)) {
      final rows = await catalogDatabase
          .customSelect(
            'SELECT id, name_ko FROM stations WHERE id IN (${_sqlPlaceholders(chunk.length)})',
            variables: [for (final id in chunk) Variable.withString(id)],
            readsFrom: {catalogDatabase.stations},
          )
          .get();
      for (final row in rows) {
        final stationId = row.read<String>('id');
        final catalogName = row.read<String?>('name_ko')?.trim() ?? '';
        if (catalogName.isNotEmpty) {
          namesById[stationId] = catalogName;
        }
      }
    }
    return namesById;
  }
}

class _BatchStationMetadata {
  _BatchStationMetadata({
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.dataQualityLevel,
    required this.dataSourceType,
    required this.lastVerifiedAt,
  });

  final String nameKo;
  final String nameEn;
  final String region;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final List<StationSearchLine> lines = [];
}

Iterable<List<String>> _chunkValues(List<String> values) sync* {
  for (var i = 0; i < values.length; i += _sqliteInClauseChunkSize) {
    final end = i + _sqliteInClauseChunkSize > values.length
        ? values.length
        : i + _sqliteInClauseChunkSize;
    yield values.sublist(i, end);
  }
}

String _sqlPlaceholders(int count) => List.filled(count, '?').join(', ');

class FavoriteStationBuilder {
  FavoriteStationBuilder({
    required this.stationId,
    this.lineId = '',
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.dataQualityLevel,
    required this.dataSourceType,
    required this.lastVerifiedAt,
    required this.addedAt,
  });

  final String stationId;
  final String lineId;
  final String nameKo;
  final String nameEn;
  final String region;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final String addedAt;
  final List<StationSearchLine> lines = [];

  FavoriteStation build() {
    return FavoriteStation(
      userId: _localUserId,
      stationId: stationId,
      lineId: lineId,
      nameKo: nameKo,
      nameEn: nameEn,
      region: region,
      dataQualityLevel: dataQualityLevel,
      dataSourceType: dataSourceType,
      lastVerifiedAt: lastVerifiedAt,
      lines: List.unmodifiable(lines),
      addedAt: addedAt,
    );
  }
}

String _isoFromEpoch(int? value) {
  if (value == null) {
    return '';
  }
  return _dateTimeFromEpoch(value).toIso8601String();
}

String _dateLabelFromEpoch(int? value) {
  if (value == null) {
    return '';
  }
  final utc = _dateTimeFromEpoch(value);
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

DateTime _dateTimeFromEpoch(int value) {
  return switch (value.abs()) {
    < 10000000000 => DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    ),
    > 100000000000000 => DateTime.fromMicrosecondsSinceEpoch(
      value,
      isUtc: true,
    ),
    _ => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
  };
}

String _fieldValidationStatus(String? qualityLevel, int? checkedAt) {
  final normalizedLevel = qualityLevel?.trim().toUpperCase();
  return switch (normalizedLevel) {
    'FIELD_VERIFIED' when checkedAt != null => 'VERIFIED',
    'FIELD_STALE' => 'STALE',
    'FIELD_UNKNOWN' => 'UNKNOWN',
    _ => 'UNKNOWN',
  };
}
