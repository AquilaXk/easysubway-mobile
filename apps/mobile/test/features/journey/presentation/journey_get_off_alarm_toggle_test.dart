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

    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: _snapshot(journeyId: 'journey-resolver-error'),
          controller: controller,
          stationNameResolver: (_) => throw StateError('catalog failed'),
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

  testWidgets('enable 완료 전에 선택이 바뀌면 이전 Journey alarm을 보상 해제한다', (tester) async {
    controller.enableBarrier = Completer<void>();
    controller.enableStarted = Completer<void>();
    Widget toggle(String journeyId) => JourneyGetOffAlarmToggle(
      snapshot: _snapshot(journeyId: journeyId),
      controller: controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
      now: () => now,
    );
    await tester.pumpWidget(_host(toggle('journey-1')));
    await tester.tap(find.byType(Switch));
    while (!controller.enableStarted!.isCompleted) {
      await tester.pump();
    }

    await tester.pumpWidget(_host(toggle('journey-2')));
    controller.enableBarrier!.complete();
    await tester.pumpAndSettle();

    expect(controller.conditionalDisableCalls, 1);
    expect(controller.events, ['enable', 'disable-if-active']);
    expect(controller.state.enabled, isFalse);
  });

  testWidgets('controller 교체는 listener를 옮기고 새 controller state를 반영한다', (
    tester,
  ) async {
    final replacement = _Controller();
    addTearDown(replacement.dispose);
    final snapshot = _snapshot();
    Widget toggle(_Controller target) => JourneyGetOffAlarmToggle(
      snapshot: snapshot,
      controller: target,
      stationNameResolver: (stationId) async => '$stationId 이름',
      now: () => now,
    );

    await tester.pumpWidget(_host(toggle(controller)));
    await tester.pumpWidget(_host(toggle(replacement)));

    expect(controller.removeListenerCalls, 1);
    expect(replacement.addListenerCalls, 1);

    replacement.setTestState(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: 'journey-1',
        activeJourneyIdentity: journeyAlarmIdentityForSnapshot(snapshot),
        scheduledCount: 2,
      ),
    );
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('켜진 toggle은 disable 성공과 실패를 각각 표시한다', (tester) async {
    final snapshot = _snapshot();
    Widget toggle() => JourneyGetOffAlarmToggle(
      snapshot: snapshot,
      controller: controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
      now: () => now,
    );
    controller.setTestState(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: 'journey-1',
        activeJourneyIdentity: journeyAlarmIdentityForSnapshot(snapshot),
        scheduledCount: 2,
      ),
    );
    await tester.pumpWidget(_host(toggle()));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.disableCalls, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    controller.setTestState(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: 'journey-1',
        activeJourneyIdentity: journeyAlarmIdentityForSnapshot(snapshot),
        scheduledCount: 2,
      ),
    );
    controller.disableError = StateError('disable failed');
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.disableCalls, 2);
    expect(find.text('알림을 끄지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('다른 active identity는 먼저 끄고 enable failure를 명시한다', (tester) async {
    final snapshot = _snapshot();
    controller.setTestState(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: 'journey-other',
        activeJourneyIdentity: journeyAlarmIdentityForSnapshot(
          _snapshot(journeyId: 'journey-other'),
        ),
        scheduledCount: 2,
      ),
    );
    await tester.pumpWidget(
      _host(
        JourneyGetOffAlarmToggle(
          snapshot: snapshot,
          controller: controller,
          stationNameResolver: (stationId) async => '$stationId 이름',
          now: () => now,
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.events, ['disable', 'enable']);
    expect(controller.identity?.journeyId, 'journey-1');

    controller.events.clear();
    controller.setTestState(GetOffAlarmState.off);
    controller.enableError = StateError('enable failed');
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.events, ['enable']);
    expect(find.text('하차 알림을 켜지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('권한 거부와 부정확 예약 안내를 live region으로 표시한다', (tester) async {
    final snapshot = _snapshot();
    Widget toggle() => JourneyGetOffAlarmToggle(
      snapshot: snapshot,
      controller: controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
      now: () => now,
    );
    controller.setTestState(
      const GetOffAlarmState(permissionNotice: '휴대전화 알림 권한을 허용해 주세요.'),
    );
    await tester.pumpWidget(_host(toggle()));

    expect(find.text('휴대전화 알림 권한을 허용해 주세요.'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('journey-get-off-alarm-notice')),
          )
          .properties
          .liveRegion,
      isTrue,
    );

    controller.setTestState(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: 'journey-1',
        activeJourneyIdentity: journeyAlarmIdentityForSnapshot(snapshot),
        inexactNotice: '정확 알람 권한이 없어 ±수 분 오차가 있을 수 있어요.',
        scheduledCount: 2,
      ),
    );
    await tester.pump();

    expect(find.text('정확 알람 권한이 없어 ±수 분 오차가 있을 수 있어요.'), findsOneWidget);
    expect(find.text('휴대전화 알림 권한을 허용해 주세요.'), findsNothing);
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
        walkingPace: WalkingPace.standard,
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
  int disableCalls = 0;
  int conditionalDisableCalls = 0;
  int addListenerCalls = 0;
  int removeListenerCalls = 0;
  Object? enableError;
  Object? disableError;
  Completer<void>? enableBarrier;
  Completer<void>? enableStarted;
  JourneyAlarmSubscriptionIdentity? identity;
  List<GetOffAlarmStop> stops = const [];
  final events = <String>[];

  void setTestState(GetOffAlarmState state) {
    _testState = state;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    addListenerCalls++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removeListenerCalls++;
    super.removeListener(listener);
  }

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
    final started = enableStarted;
    if (started != null && !started.isCompleted) started.complete();
    await enableBarrier?.future;
    final error = enableError;
    if (error != null) throw error;
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
    disableCalls++;
    events.add('disable');
    final error = disableError;
    if (error != null) throw error;
    _testState = GetOffAlarmState.off;
    notifyListeners();
  }

  @override
  Future<void> disableJourneyIfActive(
    JourneyAlarmSubscriptionIdentity identity,
  ) async {
    conditionalDisableCalls++;
    events.add('disable-if-active');
    if (_testState.activeJourneyIdentity != identity) return;
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
