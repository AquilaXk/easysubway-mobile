import 'dart:async';

import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_recovery_notice_store.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingNotifier implements GetOffAlarmNotifier {
  List<ScheduledGetOffAlarm>? scheduledAlarms;
  GetOffAlarmScheduleMode? scheduledMode;
  ScheduleDeliveryResult? result;
  int cancelAllCount = 0;
  Completer<void>? cancelBarrier;
  Object? cancelErrorOnce;
  Object? scheduleError;
  int? pendingCount;
  int scheduleCalls = 0;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async {
    scheduleCalls += 1;
    final error = scheduleError;
    if (error != null) {
      throw error;
    }
    scheduledAlarms = alarms;
    scheduledMode = mode;
    return result ??
        ScheduleDeliveryResult(scheduledCount: alarms.length, failedCount: 0);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    final error = cancelErrorOnce;
    cancelErrorOnce = null;
    if (error != null) {
      throw error;
    }
    await cancelBarrier?.future;
  }

  @override
  Future<int> pendingAlarmCount() async =>
      pendingCount ?? result?.scheduledCount ?? scheduledAlarms?.length ?? 0;
}

class _RecordingStateRepository implements GetOffAlarmStateRepository {
  _RecordingStateRepository({this.loadError, this.saveError, this.clearError});

  GetOffAlarmSubscription? active;
  Object? loadError;
  Object? saveError;
  Object? clearError;
  int clearCount = 0;
  int saveCount = 0;

  @override
  Future<void> clearActive() async {
    clearCount += 1;
    final error = clearError;
    if (error != null) {
      throw error;
    }
    active = null;
  }

  @override
  Future<GetOffAlarmSubscription?> loadActive() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    return active;
  }

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {
    saveCount += 1;
    final error = saveError;
    if (error != null) {
      throw error;
    }
    active = subscription;
  }
}

GetOffAlarmSubscription _withRouteId(
  GetOffAlarmSubscription subscription,
  String routeId,
) {
  return GetOffAlarmSubscription(
    routeId: routeId,
    journeyIdentity: subscription.journeyIdentity,
    transferAlarmEnabled: subscription.transferAlarmEnabled,
    scheduledCount: subscription.scheduledCount,
    scheduleMode: subscription.scheduleMode,
    inexactNotice: subscription.inexactNotice,
    destination: subscription.destination,
    transfers: subscription.transfers,
  );
}

JourneyAlarmSubscriptionIdentity _journeyIdentity([String journeyId = 'r1']) =>
    JourneyAlarmSubscriptionIdentity(
      contractVersion: JourneyContractVersion.journeySearchV3,
      requestId: '01J9VV0K000000000000000000',
      queryId: 'query-1',
      journeyId: journeyId,
      calculatedAt: DateTime.utc(2026, 7, 6, 8, 55),
      validUntil: DateTime.utc(2026, 7, 6, 9, 0),
      effectiveDepartureTime: DateTime.utc(2026, 7, 6, 9, 0),
      serviceDate: JourneyDate.parse('2026-07-06'),
      serviceTimezone: 'Asia/Seoul',
      sourceIdentity: JourneySourceIdentity(
        routeBundleId: 'bundle-1',
        routeBundleSha256: 'a' * 64,
        timetableSnapshotId: 'timetable-1',
        accessibilitySnapshotId: 'accessibility-1',
        realtimeSnapshotId: null,
      ),
      requestPolicy: const JourneyRequestPolicy(
        timePolicy: TimePolicy.timetableRequired,
        mobilityProfile: MobilityProfile.standard,
        constraintMode: ConstraintMode.none,
        maxTransfers: 3,
        alternativeCount: 3,
      ),
    );

class _StubExactAlarmGate implements ExactAlarmPermissionGate {
  _StubExactAlarmGate(this.permitted);

  bool permitted;
  int isPermittedCalls = 0;
  int requestCalls = 0;

  @override
  Future<bool> isExactAlarmPermitted() async {
    isPermittedCalls += 1;
    return permitted;
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    requestCalls += 1;
    return permitted;
  }
}

class _BlockingRefreshExactAlarmGate implements ExactAlarmPermissionGate {
  final isPermittedStarted = Completer<void>();
  final permitted = Completer<bool>();
  int isPermittedCalls = 0;

  @override
  Future<bool> isExactAlarmPermitted() {
    isPermittedCalls += 1;
    if (!isPermittedStarted.isCompleted) {
      isPermittedStarted.complete();
    }
    return permitted.future;
  }

  @override
  Future<bool> requestExactAlarmPermission() async => true;
}

class _RecordingRecoveryNoticeStore implements GetOffAlarmRecoveryNoticeStore {
  bool flag = false;
  int recordCount = 0;
  int consumeCount = 0;

  @override
  Future<void> record() async {
    recordCount += 1;
    flag = true;
  }

  @override
  Future<bool> consume() async {
    consumeCount += 1;
    final current = flag;
    flag = false;
    return current;
  }
}

class _StubNotificationPermissionProvider
    implements NotificationPermissionProvider {
  _StubNotificationPermissionProvider(this.status);

  NotificationPermissionStatus status;
  int requestCalls = 0;
  int statusCalls = 0;

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async {
    statusCalls += 1;
    return status;
  }

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    requestCalls += 1;
    return status;
  }
}

/// 호출마다 다음 시각을 돌려주는 주입용 시계. 마지막 원소에 도달하면 그대로
/// 유지한다. now()가 몇 번 소비됐는지([calls])로 단일 스냅샷 여부를 검증한다.
class _AdvancingClock {
  _AdvancingClock(this._instants);

  final List<DateTime> _instants;
  int calls = 0;

  DateTime now() {
    final index = calls < _instants.length ? calls : _instants.length - 1;
    calls += 1;
    return _instants[index];
  }
}

void main() {
  final now = DateTime(2026, 7, 6, 9, 0, 0);

  List<GetOffAlarmStop> stops() => [
    GetOffAlarmStop(
      stationId: 'transfer',
      stationName: '동작',
      arrivalAt: DateTime(2026, 7, 6, 9, 15, 0),
      kind: GetOffAlarmKind.transfer,
    ),
    GetOffAlarmStop(
      stationId: 'dest',
      stationName: '사당',
      arrivalAt: DateTime(2026, 7, 6, 9, 30, 0),
      kind: GetOffAlarmKind.destination,
    ),
  ];

  late UserDatabase db;
  late DriftGetOffAlarmStateRepository repository;
  late _RecordingNotifier notifier;
  late _StubExactAlarmGate exactAlarmGate;

  setUp(() {
    db = UserDatabase.memory();
    repository = DriftGetOffAlarmStateRepository(userDatabase: db);
    notifier = _RecordingNotifier();
  });

  tearDown(() async {
    await db.close();
  });

  GetOffAlarmController controller({
    required bool exactPermitted,
    bool notificationPermitted = true,
  }) {
    exactAlarmGate = _StubExactAlarmGate(exactPermitted);
    return GetOffAlarmController(
      notifier: notifier,
      permissionGate: exactAlarmGate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        notificationPermitted
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied,
      ),
      repository: repository,
      now: () => now,
    );
  }

  test('정확 알람 권한이 있으면 exact 모드로 예약하고 상태를 켠다', () async {
    final c = controller(exactPermitted: true);

    await c.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    expect(notifier.scheduledMode, GetOffAlarmScheduleMode.exact);
    expect(notifier.scheduledAlarms, hasLength(2));
    expect(c.state.enabled, isTrue);
    expect(c.state.activeRouteId, 'r1');
    expect(c.state.inexactNotice, isNull);
    // 활성 구독이 영속 저장된다.
    expect(await repository.loadActive(), isNotNull);
  });

  test('Journey enable은 선택 identity 전체를 저장하고 상태에 노출한다', () async {
    final c = controller(exactPermitted: true);
    final identity = _journeyIdentity();

    await c.enableJourney(
      identity: identity,
      stops: stops(),
      transferAlarmEnabled: true,
    );

    expect(c.state.activeJourneyIdentity, identity);
    expect((await repository.loadActive())?.journeyIdentity, identity);
  });

  test('identity 없는 legacy 구독은 restore current success가 아니다', () async {
    final first = controller(exactPermitted: true);
    await first.enable(
      routeId: 'legacy-route',
      stops: stops(),
      transferAlarmEnabled: true,
    );
    notifier.cancelAllCount = 0;
    final restored = controller(exactPermitted: true);

    await restored.restore();

    expect(restored.state.enabled, isFalse);
    expect(notifier.cancelAllCount, 1);
    expect(await repository.loadActive(), isNull);
  });

  test('repository가 반환한 identity 없는 구독은 restore에서 정리하고 off로 닫는다', () async {
    final stateRepository = _RecordingStateRepository()
      ..active = GetOffAlarmSubscription(
        routeId: 'legacy-route',
        journeyIdentity: null,
        transferAlarmEnabled: false,
        scheduledCount: 1,
        scheduleMode: GetOffAlarmScheduleMode.exact,
        inexactNotice: null,
        destination: GetOffAlarmStopRef(
          stationId: 'dest',
          stationName: '사당',
          arrivalAt: DateTime(2026, 7, 6, 9, 30),
        ),
        transfers: const [],
      );
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(stateRepository.active, isNull);
    expect(notifier.cancelAllCount, 1);
    expect(restored.state, GetOffAlarmState.off);
  });

  test('정확 알람 권한이 없으면 inexact로 강등하고 오차 고지를 상태에 담는다', () async {
    final c = controller(exactPermitted: false);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(notifier.scheduledMode, GetOffAlarmScheduleMode.inexact);
    expect(c.state.inexactNotice, isNotNull);
    expect(c.state.inexactNotice, contains('오차'));
  });

  test('환승 알림을 끄면 환승 정차역은 예약하지 않는다', () async {
    final c = controller(exactPermitted: true);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: false);

    expect(notifier.scheduledAlarms, hasLength(1));
    expect(notifier.scheduledAlarms!.single.kind, GetOffAlarmKind.destination);
  });

  test('POST_NOTIFICATIONS 거부는 예약과 enabled 저장을 막는다', () async {
    final c = controller(exactPermitted: true, notificationPermitted: false);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(notifier.scheduledAlarms, isNull);
    expect(c.state.enabled, isFalse);
    expect(c.state.permissionNotice, '휴대전화 알림 권한을 허용해 주세요.');
    expect(await repository.loadActive(), isNull);
  });

  test('부분 예약 실패는 실제 성공 수만 상태에 반영한다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 1,
      failedCount: 1,
    );
    final c = controller(exactPermitted: true);

    await c.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    expect(c.state.enabled, isTrue);
    expect(c.state.scheduledCount, 1);
    expect((await repository.loadActive())!.scheduledCount, 1);
  });

  test('부분 예약 성공 수는 저장되고 restore에서도 그대로 복원된다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 1,
      failedCount: 1,
    );
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.scheduledCount, 1);
  });

  test('restore는 현재도 inexact면 저장된 강등 고지를 유지한다', () async {
    final first = controller(exactPermitted: false);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: false);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(restored.state.inexactNotice, contains('오차'));
  });

  test('restore에서 알림 권한이 철회되면 프롬프트 없이 pending과 저장을 정리한다', () async {
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    final permission = _StubNotificationPermissionProvider(
      NotificationPermissionStatus.denied,
    );
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: permission,
      repository: repository,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(permission.requestCalls, 0);
    expect(permission.statusCalls, 1);
    expect(notifier.cancelAllCount, 1);
    expect(await repository.loadActive(), isNull);
    expect(restored.state.enabled, isFalse);
  });

  test('restore에서 미래 구독은 pending 상태와 무관하게 전체 재예약한다', () async {
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    notifier.scheduleCalls = 0;

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(notifier.scheduleCalls, 1);
    expect(notifier.scheduledAlarms, hasLength(2));
    expect(restored.state.enabled, isTrue);
    expect(restored.state.activeRouteId, 'r1');
    expect((await repository.loadActive())?.routeId, 'r1');
  });

  test('restore는 단일 now 스냅샷으로 계산해 마지막 알림 경계에서 갈라지지 않는다', () async {
    // 저장: 환승 9:15(fireAt 9:13)·도착 9:30(fireAt 9:28).
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    // restore 시점의 두 후보 스냅샷: 첫 스냅샷은 마지막 fireAt(9:28) 직전이라
    // 도착 알림 1건이 미래이고, 다음 스냅샷은 직후라 0건이다. 원자화 전이라면
    // _restore의 만료 판정(1건)과 _schedule의 재계산(0건)이 갈려 복구가 조용히
    // off로 정리됐다. 원자화 후에는 첫 스냅샷 결과로만 예약한다.
    final clock = _AdvancingClock([
      DateTime(2026, 7, 6, 9, 27, 59),
      DateTime(2026, 7, 6, 9, 28, 1),
    ]);
    notifier.scheduleCalls = 0;
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: repository,
      now: clock.now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    // 첫 스냅샷 결과(도착 1건)로 예약되고 켜진 상태를 유지한다.
    expect(restored.state.enabled, isTrue);
    expect(notifier.scheduleCalls, 1);
    expect(notifier.scheduledAlarms, hasLength(1));
    // restore 경로 전체가 now를 정확히 한 번만 읽어 두 스냅샷 갈림이 불가능하다.
    expect(clock.calls, 1);
  });

  test('restore는 미래 구독을 결정적 재예약하고 실제 예약 수를 저장한다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 2,
      failedCount: 0,
    );
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.scheduledCount, 2);
    expect((await repository.loadActive())!.scheduledCount, 2);
    expect(notifier.scheduleCalls, 2);
  });

  test('restore에서 exact 상태가 바뀌면 저장된 stops로 권한 요청 없이 재예약한다', () async {
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    final permission = _StubNotificationPermissionProvider(
      NotificationPermissionStatus.granted,
    );
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(false),
      notificationPermissionProvider: permission,
      repository: repository,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(permission.requestCalls, 0);
    expect(permission.statusCalls, 1);
    expect(notifier.scheduleCalls, 2);
    expect(notifier.scheduledAlarms, hasLength(2));
    expect(restored.state.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(restored.state.inexactNotice, contains('오차'));
  });

  test('refresh는 exact 권한 상태만 확인하고 권한을 다시 요청하지 않는다', () async {
    final c = controller(exactPermitted: true);
    await c.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    expect(exactAlarmGate.requestCalls, 1);
    expect(exactAlarmGate.isPermittedCalls, 0);

    exactAlarmGate.permitted = false;
    await c.refresh(routeId: 'r1', stops: stops());

    expect(exactAlarmGate.requestCalls, 1);
    expect(exactAlarmGate.isPermittedCalls, 1);
    expect(c.state.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(c.state.inexactNotice, contains('오차'));
  });

  test('refresh는 현재 알림 권한이 거부되면 재예약 없이 off로 정리한다', () async {
    final permission = _StubNotificationPermissionProvider(
      NotificationPermissionStatus.granted,
    );
    final gate = _StubExactAlarmGate(true);
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: permission,
      repository: repository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    permission.status = NotificationPermissionStatus.denied;

    await c.refresh(routeId: 'r1', stops: stops());

    expect(permission.requestCalls, 1);
    expect(permission.statusCalls, 1);
    expect(notifier.scheduleCalls, 1);
    expect(gate.isPermittedCalls, 0);
    expect(c.state.enabled, isFalse);
    expect(await repository.loadActive(), isNull);
  });

  test('refresh에 destination이 없으면 기존 예약과 활성 구독을 유지한다', () async {
    final stateRepository = _RecordingStateRepository();
    final gate = _StubExactAlarmGate(true);
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);
    final stateBeforeRefresh = c.state;
    final subscriptionBeforeRefresh = stateRepository.active;
    final scheduleCallsBeforeRefresh = notifier.scheduleCalls;
    final cancelCallsBeforeRefresh = notifier.cancelAllCount;

    await c.refresh(
      routeId: 'r1',
      stops: [
        GetOffAlarmStop(
          stationId: 'transfer',
          stationName: '동작',
          arrivalAt: DateTime(2026, 7, 6, 9, 15, 0),
          kind: GetOffAlarmKind.transfer,
        ),
      ],
    );

    expect(notifier.scheduleCalls, scheduleCallsBeforeRefresh);
    expect(notifier.cancelAllCount, cancelCallsBeforeRefresh);
    expect(c.state, same(stateBeforeRefresh));
    expect(stateRepository.active, same(subscriptionBeforeRefresh));
    expect(gate.isPermittedCalls, 0);
  });

  for (final mismatch in [
    (
      name: 'persisted route만 다르면',
      controllerRouteId: 'r1',
      persistedRouteId: 'r2',
      inputRouteId: 'r1',
    ),
    (
      name: 'controller route만 다르면',
      controllerRouteId: 'r2',
      persistedRouteId: 'r1',
      inputRouteId: 'r1',
    ),
    (
      name: '입력 route만 다르면',
      controllerRouteId: 'r1',
      persistedRouteId: 'r1',
      inputRouteId: 'r2',
    ),
  ]) {
    test('refresh는 ${mismatch.name} routeMismatch로 기존 알림과 구독을 보존한다', () async {
      final stateRepository = _RecordingStateRepository();
      final c = GetOffAlarmController(
        notifier: notifier,
        permissionGate: _StubExactAlarmGate(true),
        notificationPermissionProvider: _StubNotificationPermissionProvider(
          NotificationPermissionStatus.granted,
        ),
        repository: stateRepository,
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.enable(
        routeId: mismatch.controllerRouteId,
        stops: stops(),
        transferAlarmEnabled: true,
      );
      stateRepository.active = _withRouteId(
        stateRepository.active!,
        mismatch.persistedRouteId,
      );
      final subscriptionBefore = stateRepository.active;
      final pendingBefore = List<ScheduledGetOffAlarm>.of(
        notifier.scheduledAlarms!,
      );
      final scheduleCallsBefore = notifier.scheduleCalls;
      final cancelCallsBefore = notifier.cancelAllCount;
      final saveCallsBefore = stateRepository.saveCount;
      final clearCallsBefore = stateRepository.clearCount;

      final result = await c.refresh(
        routeId: mismatch.inputRouteId,
        stops: stops(),
      );

      expect(result, GetOffAlarmRefreshResult.routeMismatch);
      expect(notifier.scheduleCalls, scheduleCallsBefore);
      expect(notifier.cancelAllCount, cancelCallsBefore);
      expect(stateRepository.saveCount, saveCallsBefore);
      expect(stateRepository.clearCount, clearCallsBefore);
      expect(stateRepository.active, same(subscriptionBefore));
      expect(notifier.scheduledAlarms, pendingBefore);
    });
  }

  test('route 전환 뒤 queued된 이전 route refresh는 routeMismatch로 거부한다', () async {
    final gate = _BlockingRefreshExactAlarmGate();
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    final inFlight = c.refresh(routeId: 'r1', stops: stops());
    await gate.isPermittedStarted.future;
    final transition = c.enable(
      routeId: 'r2',
      stops: stops(),
      transferAlarmEnabled: false,
    );
    final stale = c.refresh(routeId: 'r1', stops: stops());
    gate.permitted.complete(true);

    expect(await inFlight, GetOffAlarmRefreshResult.refreshed);
    await transition;
    final scheduleCallsBeforeStale = notifier.scheduleCalls;
    final saveCallsBeforeStale = stateRepository.saveCount;
    expect(await stale, GetOffAlarmRefreshResult.routeMismatch);

    expect(notifier.scheduleCalls, scheduleCallsBeforeStale);
    expect(notifier.cancelAllCount, 0);
    expect(stateRepository.saveCount, saveCallsBeforeStale);
    expect(stateRepository.clearCount, 0);
    expect(stateRepository.active?.routeId, 'r2');
    expect(stateRepository.active?.transferAlarmEnabled, isFalse);
    expect(c.state.activeRouteId, 'r2');
  });

  test('예약 성공이 0건이면 enabled와 활성 구독을 저장하지 않는다', () async {
    notifier.result = const ScheduleDeliveryResult(
      scheduledCount: 0,
      failedCount: 2,
    );
    final c = controller(exactPermitted: true);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(c.state.enabled, isFalse);
    expect(c.state.scheduledCount, 0);
    expect(await repository.loadActive(), isNull);
  });

  test('OS 예약 후 활성 저장 실패는 전용 알림과 저장값을 정리하고 원래 오류를 던진다', () async {
    final saveError = StateError('save failed');
    final stateRepository = _RecordingStateRepository(saveError: saveError);
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);

    await expectLater(
      c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true),
      throwsA(same(saveError)),
    );

    expect(notifier.scheduledAlarms, hasLength(2));
    expect(notifier.cancelAllCount, 1);
    expect(stateRepository.clearCount, 1);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
  });

  test('저장 실패 보상 정리 오류는 안전한 문맥으로 보고하고 원래 저장 오류를 보존한다', () async {
    final saveError = StateError('save failed');
    final cancelError = StateError('cancel failed');
    final clearError = StateError('clear failed');
    notifier.cancelErrorOnce = cancelError;
    final stateRepository = _RecordingStateRepository(
      saveError: saveError,
      clearError: clearError,
    );
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    final reports = <FlutterErrorDetails>[];

    await expectLater(
      runWithMobileErrorReporter(
        reports.add,
        () =>
            c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true),
      ),
      throwsA(same(saveError)),
    );

    expect(reports.map((report) => report.exception), [
      cancelError,
      clearError,
    ]);
    expect(
      reports.map((report) => report.context.toString()),
      everyElement(equals('하차 알림 저장 실패 보상 정리 중 예외가 발생했습니다.')),
    );
    expect(c.state.enabled, isFalse);
  });

  test('disable은 알림을 취소하고 영속 상태를 지우며 상태를 끈다', () async {
    final c = controller(exactPermitted: true);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    await c.disable();

    expect(notifier.cancelAllCount, greaterThanOrEqualTo(1));
    expect(await repository.loadActive(), isNull);
    expect(c.state.enabled, isFalse);
    expect(c.state.activeRouteId, isNull);
  });

  test('disable clear 실패는 기존 Journey 예약·선택을 복구하고 오류를 돌려준다', () async {
    final clearError = StateError('clear failed');
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    final identity = _journeyIdentity();
    await c.enableJourney(
      identity: identity,
      stops: stops(),
      transferAlarmEnabled: true,
    );
    stateRepository.clearError = clearError;
    final scheduleCallsBefore = notifier.scheduleCalls;

    await expectLater(c.disable(), throwsA(same(clearError)));

    expect(notifier.scheduleCalls, scheduleCallsBefore + 1);
    expect(stateRepository.active?.journeyIdentity, identity);
    expect(c.state.enabled, isTrue);
    expect(c.state.activeJourneyIdentity, identity);
  });

  for (final recovery in [
    (
      name: '0건',
      result: const ScheduleDeliveryResult(scheduledCount: 0, failedCount: 2),
    ),
    (
      name: '부분',
      result: const ScheduleDeliveryResult(scheduledCount: 1, failedCount: 1),
    ),
  ]) {
    test('disable clear 실패 뒤 ${recovery.name} 예약은 enabled로 복원하지 않는다', () async {
      final clearError = StateError('clear failed');
      final stateRepository = _RecordingStateRepository();
      final c = GetOffAlarmController(
        notifier: notifier,
        permissionGate: _StubExactAlarmGate(true),
        notificationPermissionProvider: _StubNotificationPermissionProvider(
          NotificationPermissionStatus.granted,
        ),
        repository: stateRepository,
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.enableJourney(
        identity: _journeyIdentity(),
        stops: stops(),
        transferAlarmEnabled: true,
      );
      stateRepository.clearError = clearError;
      notifier.result = recovery.result;

      await expectLater(c.disable(), throwsA(same(clearError)));

      expect(c.state.enabled, isFalse);
      expect(c.state.scheduledCount, 0);
      expect(c.state.activeJourneyIdentity, isNull);
      expect(notifier.cancelAllCount, greaterThanOrEqualTo(2));
    });
  }

  test('conditional Journey disable은 exact active identity에만 적용한다', () async {
    final c = controller(exactPermitted: true);
    final activeIdentity = _journeyIdentity();
    await c.enableJourney(
      identity: activeIdentity,
      stops: stops(),
      transferAlarmEnabled: true,
    );

    await c.disableJourneyIfActive(_journeyIdentity('other'));
    expect(c.state.activeJourneyIdentity, activeIdentity);

    await c.disableJourneyIfActive(activeIdentity);
    expect(c.state.enabled, isFalse);
    expect(await repository.loadActive(), isNull);
  });

  test('disable 복구 예약도 실패하면 복구 오류를 보고하고 원래 clear 오류를 보존한다', () async {
    final clearError = StateError('clear failed');
    final compensationError = StateError('reschedule failed');
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    stateRepository.clearError = clearError;
    notifier.scheduleError = compensationError;
    final reports = <FlutterErrorDetails>[];

    await expectLater(
      runWithMobileErrorReporter(reports.add, c.disable),
      throwsA(same(clearError)),
    );

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(compensationError));
    expect(reports.single.context.toString(), '하차 알림 끄기 실패 복구 중 예외가 발생했습니다.');
  });

  test('destination 스톱이 없으면 예약·저장 없이 조기 반환한다', () async {
    final c = controller(exactPermitted: true);

    await c.enable(
      routeId: 'r1',
      stops: [
        GetOffAlarmStop(
          stationId: 'transfer',
          stationName: '동작',
          arrivalAt: DateTime(2026, 7, 6, 9, 15, 0),
          kind: GetOffAlarmKind.transfer,
        ),
      ],
      transferAlarmEnabled: true,
    );

    expect(notifier.scheduledAlarms, isNull);
    expect(c.state.enabled, isFalse);
    expect(await repository.loadActive(), isNull);
  });

  test('restore는 영속된 활성 구독을 켜진 상태로 복원한다', () async {
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );

    final restored = controller(exactPermitted: true);
    await restored.restore();

    expect(restored.state.enabled, isTrue);
    expect(restored.state.activeRouteId, 'r1');
  });

  test('startup restore 예외는 앱 시작 경계 밖으로 전파하지 않는다', () async {
    final error = StateError('database unavailable');
    final startupController = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: _RecordingStateRepository(loadError: error),
      now: () => now,
    );
    addTearDown(startupController.dispose);
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(
      reports.add,
      () => app.restoreGetOffAlarmState(startupController),
    );

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(error));
    expect(reports.single.context.toString(), isNot(contains('route')));
  });

  test('foreground reconcile 예외는 lifecycle 경계 밖으로 전파하지 않는다', () async {
    final error = StateError('database unavailable');
    final foregroundController = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: _RecordingStateRepository(loadError: error),
      now: () => now,
    );
    addTearDown(foregroundController.dispose);
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(
      reports.add,
      () => app.reconcileGetOffAlarmState(foregroundController),
    );

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(error));
    expect(reports.single.context.toString(), isNot(contains('route')));
  });

  test('restore에서 active가 없으면 pending 알림과 저장값을 정리한다', () async {
    final stateRepository = _RecordingStateRepository();
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(notifier.cancelAllCount, 1);
    expect(stateRepository.clearCount, 1);
    expect(restored.state.enabled, isFalse);
  });

  test('진행 중 refresh 뒤 disable은 마지막 cancel clear off 상태를 보장한다', () async {
    final gate = _BlockingRefreshExactAlarmGate();
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    final refresh = c.refresh(routeId: 'r1', stops: stops());
    await gate.isPermittedStarted.future;
    final disable = c.disable();
    gate.permitted.complete(true);
    await Future.wait([refresh, disable]);

    expect(notifier.cancelAllCount, 1);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
    expect(c.state.activeRouteId, isNull);
  });

  test('disable 뒤 queued refresh는 off 상태를 재확인하고 no-op 한다', () async {
    final gate = _StubExactAlarmGate(true);
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: gate,
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);
    notifier.cancelBarrier = Completer<void>();

    final disable = c.disable();
    await Future<void>.delayed(Duration.zero);
    final refresh = c.refresh(routeId: 'r1', stops: stops());
    await Future<void>.delayed(Duration.zero);
    notifier.cancelBarrier!.complete();
    await Future.wait([disable, refresh]);

    expect(gate.isPermittedCalls, 0);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
  });

  test('앞선 mutation 오류가 다음 disable queue를 poison하지 않는다', () async {
    final stateRepository = _RecordingStateRepository();
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);
    notifier.cancelErrorOnce = StateError('cancel failed');

    await expectLater(c.disable(), throwsStateError);
    await c.disable();

    expect(notifier.cancelAllCount, 2);
    expect(stateRepository.active, isNull);
    expect(c.state.enabled, isFalse);
  });

  test('restore에서 만료 구독은 pending을 취소하고 구독을 삭제한다', () async {
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    // 저장된 도착 시각(9:15/9:30)이 모두 지난 시점으로 복원한다.
    final expired = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: repository,
      now: () => DateTime(2026, 7, 6, 10, 0, 0),
    );
    addTearDown(expired.dispose);
    notifier.cancelAllCount = 0;
    notifier.scheduleCalls = 0;

    await expired.restore();

    expect(notifier.cancelAllCount, 1);
    expect(notifier.scheduleCalls, 0);
    expect(await repository.loadActive(), isNull);
    expect(expired.state.enabled, isFalse);
  });

  test('알림 권한 거부 정리는 복구 안내 플래그를 기록하고 안내를 표시한다', () async {
    final store = _RecordingRecoveryNoticeStore();
    final first = controller(exactPermitted: true);
    await first.enableJourney(
      identity: _journeyIdentity(),
      stops: stops(),
      transferAlarmEnabled: true,
    );
    final denied = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.denied,
      ),
      repository: repository,
      recoveryNoticeStore: store,
      now: () => now,
    );
    addTearDown(denied.dispose);

    await denied.restore();

    expect(store.recordCount, 1);
    expect(await repository.loadActive(), isNull);
    expect(denied.state.enabled, isFalse);
    expect(denied.state.permissionNotice, '휴대전화 알림 권한을 허용해 주세요.');
  });

  test('다음 UI init은 기록된 복구 안내를 한 번 표시하고 플래그를 지운다', () async {
    final store = _RecordingRecoveryNoticeStore()..flag = true;
    final stateRepository = _RecordingStateRepository();
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      recoveryNoticeStore: store,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(restored.state.permissionNotice, '휴대전화 알림 권한을 허용해 주세요.');
    expect(store.flag, isFalse);

    // 두 번째 init은 더 이상 복구 안내를 표시하지 않는다(one-shot).
    await restored.restore();
    expect(restored.state.permissionNotice, isNull);
  });

  test('활성 구독 저장은 reconcile work를 등록하고 취소하지 않는다', () async {
    var activateCount = 0;
    var deactivateCount = 0;
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: repository,
      onActivateReconcileWork: () async => activateCount += 1,
      onDeactivateReconcileWork: () async => deactivateCount += 1,
      now: () => now,
    );
    addTearDown(c.dispose);

    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    expect(activateCount, 1);
    expect(deactivateCount, 0);
  });

  test('off 정리는 reconcile work를 취소한다', () async {
    var deactivateCount = 0;
    final c = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: repository,
      onActivateReconcileWork: () async {},
      onDeactivateReconcileWork: () async => deactivateCount += 1,
      now: () => now,
    );
    addTearDown(c.dispose);
    await c.enable(routeId: 'r1', stops: stops(), transferAlarmEnabled: true);

    await c.disable();

    expect(deactivateCount, greaterThanOrEqualTo(1));
  });

  test('사용자가 끈 구독(없음)은 복원하지 않는다', () async {
    final stateRepository = _RecordingStateRepository();
    var activateCount = 0;
    final restored = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmGate(true),
      notificationPermissionProvider: _StubNotificationPermissionProvider(
        NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      onActivateReconcileWork: () async => activateCount += 1,
      now: () => now,
    );
    addTearDown(restored.dispose);

    await restored.restore();

    expect(activateCount, 0);
    expect(notifier.scheduleCalls, 0);
    expect(restored.state.enabled, isFalse);
  });
}
