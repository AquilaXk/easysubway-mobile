import '../core/network/api_client.dart';
import '../features/journey/data/journey_api_repository.dart';
import '../features/journey/data/journey_method_channel_integrity_attestor.dart';
import '../features/journey/journey_session_provider.dart';
import '../features/stations/data/server_station_timetable_repository.dart';
import '../features/stations/data/station_api_base_uri.dart';
import '../features/stations/domain/station_repositories.dart';

/// App-owned composition for each headless next-train widget engine.
///
/// The widget feature receives only [StationTimetableRepository], keeping the
/// Journey V3 transport, integrity, and session implementations at the app
/// composition boundary.
StationTimetableRepository createNextTrainWidgetTimetableRepository() {
  final baseUri = defaultOptionalStationApiBaseUri();
  if (baseUri == null) {
    throw StateError('Journey V3 API base URL is not configured.');
  }
  final journeyRepository = JourneyApiRepository(ApiClient(baseUri: baseUri));
  return ServerStationTimetableRepository(
    journeyRepository: journeyRepository,
    sessionProvider: JourneySessionProvider(
      repository: journeyRepository,
      attestor: JourneyMethodChannelIntegrityAttestor(),
    ),
  );
}
