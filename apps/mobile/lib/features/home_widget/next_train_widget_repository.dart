import 'package:drift/drift.dart';

import '../../core/database/catalog/canonical_station_id.dart';
import '../../core/database/catalog/catalog_database.dart';
import '../../core/database/user/user_database.dart';
import '../stations/domain/station_repositories.dart';

enum NextTrainWidgetStatus { available, timetableUnavailable }

class WidgetStationSelection {
  const WidgetStationSelection({
    required this.stationId,
    required this.lineId,
    required this.stationName,
    required this.lineName,
  });
  final String stationId;
  final String lineId;
  final String stationName;
  final String lineName;
}

class NextTrainDirection {
  const NextTrainDirection({required this.name, required this.departureAt});
  final String name;
  final DateTime departureAt;
  String get departureLabel {
    final seoul = departureAt.toUtc().add(const Duration(hours: 9));
    return '${seoul.hour.toString().padLeft(2, '0')}:${seoul.minute.toString().padLeft(2, '0')}';
  }
}

class NextTrainWidgetData {
  const NextTrainWidgetData({
    required this.selection,
    required this.status,
    required this.directions,
    required this.statusLabel,
    required this.updatedAt,
  });
  factory NextTrainWidgetData.unavailable(
    WidgetStationSelection selection,
    DateTime updatedAt,
  ) => NextTrainWidgetData(
    selection: selection,
    status: NextTrainWidgetStatus.timetableUnavailable,
    directions: const [],
    statusLabel: '시간표를 확인할 수 없어요.',
    updatedAt: updatedAt,
  );
  final WidgetStationSelection selection;
  final NextTrainWidgetStatus status;
  final List<NextTrainDirection> directions;
  final String statusLabel;
  final DateTime updatedAt;
}

class NextTrainWidgetRepository {
  const NextTrainWidgetRepository({
    required this.catalogDatabase,
    required this.userDatabase,
    required this.timetableRepository,
  });
  final CatalogDatabase catalogDatabase;
  final UserDatabase userDatabase;
  final StationTimetableRepository timetableRepository;

  Future<List<WidgetStationSelection>> availableSelections() async {
    final favorites = await userDatabase
        .customSelect('SELECT station_id FROM favorite_stations')
        .get();
    if (favorites.isEmpty) return const [];
    final stationIds = <String>{};
    for (final favorite in favorites) {
      final id = await catalogDatabase.findCanonicalStationId(
        favorite.read<String>('station_id'),
      );
      if (id != null) stationIds.add(id);
    }
    if (stationIds.isEmpty) return const [];
    final placeholders = List.filled(stationIds.length, '?').join(',');
    final rows = await catalogDatabase.customSelect('''
      SELECT DISTINCT s.id AS station_id, sl.line_id, s.name_ko AS station_name, l.name_ko AS line_name
      FROM stations s JOIN station_lines sl ON sl.station_id = s.id JOIN lines l ON l.id = sl.line_id
      WHERE s.id IN ($placeholders) ORDER BY s.name_ko, l.name_ko
    ''', variables: stationIds.map(Variable.withString).toList()).get();
    return List.unmodifiable(
      rows.map(
        (row) => WidgetStationSelection(
          stationId: row.read<String>('station_id'),
          lineId: row.read<String>('line_id'),
          stationName: row.read<String>('station_name'),
          lineName: row.read<String>('line_name'),
        ),
      ),
    );
  }

  Future<NextTrainWidgetData> load(
    WidgetStationSelection selection,
    DateTime now,
  ) async {
    try {
      final canonicalStationId = await catalogDatabase.findCanonicalStationId(
        selection.stationId,
      );
      if (canonicalStationId == null) {
        return NextTrainWidgetData.unavailable(selection, now);
      }
      final canonicalSelection = canonicalStationId == selection.stationId
          ? selection
          : WidgetStationSelection(
              stationId: canonicalStationId,
              lineId: selection.lineId,
              stationName: selection.stationName,
              lineName: selection.lineName,
            );
      final timetable = await timetableRepository.loadNextStationTimetable(
        stationId: canonicalSelection.stationId,
        lineId: canonicalSelection.lineId,
        asOf: now,
      );
      final directions = <NextTrainDirection>[];
      for (final direction in timetable.directions) {
        if (direction.departures.isEmpty) continue;
        final departureAt = direction.departures.first.departureAt;
        if (departureAt == null || departureAt.isBefore(now)) continue;
        directions.add(
          NextTrainDirection(name: direction.name, departureAt: departureAt),
        );
      }
      directions.sort((a, b) => a.departureAt.compareTo(b.departureAt));
      if (directions.length < 2) {
        return NextTrainWidgetData.unavailable(canonicalSelection, now);
      }
      return NextTrainWidgetData(
        selection: canonicalSelection,
        status: NextTrainWidgetStatus.available,
        directions: List.unmodifiable(directions),
        statusLabel: '시간표 기준',
        updatedAt: now,
      );
    } catch (_) {
      return NextTrainWidgetData.unavailable(selection, now);
    }
  }
}
