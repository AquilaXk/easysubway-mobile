import 'package:drift/drift.dart';

import 'catalog_database.dart';

extension CanonicalStationIdQuery on CatalogDatabase {
  Future<String?> findCanonicalStationId(String stationId) async {
    final direct = await customSelect(
      'SELECT id AS station_id FROM stations WHERE id = ? LIMIT 1',
      variables: [Variable.withString(stationId)],
      readsFrom: {stations},
    ).get();
    if (direct.isNotEmpty) {
      return direct.single.read<String>('station_id');
    }
    if (!stationId.startsWith('station-')) {
      return null;
    }
    final aliasRows = await customSelect(
      '''
      SELECT sa.station_id
      FROM station_aliases sa
      JOIN stations s ON s.id = sa.station_id
      WHERE sa.alias = ?
      LIMIT 2
      ''',
      variables: [Variable.withString(stationId)],
      readsFrom: {stations, stationAliases},
    ).get();
    return aliasRows.length == 1
        ? aliasRows.single.read<String>('station_id')
        : null;
  }

  Future<String> resolveCanonicalStationId(String stationId) async {
    return await findCanonicalStationId(stationId) ?? stationId;
  }
}
