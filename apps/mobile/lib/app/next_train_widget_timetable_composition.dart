import '../core/database/catalog/catalog_database.dart';
import '../core/network/api_client.dart';
import '../features/journey/data/journey_api_repository.dart';
import '../features/journey/data/journey_method_channel_integrity_attestor.dart';
import '../features/journey/journey_session_provider.dart';
import '../features/stations/data/drift_station_repository.dart';
import '../features/stations/data/server_station_timetable_repository.dart';
import '../features/stations/data/station_api_base_uri.dart';
import '../features/stations/domain/station_repositories.dart';

/// App-owned composition for each headless next-train widget engine.
///
/// The widget feature receives only [StationTimetableRepository], keeping the
/// Journey V3 transport, integrity, and session implementations at the app
/// composition boundary.
StationTimetableRepository createNextTrainWidgetTimetableRepository(
  CatalogDatabase catalog, {
  Uri? Function() resolveBaseUri = defaultOptionalStationApiBaseUri,
  JourneyV3IntegrityAttestor Function() createAttestor =
      JourneyMethodChannelIntegrityAttestor.new,
}) {
  final baseUri = resolveBaseUri();
  if (baseUri == null) {
    throw StateError('Journey V3 API base URL is not configured.');
  }
  final apiClient = ApiClient(baseUri: baseUri);
  final journeyRepository = JourneyApiRepository(apiClient);
  return _CloseableNextTrainWidgetTimetableRepository(
    journeyRepository: journeyRepository,
    stationNameResolver: stationDetailNameResolver(
      DriftStationRepository(database: catalog),
    ),
    sessionProvider: JourneySessionProvider(
      repository: journeyRepository,
      attestor: createAttestor(),
    ),
    onClose: apiClient.close,
  );
}

class _CloseableNextTrainWidgetTimetableRepository
    extends ServerStationTimetableRepository
    implements CloseableStationTimetableRepository {
  _CloseableNextTrainWidgetTimetableRepository({
    required super.journeyRepository,
    required super.stationNameResolver,
    required super.sessionProvider,
    required this._onClose,
  });

  final void Function({bool force}) _onClose;

  @override
  void close({bool force = false}) {
    _onClose(force: force);
  }
}
