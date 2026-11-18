import 'dart:convert';

import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UserDatabase db;
  late DriftGetOffAlarmStateRepository repository;

  setUp(() {
    db = UserDatabase.memory();
    repository = DriftGetOffAlarmStateRepository(userDatabase: db);
  });

  tearDown(() async {
    await db.close();
  });

  JourneyAlarmSubscriptionIdentity identity(
    String journeyId, {
    bool realtime = false,
    WalkingPace walkingPace = WalkingPace.standard,
  }) => JourneyAlarmSubscriptionIdentity(
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
      realtimeSnapshotId: realtime ? 'realtime-1' : null,
    ),
    requestPolicy: JourneyRequestPolicy(
      timePolicy: realtime
          ? TimePolicy.realtimeRequired
          : TimePolicy.timetableRequired,
      walkingPace: walkingPace,
      mobilityProfile: MobilityProfile.standard,
      constraintMode: ConstraintMode.none,
      maxTransfers: 3,
      alternativeCount: 3,
    ),
  );

  GetOffAlarmSubscription subscriptionFor(String journeyId) =>
      GetOffAlarmSubscription(
        routeId: journeyId,
        journeyIdentity: identity(journeyId),
        transferAlarmEnabled: true,
        scheduledCount: 2,
        scheduleMode: GetOffAlarmScheduleMode.inexact,
        inexactNotice: '정확 알람 권한이 없어 오차가 있을 수 있어요.',
        destination: GetOffAlarmStopRef(
          stationId: 'dest',
          stationName: '사당',
          arrivalAt: DateTime.utc(2026, 7, 6, 9, 30),
        ),
        transfers: [
          GetOffAlarmStopRef(
            stationId: 'transfer',
            stationName: '동작',
            arrivalAt: DateTime.utc(2026, 7, 6, 9, 15),
          ),
        ],
      );

  final subscription = subscriptionFor('journey-1');

  Future<void> writeRaw(Map<String, Object?> value) async {
    await db
        .into(db.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            key: 'get_off_alarm_active',
            value: jsonEncode(value),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );
  }

  test('활성 구독이 없으면 null을 돌려준다', () async {
    expect(await repository.loadActive(), isNull);
  });

  test('저장한 활성 구독을 그대로 다시 읽는다', () async {
    expect(subscription.toJson().containsKey('routeId'), isFalse);
    expect(subscription.toJson()['selectedJourneyId'], 'journey-1');
    await repository.saveActive(subscription);

    final loaded = await repository.loadActive();
    expect(loaded, isNotNull);
    expect(loaded!.routeId, 'journey-1');
    expect(loaded.journeyIdentity, identity('journey-1'));
    expect(loaded.transferAlarmEnabled, isTrue);
    expect(loaded.scheduledCount, 2);
    expect(loaded.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(loaded.inexactNotice, contains('오차'));
    expect(loaded.destination.stationName, '사당');
    expect(loaded.destination.arrivalAt, DateTime.utc(2026, 7, 6, 9, 30));
    expect(loaded.transfers, hasLength(1));
    expect(loaded.transfers.single.stationId, 'transfer');
  });

  test('identity parser는 malformed를 거부하고 realtime·hash equality를 보존한다', () {
    final malformed = identity('journey-1').toJson()
      ..['serviceDate'] = 'not-a-date';
    expect(JourneyAlarmSubscriptionIdentity.fromJson(malformed), isNull);

    final expected = identity('journey-realtime', realtime: true);
    final restored = JourneyAlarmSubscriptionIdentity.fromJson(
      expected.toJson(),
    );
    expect(restored, expected);
    expect(restored.hashCode, expected.hashCode);
  });

  test('기존 five-key V1 alarm policy는 STANDARD로 migration한다', () async {
    final legacy =
        jsonDecode(jsonEncode(subscription.toJson())) as Map<String, Object?>;
    final journeyIdentity = legacy['journeyIdentity']! as Map<String, Object?>;
    final requestPolicy =
        journeyIdentity['requestPolicy']! as Map<String, Object?>;
    requestPolicy.remove('walkingPace');
    await writeRaw(legacy);

    final loaded = await repository.loadActive();

    expect(loaded, isNotNull);
    expect(
      loaded!.journeyIdentity!.requestPolicy.walkingPace,
      WalkingPace.standard,
    );
    expect(
      (loaded.journeyIdentity!.toJson()['requestPolicy']!
          as Map<String, Object?>)['walkingPace'],
      'STANDARD',
    );
    expect(
      loaded.journeyIdentity,
      isNot(identity('journey-1', walkingPace: WalkingPace.fast)),
    );
  });

  test('legacy migration은 exact five-key policy에만 허용한다', () {
    Map<String, Object?> legacyPolicy() {
      final encoded =
          jsonDecode(jsonEncode(identity('journey-1').toJson()))
              as Map<String, Object?>;
      final policy = encoded['requestPolicy']! as Map<String, Object?>;
      policy.remove('walkingPace');
      return encoded;
    }

    final extra = legacyPolicy();
    (extra['requestPolicy']! as Map<String, Object?>)['unexpected'] = true;
    final missing = legacyPolicy();
    (missing['requestPolicy']! as Map<String, Object?>).remove('timePolicy');
    final unknown = identity('journey-1').toJson();
    (unknown['requestPolicy']! as Map<String, Object?>)['walkingPace'] =
        'UNKNOWN';

    expect(JourneyAlarmSubscriptionIdentity.fromJson(extra), isNull);
    expect(JourneyAlarmSubscriptionIdentity.fromJson(missing), isNull);
    expect(JourneyAlarmSubscriptionIdentity.fromJson(unknown), isNull);
  });

  test('단일 활성 구독 — 새로 저장하면 이전 것을 대체한다', () async {
    await repository.saveActive(subscription);
    await repository.saveActive(
      GetOffAlarmSubscription(
        routeId: 'journey-2',
        journeyIdentity: identity('journey-2'),
        transferAlarmEnabled: false,
        scheduledCount: 1,
        scheduleMode: GetOffAlarmScheduleMode.exact,
        inexactNotice: null,
        destination: GetOffAlarmStopRef(
          stationId: 'd2',
          stationName: '서울역',
          arrivalAt: DateTime.utc(2026, 7, 6, 10, 0),
        ),
        transfers: const [],
      ),
    );

    final loaded = await repository.loadActive();
    expect(loaded!.routeId, 'journey-2');
    expect(loaded.transferAlarmEnabled, isFalse);
    expect(loaded.scheduledCount, 1);
    expect(loaded.transfers, isEmpty);
  });

  test('scheduleMode와 inexactNotice를 복원한다', () async {
    await writeRaw({
      ...subscription.toJson(),
      'scheduleMode': 'inexact',
      'inexactNotice': '정확 알람 권한이 없어 오차가 있을 수 있어요.',
    });

    final loaded = await repository.loadActive();

    expect(loaded, isNotNull);
    expect(loaded!.scheduleMode, GetOffAlarmScheduleMode.inexact);
    expect(loaded.inexactNotice, '정확 알람 권한이 없어 오차가 있을 수 있어요.');
  });

  test('non-list transfers 손상값은 active subscription을 폐기한다', () async {
    await writeRaw({
      ...subscription.toJson(),
      'transferAlarmEnabled': false,
      'scheduledCount': 1,
      'transfers': <String, Object?>{},
    });

    expect(await repository.loadActive(), isNull);
  });

  test('closed current schema에서 scheduledCount가 없으면 폐기한다', () async {
    final currentSchema = subscription.toJson()..remove('scheduledCount');
    await writeRaw(currentSchema);

    expect(await repository.loadActive(), isNull);
  });

  test('identity 없는 과거 routeId JSON은 current success로 복원하지 않는다', () async {
    final routeOnly = subscription.toJson()
      ..remove('schemaVersion')
      ..remove('journeyIdentity')
      ..remove('selectedJourneyId')
      ..['routeId'] = 'journey-1';
    await writeRaw(routeOnly);

    expect(await repository.loadActive(), isNull);
  });

  test('unknown top-level field나 route/identity 불일치는 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'unknown': true});
    expect(await repository.loadActive(), isNull);

    await writeRaw({
      ...subscription.toJson(),
      'selectedJourneyId': 'journey-other',
    });
    expect(await repository.loadActive(), isNull);
  });

  test('scheduleMode 없는 실제 legacy 구독은 positive restore하지 않는다', () async {
    await writeRaw({
      'routeId': 'legacy-route',
      'transferAlarmEnabled': true,
      'destination': {
        'stationId': 'dest',
        'stationName': '사당',
        'arrivalAtEpochMs': DateTime.utc(
          2026,
          7,
          6,
          9,
          30,
        ).millisecondsSinceEpoch,
      },
      'transfers': [
        {
          'stationId': 'transfer',
          'stationName': '동작',
          'arrivalAtEpochMs': DateTime.utc(
            2026,
            7,
            6,
            9,
            15,
          ).millisecondsSinceEpoch,
        },
      ],
    });

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount 문자열은 손상 구독으로 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': '1'});

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount null은 legacy 누락으로 보지 않고 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': null});

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount 0은 비활성 구독으로 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': 0});

    expect(await repository.loadActive(), isNull);
  });

  test('scheduledCount가 구독 최대 예약 수를 넘으면 폐기한다', () async {
    await writeRaw({...subscription.toJson(), 'scheduledCount': 3});

    expect(await repository.loadActive(), isNull);
  });

  test('clearActive 후에는 활성 구독이 없다', () async {
    await repository.saveActive(subscription);
    await repository.clearActive();

    expect(await repository.loadActive(), isNull);
  });
}
