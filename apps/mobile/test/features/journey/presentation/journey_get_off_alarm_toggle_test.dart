import 'dart:async';

import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_get_off_alarm_toggle.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Controller controller;
  final now = DateTime.utc(2026, 8, 12, 0, 1);

  setUp(() {
    controller = _Controller();
  });

  tearDown(() => controller.dispose());

  testWidgets('resolved station names 뒤에만 exact Journey 구독을 켠다', (
    tester,
  ) async {
    final resolved = <String>[];
    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: _snapshot(),
          controller: controller,
          stationNameResolver: (stationId) async {
            resolved.add(stationId);
            controller.events.add('resolve:$stationId');
            return {'transfer': '동작', 'destination': '사당'}[stationId]!;
          },
          now: () => now,
        ),
      ),
    );

    expect(tester.getSize(find.byType(SwitchListTile)).height, greaterThan(48));
    await tester.tap(find.byType(Switch));
    for (var index = 0; index < 6; index++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(resolved, ['transfer', 'destination']);
    expect(find.byKey(const Key('journey-get-off-alarm-error')), findsNothing);
    expect(find.text('알림을 준비하고 있어요.'), findsNothing);
    expect(controller.events, [
      'resolve:transfer',
      'resolve:destination',
      'enable',
    ]);
    expect(controller.identity?.journeyId, 'journey-1');
    expect(
      controller.stops
          .singleWhere((stop) => stop.stationId == 'transfer')
          .stationName,
      '동작',
    );
    expect(
      controller.stops
          .singleWhere((stop) => stop.stationId == 'destination')
          .stationName,
      '사당',
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('realtime 선택은 realtime identity와 도착 시각으로 켠다', (tester) async {
    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: _snapshot(realtime: true),
          controller: controller,
          stationNameResolver: (stationId) async => '$stationId 이름',
          now: () => now,
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    for (var index = 0; index < 6; index++) {
      await tester.pump();
    }

    expect(
      controller.identity?.requestPolicy.timePolicy,
      TimePolicy.realtimeRequired,
    );
    expect(controller.stops.map((stop) => stop.arrivalAt), [
      DateTime.utc(2026, 8, 12, 0, 16),
      DateTime.utc(2026, 8, 12, 0, 31),
    ]);
  });

  testWidgets('expired·raw ID station name은 명시 실패하고 effect 0이다', (
    tester,
  ) async {
    var resolverCalls = 0;
    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: _snapshot(validUntil: now),
          controller: controller,
          stationNameResolver: (stationId) async {
            resolverCalls++;
            return stationId;
          },
          now: () => now,
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('이 경로로 하차 알림을 켤 수 없어요.'), findsOneWidget);
    expect(resolverCalls, 0);
    expect(controller.enableCalls, 0);

    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: _snapshot(realtime: true, partialRealtime: true),
          controller: controller,
          stationNameResolver: (stationId) async {
            resolverCalls++;
            return '$stationId 이름';
          },
          now: () => now,
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('이 경로로 하차 알림을 켤 수 없어요.'), findsOneWidget);
    expect(resolverCalls, 0);
    expect(controller.enableCalls, 0);

    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: _snapshot(),
          controller: controller,
          stationNameResolver: (stationId) async => stationId,
          now: () => now,
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('역 이름을 확인하지 못해 알림을 켜지 않았어요.'), findsOneWidget);
    expect(controller.enableCalls, 0);
  });

  testWidgets('station resolve 중 선택 generation이 바뀌면 effect 0이다', (
    tester,
  ) async {
    final name = Completer<String>();
    Widget toggle(String journeyId) => JourneyGetOffAlarmToggle(
      snapshot: _snapshot(journeyId: journeyId),
      controller: controller,
      stationNameResolver: (_) => name.future,
      now: () => now,
    );
    await tester.pumpWidget(_host(toggle('journey-1')));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    await tester.pumpWidget(_host(toggle('journey-2')));
    name.complete('사당');
    await tester.pumpAndSettle();

    expect(controller.enableCalls, 0);
  });
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

JourneySelectedSnapshot _snapshot({
  String journeyId = 'journey-1',
  DateTime? validUntil,
  bool realtime = false,
  bool partialRealtime = false,
}) {
  final now = DateTime.utc(2026, 8, 12);
  final journey = Journey(
    journeyId: journeyId,
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now.add(const Duration(minutes: 1)),
    plannedArrivalTime: now.add(const Duration(minutes: 30)),
    realtimeDepartureTime: realtime
        ? now.add(const Duration(minutes: 2))
        : null,
    realtimeArrivalTime: realtime ? now.add(const Duration(minutes: 31)) : null,
    durationSeconds: 300,
    transferCount: 1,
    walkingDistanceMeters: 0,
    timeSource: realtime
        ? JourneyTimeSource.realtime
        : JourneyTimeSource.timetable,
    accessibility: const JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: true,
      reasonCodes: <String>[],
    ),
    legs: <JourneyLeg>[
      JourneyRideLeg(
        lineId: 'line-1',
        tripId: 'trip-1',
        directionStationId: 'direction',
        fromStationId: 'origin',
        toStationId: 'transfer',
        plannedDepartureTime: now.add(const Duration(minutes: 1)),
        plannedArrivalTime: now.add(const Duration(minutes: 15)),
        realtimeDepartureTime: realtime
            ? now.add(const Duration(minutes: 2))
            : null,
        realtimeArrivalTime: realtime
            ? now.add(const Duration(minutes: 16))
            : null,
      ),
      JourneyRideLeg(
        lineId: 'line-2',
        tripId: 'trip-2',
        directionStationId: 'direction',
        fromStationId: 'transfer',
        toStationId: 'destination',
        plannedDepartureTime: now.add(const Duration(minutes: 16)),
        plannedArrivalTime: now.add(const Duration(minutes: 30)),
        realtimeDepartureTime: realtime
            ? now.add(const Duration(minutes: 17))
            : null,
        realtimeArrivalTime: realtime && !partialRealtime
            ? now.add(const Duration(minutes: 31))
            : null,
      ),
    ],
  );
  return JourneySelectedSnapshot.fromResponse(
    JourneySearchSuccess(
      contractVersion: JourneyContractVersion.journeySearchV3,
      requestId: '01J9VV0K000000000000000000',
      queryId: 'query-1',
      calculatedAt: now,
      validUntil: validUntil ?? now.add(const Duration(minutes: 5)),
      effectiveDepartureTime: now,
      serviceDate: JourneyDate.parse('2026-08-12'),
      serviceTimezone: 'Asia/Seoul',
      sourceIdentity: JourneySourceIdentity(
        routeBundleId: 'bundle-1',
        routeBundleSha256: 'a' * 64,
        timetableSnapshotId: 'timetable-1',
        accessibilitySnapshotId: 'accessibility-1',
        realtimeSnapshotId: realtime ? 'realtime-1' : null,
      ),
      requestPolicy: JourneyRequestPolicy(
        timePolicy: realtime
            ? TimePolicy.realtimeRequired
            : TimePolicy.timetableRequired,
        mobilityProfile: MobilityProfile.standard,
        constraintMode: ConstraintMode.none,
        maxTransfers: 3,
        alternativeCount: 3,
      ),
      journeys: [journey],
    ),
    journey,
  );
}

class _Controller extends GetOffAlarmController {
  _Controller()
    : super(
        notifier: const _Notifier(),
        permissionGate: const _ExactAlarmGate(),
        notificationPermissionProvider: const _Permission(),
        repository: _Repository(),
      );

  GetOffAlarmState _testState = GetOffAlarmState.off;
  int enableCalls = 0;
  JourneyAlarmSubscriptionIdentity? identity;
  List<GetOffAlarmStop> stops = const [];
  final events = <String>[];

  @override
  GetOffAlarmState get state => _testState;

  @override
  Future<void> enableJourney({
    required JourneyAlarmSubscriptionIdentity identity,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
  }) async {
    enableCalls++;
    events.add('enable');
    this.identity = identity;
    this.stops = List<GetOffAlarmStop>.unmodifiable(stops);
    _testState = GetOffAlarmState(
      enabled: true,
      activeRouteId: identity.journeyId,
      activeJourneyIdentity: identity,
      scheduledCount: stops.length,
    );
    notifyListeners();
  }

  @override
  Future<void> disable() async {
    _testState = GetOffAlarmState.off;
    notifyListeners();
  }
}

class _Notifier implements GetOffAlarmNotifier {
  const _Notifier();

  @override
  Future<void> cancelAll() async {}

  @override
  Future<int> pendingAlarmCount() async => 0;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async => throw UnimplementedError();
}

class _Repository implements GetOffAlarmStateRepository {
  @override
  Future<void> clearActive() async {}

  @override
  Future<GetOffAlarmSubscription?> loadActive() async => null;

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {}
}

class _Permission implements NotificationPermissionProvider {
  const _Permission();

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    return NotificationPermissionStatus.granted;
  }
}

class _ExactAlarmGate implements ExactAlarmPermissionGate {
  const _ExactAlarmGate();

  @override
  Future<bool> isExactAlarmPermitted() async => true;

  @override
  Future<bool> requestExactAlarmPermission() async => true;
}
