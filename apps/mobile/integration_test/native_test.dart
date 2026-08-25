import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:easysubway_mobile/core/crashlytics/crash_report_redaction.dart';
import 'package:easysubway_mobile/core/crashlytics/crashlytics_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android native Journey success는 exact candidate를 선택하고 restart 뒤 상태를 재사용하지 않는다',
    (tester) async {
      final repository = _NativeJourneyRepository();
      await _pumpJourney(tester, repository);

      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();
      expect(repository.sessionRequests, 1);
      expect(repository.searchRequests, 1);
      expect(
        find.byKey(const Key('journey-candidate-native-journey')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('journey-candidate-native-journey')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('selected-journey-native-journey')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('selected-journey-detail')), findsOneWidget);

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selected-journey-detail')), findsNothing);
      expect(
        find.byKey(const Key('journey-candidate-native-journey')),
        findsNothing,
      );
      expect(repository.searchRequests, 1);
    },
  );

  testWidgets(
    'Android native Journey transport failure는 candidate 없이 안전한 retry state로 끝난다',
    (tester) async {
      final repository = _NativeJourneyRepository(failSearch: true);
      final crashlytics = _NativeRecordingCrashlytics();
      replaceCrashlyticsGatewayForTest(crashlytics);
      addTearDown(resetCrashlyticsGateway);
      await _pumpJourney(tester, repository);

      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();

      expect(repository.sessionRequests, 1);
      expect(repository.searchRequests, 1);
      expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
      expect(
        find.byKey(const Key('journey-candidate-native-journey')),
        findsNothing,
      );
      expect(find.textContaining('native transport detail'), findsNothing);
      expect(crashlytics.errors, hasLength(1));
      expect(crashlytics.fatalFlags, <bool>[false]);
      expect(crashlytics.errors.single, isA<SanitizedCrashException>());
      expect(crashlytics.payload, contains('subsystem=app-report'));
      expect(crashlytics.payload, isNot(contains('native transport detail')));
      expect(crashlytics.payload, isNot(contains('station-origin')));
      expect(crashlytics.payload, isNot(contains('station-destination')));
      expect(crashlytics.payload, isNot(contains('native-session-token')));
    },
  );
}

class _NativeRecordingCrashlytics implements CrashlyticsGateway {
  final errors = <Object>[];
  final fatalFlags = <bool>[];
  final payloadLines = <String>[];

  String get payload => payloadLines.join('\n');

  @override
  bool get isCollectionEnabled => false;

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    errors.add(error);
    fatalFlags.add(fatal);
    payloadLines.addAll(<String>[
      error.toString(),
      stackTrace.toString(),
      reason ?? '',
    ]);
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {}

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> setCustomKey(String key, String value) async {}
}

Future<void> _pumpJourney(
  WidgetTester tester,
  _NativeJourneyRepository repository,
) {
  return tester.pumpWidget(
    MaterialApp(
      restorationScopeId: 'journey-native-smoke',
      home: JourneySearchScreen(
        repository: repository,
        attestor: const _NativeAttestor(),
        draft: RouteDraft(
          origin: const RouteDraftStation(id: 'station-origin', nameKo: '용산'),
          destination: const RouteDraftStation(
            id: 'station-destination',
            nameKo: '춘천',
          ),
          lastModifiedAt: DateTime.utc(2026, 8, 12),
        ),
        mobilityType: 'STANDARD',
        onShellBackToHome: () {},
        journeyNow: () => DateTime.utc(2026, 8, 12),
      ),
    ),
  );
}

final class _NativeAttestor implements JourneyV3IntegrityAttestor {
  const _NativeAttestor();

  @override
  Future<String> attest(String requestHash) async => 'native-integrity-token';
}

final class _NativeJourneyRepository implements JourneyRepository {
  _NativeJourneyRepository({this.failSearch = false});

  final bool failSearch;
  int sessionRequests = 0;
  int searchRequests = 0;

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    sessionRequests++;
    final now = DateTime.utc(2026, 8, 12);
    return JourneySessionResponse(
      token: 'native-session-token',
      scope: JourneySessionScope.journeyV3,
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    searchRequests++;
    if (failSearch) {
      throw const JourneyTransportFailure(
        JourneyOperation.searchJourneys,
        'native transport detail',
      );
    }
    final now = DateTime.utc(2026, 8, 12);
    return JourneySearchSuccess(
      contractVersion: JourneyContractVersion.journeySearchV3,
      requestId: request.requestId,
      queryId: 'native-query',
      calculatedAt: now,
      validUntil: now.add(const Duration(minutes: 5)),
      effectiveDepartureTime: now,
      serviceDate: JourneyDate.parse('2026-08-12'),
      serviceTimezone: 'Asia/Seoul',
      sourceIdentity: JourneySourceIdentity(
        routeBundleId: 'native-bundle',
        routeBundleSha256: 'a' * 64,
        timetableSnapshotId: 'native-timetable',
        accessibilitySnapshotId: 'native-accessibility',
        realtimeSnapshotId: null,
      ),
      requestPolicy: JourneyRequestPolicy(
        timePolicy: request.timePolicy,
        walkingPace: request.walkingPace,
        mobilityProfile: request.mobilityProfile,
        constraintMode: request.constraintMode,
        maxTransfers: request.maxTransfers,
        alternativeCount: request.alternativeCount,
      ),
      journeys: <Journey>[_nativeJourney(now)],
    );
  }

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) => throw UnimplementedError();
}

Journey _nativeJourney(DateTime now) => Journey(
  journeyId: 'native-journey',
  status: JourneyStatus.found,
  planSource: JourneyPlanSource.serverTimetableRaptor,
  plannedDepartureTime: now,
  plannedArrivalTime: now.add(const Duration(minutes: 5)),
  realtimeDepartureTime: null,
  realtimeArrivalTime: null,
  durationSeconds: 300,
  transferCount: 0,
  walkingDistanceMeters: 20,
  timeSource: JourneyTimeSource.timetable,
  accessibility: const JourneyAccessibility(
    result: JourneyAccessibilityResult.verified,
    stairFree: false,
    reasonCodes: <String>[],
  ),
  legs: <JourneyLeg>[
    const JourneyEntryLeg(fromStationId: 'station-origin', durationSeconds: 60),
    JourneyRideLeg(
      lineId: 'line-1',
      tripId: 'trip-1',
      directionStationId: 'station-destination',
      fromStationId: 'station-origin',
      toStationId: 'station-destination',
      plannedDepartureTime: now,
      plannedArrivalTime: now.add(const Duration(minutes: 4)),
      realtimeDepartureTime: null,
      realtimeArrivalTime: null,
    ),
    const JourneyExitLeg(
      fromStationId: 'station-destination',
      durationSeconds: 60,
    ),
  ],
);
