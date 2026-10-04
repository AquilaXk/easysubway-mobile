import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/app/home_screen.dart';
import 'package:easysubway_mobile/features/journey/application/journey_search_controller.dart';
import 'package:easysubway_mobile/features/journey/domain/journey_repository.dart';
import 'package:easysubway_mobile/features/journey/presentation/journey_search_screen.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/generated/journey_v3/journey_v3_contract.dart';
import 'package:easysubway_mobile/core/crashlytics/crash_report_redaction.dart';
import 'package:easysubway_mobile/core/crashlytics/crashlytics_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home Journey station resolver는 exact ID만 이름으로 해소한다', () async {
    final resolver = journeyAlarmStationNameResolver(
      _StationRepository(_stationDetail('station-destination', '춘천')),
    );

    expect(await resolver('station-destination'), '춘천');

    final mismatched = journeyAlarmStationNameResolver(
      _StationRepository(_stationDetail('station-other', '다른 역')),
    );
    await expectLater(
      mismatched('station-destination'),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('complete draft는 server-order 후보를 보여주고 exact ID만 선택한다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository();
    final shared = <String>[];
    await _pumpScreen(
      tester,
      repository: repository,
      mobilityType: 'STANDARD',
      shareInvoker: (text, _) async => shared.add(text),
    );

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(repository.sessionRequests, 1);
    expect(repository.requests, hasLength(1));
    final request = repository.requests.single;
    expect(request.originStationId, 'station-origin');
    expect(request.destinationStationId, 'station-destination');
    expect(request.departure, isA<JourneyDepartureNow>());
    expect(request.timePolicy, TimePolicy.timetableRequired);
    expect(request.walkingPace, WalkingPace.standard);
    expect(request.mobilityProfile, MobilityProfile.standard);
    expect(request.constraintMode, ConstraintMode.none);
    expect(request.maxTransfers, 3);
    expect(request.alternativeCount, 3);
    expect(find.text('경로 후보 2개'), findsOneWidget);
    final second = find.byKey(const Key('journey-candidate-journey-1'));
    final first = find.byKey(const Key('journey-candidate-journey-2'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    // 후보는 서버 순서의 가로 탭이고, 첫 후보가 기본 선택된다.
    expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(find.text('09:00 출발 → 09:05 도착'), findsOneWidget);
    expect(find.textContaining('환승 2회'), findsOneWidget);
    expect(
      tester.getSemantics(first).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    expect(tester.getSize(second).height, greaterThanOrEqualTo(48));

    final candidateSemantics = tester.getSemantics(second);
    expect(
      candidateSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    candidateSemantics.owner!.performAction(
      candidateSemantics.id,
      SemanticsAction.tap,
    );
    await tester.pump();
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.byKey(const Key('selected-journey-journey-1')), findsOneWidget);
    await tester.pump();
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.byKey(const Key('selected-journey-detail')), findsOneWidget);
    final entry = find.byKey(const Key('selected-journey-leg-0'));
    final ride = find.byKey(const Key('selected-journey-leg-1'));
    final transfer = find.byKey(const Key('selected-journey-leg-2'));
    final exit = find.byKey(const Key('selected-journey-leg-3'));
    expect(tester.getTopLeft(entry).dy, lessThan(tester.getTopLeft(ride).dy));
    expect(
      tester.getTopLeft(ride).dy,
      lessThan(tester.getTopLeft(transfer).dy),
    );
    expect(
      tester.getTopLeft(transfer).dy,
      lessThan(tester.getTopLeft(exit).dy),
    );
    final shareButton = find.widgetWithText(OutlinedButton, '공유');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    expect(shared, hasLength(1));
    expect(shared.single, contains('용산역 → 춘천역'));
    expect(shared.single, contains('5분'));
    expect(shared.single, isNot(contains('카드')));
    expect(shared.single, isNot(contains('journey-1')));
    expect(shared.single, isNot(contains('query-1')));
    expect(shared.single, isNot(contains('bundle-1')));
    expect(shared.single, isNot(contains('station-origin')));
    expect(shared.single, isNot(contains('a' * 64)));

    await tester.pumpWidget(const SizedBox.shrink());
    final single = _Repository()..journeyIds = <String>['journey-only'];
    await _pumpScreen(tester, repository: single);
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 1개'), findsOneWidget);
    expect(
      find.byKey(const Key('journey-candidate-journey-only')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('걷는 속도는 표준으로 시작하고 선택마다 exact pace로 다시 검색한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository();
    await _pumpScreen(tester, repository: repository);

    expect(find.text('느린 걸음'), findsOneWidget);
    expect(find.text('표준 걸음'), findsOneWidget);
    expect(find.text('빠른 걸음'), findsOneWidget);
    final standard = find.byKey(const Key('walking-pace-standard'));
    expect(
      tester.getSemantics(standard).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    for (final pace in <String>['slow', 'standard', 'fast']) {
      expect(
        tester.getSize(find.byKey(Key('walking-pace-$pace'))).height,
        greaterThanOrEqualTo(60),
      );
    }

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(repository.requests.single.walkingPace, WalkingPace.standard);

    await tester.tap(find.byKey(const Key('walking-pace-slow')));
    await tester.pumpAndSettle();
    expect(repository.requests.last.walkingPace, WalkingPace.slow);
    expect(repository.requests.last.mobilityProfile, MobilityProfile.standard);
    expect(repository.requests.last.constraintMode, ConstraintMode.none);

    await tester.tap(find.byKey(const Key('walking-pace-fast')));
    await tester.pumpAndSettle();
    expect(repository.requests.last.walkingPace, WalkingPace.fast);
    expect(repository.requests, hasLength(3));
    semantics.dispose();
  });

  testWidgets('출발 시간은 exact SCHEDULED requestedAt으로 전송하고 모드 변경 시 이전 결과를 지운다', (
    tester,
  ) async {
    final repository = _Repository();
    final alarm = _AlarmHarness();
    addTearDown(alarm.dispose);
    await _pumpScreen(
      tester,
      repository: repository,
      getOffAlarmController: alarm.controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
    );

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 2개'), findsOneWidget);
    await alarm.controller.enable(
      routeId: 'scheduled-selection-alarm',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-destination',
          stationName: '춘천',
          arrivalAt: DateTime.utc(2026, 8, 12),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );

    final scheduled = find.byKey(const Key('journey-departure-scheduled'));
    expect(tester.getSize(scheduled).height, greaterThanOrEqualTo(48));
    await tester.tap(scheduled);
    await tester.pumpAndSettle();

    expect(alarm.notifier.cancelAllCount, 1);
    expect(find.text('경로 후보 2개'), findsNothing);
    expect(
      tester.getSemantics(scheduled).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '경로 찾기'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('journey-scheduled-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('출발 시간 선택'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journey-scheduled-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('출발 시간 선택'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journey-scheduled-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    expect(find.text('출발 시간 2026-08-12 09:00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    final departure = repository.requests.last.departure;
    expect(departure, isA<JourneyDepartureScheduled>());
    expect(
      (departure as JourneyDepartureScheduled).requestedAt,
      DateTime.utc(2026, 8, 12),
    );

    await tester.tap(find.byKey(const Key('journey-scheduled-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 2개'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journey-departure-now')));
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 2개'), findsNothing);
    expect(find.byKey(const Key('journey-scheduled-time')), findsNothing);
  });

  testWidgets('계단 회피 profile은 REQUIRE_STEP_FREE로 전송한다', (tester) async {
    final repository = _Repository();
    await _pumpScreen(tester, repository: repository, mobilityType: 'LUGGAGE');

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(
      repository.requests.single.mobilityProfile,
      MobilityProfile.noStairs,
    );
    expect(
      repository.requests.single.constraintMode,
      ConstraintMode.requireStepFree,
    );

    final stepFree = _Repository();
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, repository: stepFree, mobilityType: 'WHEELCHAIR');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(stepFree.requests.single.mobilityProfile, MobilityProfile.stepFree);
    expect(
      stepFree.requests.single.constraintMode,
      ConstraintMode.requireStepFree,
    );
  });

  // #441: 서버 계단 없는 대안 결과(backend #471)를 교통약자에게 구분해 안내한다.
  testWidgets('계단 정보를 확인할 수 없는 환승이 있으면 경로 후보 위에 안내하고 스크린리더로 읽힌다', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository()
      ..stairFreeAlternative = const JourneyStairFreeAlternative(
        status: JourneyStairFreeAlternativeStatus.undetermined,
        facilityStatus: JourneyStairFreeFacilityStatus.unobserved,
      );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(find.text('계단 없이 갈 수 있는지 확인하지 못했어요'), findsOneWidget);
    expect(
      find.text('계단 정보가 없는 환승 통로가 있어요. 출발 전에 환승역 엘리베이터 위치를 확인해 주세요.'),
      findsOneWidget,
    );
    // 결과에 계단 없는 여정이 없으므로 시설 미반영 안내는 붙이지 않는다.
    expect(find.text('엘리베이터 고장 정보는 반영하지 못했어요'), findsNothing);
    expect(
      find.bySemanticsLabel(
        '계단 없이 갈 수 있는지 확인하지 못했어요. 계단 정보가 없는 환승 통로가 있어요. 출발 전에 환승역 엘리베이터 위치를 확인해 주세요.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('journey-stair-status-notices')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('journey-candidate-journey-2')))
            .dy,
      ),
    );
    semantics.dispose();
  });

  testWidgets('계단 없는 경로가 없으면 없다고 알리고, 계단 없는 경로의 엘리베이터 고장 미반영을 알린다', (
    tester,
  ) async {
    final notFound = _Repository()
      ..stairFreeAlternative = const JourneyStairFreeAlternative(
        status: JourneyStairFreeAlternativeStatus.notFound,
        facilityStatus: JourneyStairFreeFacilityStatus.applied,
      );
    await _pumpScreen(tester, repository: notFound);
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('계단회피 경로가 없어요'), findsOneWidget);
    expect(find.text('찾은 경로는 모두 환승할 때 계단을 지나요.'), findsOneWidget);

    final unobserved = _Repository()
      ..journeyIds = <String>['journey-multileg']
      ..stairFreeAlternative = const JourneyStairFreeAlternative(
        status: JourneyStairFreeAlternativeStatus.included,
        facilityStatus: JourneyStairFreeFacilityStatus.unobserved,
      );
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, repository: unobserved);
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('계단회피 경로가 없어요'), findsNothing);
    expect(find.text('엘리베이터 고장 정보는 반영하지 못했어요'), findsOneWidget);

    final applied = _Repository()..journeyIds = <String>['journey-multileg'];
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, repository: applied);
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journey-stair-status-notices')), findsNothing);
  });

  for (final (mobilityType, profile) in [
    ('LUGGAGE', MobilityProfile.noStairs),
    ('WHEELCHAIR', MobilityProfile.stepFree),
  ]) {
    testWidgets(
      '$mobilityType 계단 없는 경로 요청이 422면 사실과 일반 경로 보기를 안내하고, 누르면 계단 여부를 표시한 일반 검색을 한다',
      (tester) async {
        final repository = _Repository()
          ..rejectionToThrow = _accessibilityConstraintRejection()
          ..stairFreeAlternative = const JourneyStairFreeAlternative(
            status: JourneyStairFreeAlternativeStatus.undetermined,
            facilityStatus: JourneyStairFreeFacilityStatus.unobserved,
          );
        await _pumpScreen(
          tester,
          repository: repository,
          mobilityType: mobilityType,
        );

        await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
        await tester.pumpAndSettle();

        expect(repository.requests.single.mobilityProfile, profile);
        expect(
          repository.requests.single.constraintMode,
          ConstraintMode.requireStepFree,
        );
        expect(find.text('계단 없이 갈 수 있는 경로를 찾지 못했어요.'), findsOneWidget);
        expect(find.text('계단 여부를 함께 표시한 일반 경로는 볼 수 있어요.'), findsOneWidget);
        expect(find.textContaining('검증'), findsNothing);
        final standardRoutes = find.widgetWithText(FilledButton, '일반 경로 보기');
        expect(standardRoutes, findsOneWidget);
        expect(tester.getSize(standardRoutes).height, greaterThanOrEqualTo(48));
        expect(find.widgetWithText(FilledButton, '다시 시도'), findsNothing);

        await tester.tap(standardRoutes);
        await tester.pumpAndSettle();

        expect(repository.requests, hasLength(2));
        // NO_STAIRS는 계약상 NONE과 함께 보낼 수 없다. 두 프로필 모두 계단 없는
        // 경로를 우선 고르는 STEP_FREE + NONE으로 계단 여부를 표시한 일반 경로를 받는다.
        expect(
          repository.requests.last.mobilityProfile,
          MobilityProfile.stepFree,
        );
        expect(repository.requests.last.constraintMode, ConstraintMode.none);
        expect(
          repository.requests.last.originStationId,
          repository.requests.first.originStationId,
        );
        expect(
          repository.requests.last.destinationStationId,
          repository.requests.first.destinationStationId,
        );
        expect(find.text('계단 없이 갈 수 있는 경로를 찾지 못했어요.'), findsNothing);
        expect(
          find.byKey(const Key('journey-candidate-journey-2')),
          findsOneWidget,
        );
        expect(find.text('계단 없이 갈 수 있는지 확인하지 못했어요'), findsOneWidget);
      },
    );
  }

  testWidgets('다른 후보·새 검색은 기존 Journey 알림 취소 성공 뒤에만 전환한다', (tester) async {
    final repository = _Repository();
    final alarm = _AlarmHarness();
    addTearDown(alarm.dispose);
    await _pumpScreen(
      tester,
      repository: repository,
      getOffAlarmController: alarm.controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
      getOffAlarmNow: () => DateTime.utc(2026, 8, 11, 23, 55),
    );
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    final selectedCandidate = find.byKey(
      const Key('journey-candidate-journey-1'),
    );
    await tester.ensureVisible(selectedCandidate);
    await tester.tap(selectedCandidate);
    await tester.pump();
    final alarmToggle = find.byKey(const Key('journey-get-off-alarm-toggle'));
    await tester.ensureVisible(alarmToggle);
    await tester.tap(alarmToggle);
    for (var index = 0; index < 4; index++) {
      await tester.pump();
    }
    await tester.runAsync(
      () => alarm.repository.saved.future.timeout(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    alarm.notifier.cancelErrorOnce = StateError('cancel failed');
    final otherCandidate = find.byKey(const Key('journey-candidate-journey-2'));
    await tester.ensureVisible(otherCandidate);
    await tester.tap(otherCandidate);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-journey-journey-1')), findsOneWidget);
    expect(find.text('기존 하차 알림을 끄지 못해 경로를 바꾸지 않았어요.'), findsOneWidget);

    final requestsBeforePace = repository.requests.length;
    alarm.notifier.cancelErrorOnce = StateError('cancel failed');
    final slowPace = find.byKey(const Key('walking-pace-slow'));
    await tester.ensureVisible(slowPace);
    await tester.tap(slowPace);
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(requestsBeforePace));
    expect(
      tester
          .getSemantics(find.byKey(const Key('walking-pace-standard')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    final currentCandidate = find.byKey(
      const Key('journey-candidate-journey-1'),
    );
    await tester.ensureVisible(currentCandidate);
    await tester.tap(currentCandidate);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('journey-alarm-transition-error')),
      findsNothing,
    );

    final requestsBefore = repository.requests.length;
    alarm.notifier.cancelErrorOnce = StateError('cancel failed');
    final searchButton = find.widgetWithText(FilledButton, '경로 찾기');
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(requestsBefore));
    expect(find.byKey(const Key('selected-journey-journey-1')), findsOneWidget);

    final nextCandidate = find.byKey(const Key('journey-candidate-journey-2'));
    alarm.notifier.cancelBarrier = Completer<void>();
    await tester.ensureVisible(nextCandidate);
    await tester.tap(nextCandidate);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    alarm.notifier.cancelBarrier!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-journey-journey-2')), findsOneWidget);
    expect(alarm.repository.active, isNull);
  });

  testWidgets('세션 발급 중에는 검색 진행 상태를 보여준다', (tester) async {
    final repository = _Repository();
    final session = Completer<JourneySessionResponse>();
    repository.sessionCompleter = session;
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    session.complete(_sessionResponse());
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 2개'), findsOneWidget);
  });

  testWidgets('validUntil 만료는 후보·선택 상세·공유 claim을 함께 제거한다', (tester) async {
    var current = DateTime.now().toUtc();
    final repository = _Repository()..responseNow = current;
    await _pumpScreen(
      tester,
      repository: repository,
      journeyNow: () => current,
    );

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journey-candidate-journey-1')));
    await tester.pump();

    expect(find.text('경로 후보 2개'), findsOneWidget);
    expect(find.byKey(const Key('selected-journey-detail')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '공유'), findsOneWidget);

    current = current.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));

    expect(find.text('경로 후보 2개'), findsNothing);
    expect(find.byKey(const Key('selected-journey-detail')), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '공유'), findsNothing);
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
  });

  testWidgets('resume은 forward clock correction 뒤 stale Journey claim을 제거한다', (
    tester,
  ) async {
    var current = DateTime.now().toUtc();
    final repository = _Repository()..responseNow = current;
    await _pumpScreen(
      tester,
      repository: repository,
      journeyNow: () => current,
    );

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.text('경로 후보 2개'), findsOneWidget);

    current = current.add(const Duration(minutes: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('경로 후보 2개'), findsNothing);
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
  });

  testWidgets('incomplete draft는 request를 만들지 않는다', (tester) async {
    final incomplete = _Repository();
    await _pumpScreen(
      tester,
      repository: incomplete,
      draft: const RouteDraft.empty(),
    );
    expect(find.text('출발역과 도착역을 다시 확인해 주세요.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(incomplete.requests, isEmpty);
  });

  testWidgets(
    'waypoint draft는 viaStationId를 포함하여 request를 전송하고 waypointLabel을 렌더링한다',
    (tester) async {
      final waypoint = _Repository();
      await _pumpScreen(
        tester,
        repository: waypoint,
        draft: _completeDraft(waypoint: _station('station-waypoint', '서울')),
      );
      expect(find.text('경유 서울역'), findsOneWidget);
      expect(find.text('출발역과 도착역을 다시 확인해 주세요.'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(waypoint.requests, hasLength(1));
      expect(waypoint.requests.single.viaStationId, 'station-waypoint');
      expect(waypoint.requests.single.originStationId, 'station-origin');
      expect(
        waypoint.requests.single.destinationStationId,
        'station-destination',
      );
    },
  );

  testWidgets('failure는 안전한 retry만 노출하고 명시 retry가 새 search를 실행한다', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (_) async => throw PlatformException(code: 'share_failed'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );
    final repository = _Repository()..failuresRemaining = 1;
    final alarm = _AlarmHarness();
    final crashlytics = _RecordingCrashlytics();
    replaceCrashlyticsGatewayForTest(crashlytics);
    addTearDown(resetCrashlyticsGateway);
    addTearDown(alarm.dispose);
    await _pumpScreen(
      tester,
      repository: repository,
      getOffAlarmController: alarm.controller,
      stationNameResolver: (stationId) async => '$stationId 이름',
    );

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, '다시 시도')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
    expect(crashlytics.errors, hasLength(1));
    expect(crashlytics.fatalFlags, <bool>[false]);
    expect(crashlytics.errors.single, isA<SanitizedCrashException>());
    expect(crashlytics.payload, contains('subsystem=app-report'));
    expect(crashlytics.payload, isNot(contains('private')));
    expect(crashlytics.payload, isNot(contains('station-origin')));
    expect(crashlytics.payload, isNot(contains('station-destination')));

    await alarm.controller.enable(
      routeId: 'retry-alarm',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-destination',
          stationName: '춘천',
          arrivalAt: DateTime.utc(2026, 8, 12, 0, 30),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );

    await tester.tap(find.widgetWithText(FilledButton, '다시 시도'));
    await tester.pumpAndSettle();

    expect(alarm.notifier.cancelAllCount, 1);
    expect(repository.sessionRequests, 1);
    expect(repository.requests, hasLength(2));
    expect(
      repository.requests.map((request) => request.walkingPace),
      everyElement(WalkingPace.standard),
    );
    expect(find.text('경로 후보 2개'), findsOneWidget);
    final candidate = find.byKey(const Key('journey-candidate-journey-1'));
    await tester.ensureVisible(candidate);
    await tester.tap(candidate);
    await tester.pump();
    final shareButton = find.widgetWithText(OutlinedButton, '공유');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsOneWidget);
    expect(
      tester.getSemantics(candidate).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('노외 환승은 시간에 따라 3단계 배지(녹색, 주황색, 빨간색) 및 분리 요금을 렌더링한다', (
    tester,
  ) async {
    final repository = _Repository();
    repository.journeyIds = <String>[
      'journey-oos-green',
      'journey-oos-amber',
      'journey-oos-red',
    ];
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    // 배지는 선택한 경로의 환승 노드에 붙는다. 탭을 바꿔 가며 확인한다.
    for (final (id, key, label) in <(String, String, String)>[
      ('journey-oos-green', 'out-of-station-badge-green', '노외 환승 (여유)'),
      ('journey-oos-amber', 'out-of-station-badge-amber', '노외 환승 (주의)'),
      ('journey-oos-red', 'out-of-station-badge-red', '노외 환승 (시간 초과)'),
    ]) {
      final candidate = find.byKey(Key('journey-candidate-$id'));
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pumpAndSettle();
      expect(find.byKey(Key(key)), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    }

    // 재승차 운임은 금액 없이 사실만 표시한다. 금액은 여정 총운임(fare)에만 있다(backend#444).
    expect(find.text('추가 요금 +1,400원'), findsNothing);
    expect(find.textContaining('추가 요금'), findsNothing);
  });

  testWidgets('재승차(farePenaltyApplies)면 환승 노드에 "재승차 운임 발생"만 표시한다', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repository = _Repository();
    repository.journeyIds = <String>[
      'journey-oos-green',
      'journey-oos-amber',
      'journey-oos-red',
    ];
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    const notice = Key('reboarding-fare-notice');
    for (final id in <String>['journey-oos-green', 'journey-oos-amber']) {
      final candidate = find.byKey(Key('journey-candidate-$id'));
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pumpAndSettle();
      expect(find.byKey(notice), findsNothing, reason: '$id: 재승차 아님');
      expect(find.text('재승차 운임 발생'), findsNothing);
    }

    final red = find.byKey(const Key('journey-candidate-journey-oos-red'));
    await tester.ensureVisible(red);
    await tester.tap(red);
    await tester.pumpAndSettle();
    expect(find.byKey(notice), findsOneWidget);
    expect(find.text('재승차 운임 발생'), findsOneWidget);
    expect(find.bySemanticsLabel('재승차 운임 발생'), findsOneWidget);
    expect(find.textContaining('원'), findsNothing);
    expect(
      find.byKey(const Key('out-of-station-fare-breakdown')),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets(
    '기후동행카드 등 정기권 보유 시(hasUnlimitedTransitPass: true) 빨간색 배지 대신 우회 텍스트를 렌더링한다',
    (tester) async {
      final repository = _Repository();
      repository.journeyIds = <String>['journey-oos-red'];
      await _pumpScreen(
        tester,
        repository: repository,
        hasUnlimitedTransitPass: true,
      );

      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('out-of-station-badge-red')), findsNothing);
      expect(
        find.byKey(const Key('out-of-station-badge-pass-override')),
        findsWidgets,
      );
      expect(find.text('노외 환승 (기후동행카드 적용)'), findsWidgets);
    },
  );

  testWidgets(
    '선택 경로 상세(selected-journey-detail)는 각 ride leg의 노선과 승하차역을 바인딩한다',
    (tester) async {
      final repository = _Repository();
      await _pumpScreen(
        tester,
        repository: repository,
        stationNameResolver: (stationId) async => switch (stationId) {
          'station-origin' => '시청역',
          'station-transfer' => '종로3가역',
          'station-destination' => '동대문역',
          _ => '$stationId 이름',
        },
      );

      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();

      // 기본 선택(첫 후보 journey-2)의 탑승 노드는 모르는 노선 ID를 그대로 보여 준다.
      expect(find.text('line-private'), findsOneWidget);
      expect(find.text('2호선'), findsNothing);

      await tester.tap(find.byKey(const Key('journey-candidate-journey-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('selected-journey-detail')), findsOneWidget);
      // 출발·환승·도착 노드가 역 이름에 바인딩된다.
      expect(
        find.descendant(
          of: find.byKey(const Key('selected-journey-leg-0')),
          matching: find.text('시청역'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('selected-journey-leg-2')),
          matching: find.text('종로3가역'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('selected-journey-leg-3')),
          matching: find.text('동대문역'),
        ),
        findsOneWidget,
      );
      // 탑승 노드가 노선명에 바인딩된다.
      expect(
        find.descendant(
          of: find.byKey(const Key('selected-journey-leg-1')),
          matching: find.text('2호선'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '백엔드 거절 응답(JourneyRejectedFailure) 시 canonicalKoreanCopy를 노출하고 FORBIDDEN 처분이면 재시도를 차단한다',
    (tester) async {
      final repository = _Repository();
      final error = JourneyV3Error(
        contractVersion: JourneyErrorContractVersion.journeyErrorV1,
        requestId: '01K1Y000000000000000000000',
        code: JourneyErrorCode.stationNotFound,
        retryable: false,
        occurredAt: DateTime.utc(2026, 8, 12),
      );
      final disposition = JourneyErrorDispositions.lookup(
        JourneyOperation.searchJourneys,
        404,
        JourneyErrorCode.stationNotFound,
      );
      repository.rejectionToThrow = JourneyRejectedFailure(
        JourneyOperation.searchJourneys,
        statusCode: 404,
        error: error,
        disposition: disposition,
      );

      await _pumpScreen(tester, repository: repository);
      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();

      // 서버의 정규화된 한국어 오류 메시지 노출 확인
      expect(find.text('선택한 역 정보를 찾을 수 없어요.'), findsOneWidget);
      // FORBIDDEN 처분이므로 '다시 시도' 버튼은 노출되지 않음
      expect(find.widgetWithText(FilledButton, '다시 시도'), findsNothing);
      // 대신 홈으로 돌아가거나 조건을 재선택하는 액션 버튼 노출
      expect(
        find.byKey(const Key('journey-failure-action-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('origin 또는 destination과 동일한 waypoint draft는 request를 차단한다', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpScreen(
      tester,
      repository: repository,
      draft: _completeDraft(waypoint: _station('station-origin', '출발역과동일')),
    );

    expect(find.text('출발역과 도착역을 다시 확인해 주세요.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repository.requests, isEmpty);
  });

  testWidgets(
    '특정 시간대 출발 대안 보기(departureWindow) 선택 시 Profile V1 DEPART_BETWEEN 쿼리를 실행한다',
    (tester) async {
      final repository = _Repository();
      await _pumpScreen(tester, repository: repository);

      final windowChip = find.byKey(const Key('journey-departure-window'));
      expect(tester.getSize(windowChip).height, greaterThanOrEqualTo(48));
      await tester.tap(windowChip);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(windowChip).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '경로 찾기'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('journey-window-time')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('대안 시간대'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();

      expect(repository.profileRequests, hasLength(1));
      final profileReq = repository.profileRequests.single;
      expect(profileReq.originStationId, 'station-origin');
      expect(profileReq.destinationStationId, 'station-destination');
      expect(profileReq.temporalQuery, isA<JourneyDepartBetweenQuery>());
      final temporal = profileReq.temporalQuery as JourneyDepartBetweenQuery;
      expect(
        temporal.latestReadyAt,
        temporal.earliestReadyAt.add(const Duration(minutes: 30)),
      );
      expect(find.text('경로 후보 2개'), findsOneWidget);
    },
  );

  testWidgets(
    '교통약자 안심 막차 찾기(Last Connection) 선택 시 Profile V1 LAST_CONNECTION 쿼리를 실행한다',
    (tester) async {
      final repository = _Repository();
      await _pumpScreen(tester, repository: repository);

      final lastConnChip = find.byKey(
        const Key('journey-departure-last-connection'),
      );
      expect(tester.getSize(lastConnChip).height, greaterThanOrEqualTo(48));
      await tester.tap(lastConnChip);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(lastConnChip).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '경로 찾기'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('journey-last-connection-date')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('막차 운행일'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
      await tester.pumpAndSettle();

      expect(repository.profileRequests, hasLength(1));
      final profileReq = repository.profileRequests.single;
      expect(profileReq.originStationId, 'station-origin');
      expect(profileReq.destinationStationId, 'station-destination');
      expect(profileReq.temporalQuery, isA<JourneyLastConnectionQuery>());
      final temporal = profileReq.temporalQuery as JourneyLastConnectionQuery;
      expect(temporal.serviceDate, '2026-08-12');
      expect(find.text('경로 후보 2개'), findsOneWidget);
    },
  );

  testWidgets('경로 입력 카드는 출발·경유·도착 배지와 출발 기준 칩을 보여 준다', (tester) async {
    final repository = _Repository();
    await _pumpScreen(
      tester,
      repository: repository,
      draft: _completeDraft(waypoint: _station('station-waypoint', '가평')),
    );

    expect(find.text('출발'), findsOneWidget);
    expect(find.text('경유'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(find.text('출발 용산역'), findsOneWidget);
    expect(find.text('경유 가평역'), findsOneWidget);
    expect(find.text('도착 춘천역'), findsOneWidget);
    expect(find.byKey(const Key('journey-departure-now')), findsOneWidget);
    expect(
      find.byKey(const Key('journey-departure-scheduled')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('journey-departure-window')), findsOneWidget);
    expect(
      find.byKey(const Key('journey-departure-last-connection')),
      findsOneWidget,
    );
  });

  testWidgets('journey search는 다중 구간 환승 경로에서 무단차 태그, 경강선 노선명을 지원한다', (
    tester,
  ) async {
    final repository = _Repository()..journeyIds = ['journey-multileg'];
    await _pumpScreen(tester, repository: repository, mobilityType: 'STANDARD');

    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(find.text('무단차'), findsOneWidget);
    expect(find.text('♿ 무단차 경로'), findsOneWidget);
    expect(find.text('경강선'), findsOneWidget);
    expect(find.text('2호선'), findsOneWidget);

    // 서버가 칸-문을 주지 않으면 탑승 위치 안내를 만들지 않는다.
    expect(find.textContaining('빠른 환승'), findsNothing);
    expect(find.textContaining('가까운 문'), findsNothing);
    expect(find.textContaining('빠른 하차'), findsNothing);
  });

  testWidgets('최소환승 태그 및 방향역 ID가 없는 여정 레그가 정상 렌더링된다', (tester) async {
    final repository = _Repository()
      ..journeyIds = <String>['journey-1', 'journey-least-transfer'];
    await _pumpScreen(tester, repository: repository, mobilityType: 'STANDARD');
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(find.text('최단시간'), findsOneWidget);
    expect(find.text('최소환승'), findsOneWidget);
    expect(find.textContaining('방면'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('journey-candidate-journey-least-transfer')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-journey-leg-1')), findsOneWidget);
    expect(find.textContaining('방면'), findsNothing);
  });

  testWidgets('(9) 경로 탭: 첫 후보를 기본 선택하고 탭을 바꾸면 상세가 바뀐다', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository()
      ..journeyIds = <String>['journey-spec', 'journey-spec-express'];
    await _pumpScreen(
      tester,
      repository: repository,
      stationNameResolver: _specStationName,
    );
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    final specTab = find.byKey(const Key('journey-candidate-journey-spec'));
    final expressTab = find.byKey(
      const Key('journey-candidate-journey-spec-express'),
    );
    expect(
      tester.getSemantics(specTab).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(expressTab).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    expect(find.text('최단시간'), findsOneWidget);
    expect(find.text('최소환승'), findsOneWidget);
    expect(find.text('무단차'), findsOneWidget);
    final detail = find.byKey(const Key('selected-journey-detail'));
    expect(
      find.descendant(of: detail, matching: find.text('35분')),
      findsOneWidget,
    );
    expect(find.text('09:00 출발 → 09:35 도착'), findsOneWidget);
    expect(find.text('환승 1회 · 카드 1,550원 · 도보 320m'), findsOneWidget);
    expect(find.text('빠른 환승 3-2'), findsOneWidget);
    expect(find.text('실시간 반영'), findsNothing);
    expect(find.text('♿ 무단차 경로'), findsNothing);

    await tester.tap(expressTab);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(expressTab).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(specTab).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    expect(
      find.descendant(of: detail, matching: find.text('40분')),
      findsOneWidget,
    );
    expect(find.text('09:01 출발 → 09:41 도착'), findsOneWidget);
    expect(find.text('실시간 반영'), findsOneWidget);
    // 운임이 없으면 운임 항목만 빠진다.
    expect(find.text('환승 없음 · 도보 150m'), findsOneWidget);
    expect(find.textContaining('카드'), findsNothing);
    expect(find.text('♿ 무단차 경로'), findsOneWidget);
    expect(find.text('급행'), findsOneWidget);
    expect(find.text('중앙보훈병원 방면'), findsOneWidget);
    expect(find.text('빠른 환승 3-2'), findsNothing);
    semantics.dispose();
  });

  testWidgets('(10) 정차역 토글은 경유역을 펼치고 접으며, 1개 역 이동은 펼침이 없다', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository()..journeyIds = <String>['journey-spec'];
    await _pumpScreen(
      tester,
      repository: repository,
      stationNameResolver: _specStationName,
    );
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('journey-ride-stops-toggle-1'));
    expect(toggle, findsOneWidget);
    expect(
      find.descendant(of: toggle, matching: find.text('5개 역 이동 · 12분')),
      findsOneWidget,
    );
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    expect(find.text('역삼'), findsNothing);
    var toggleSemantics = tester.getSemantics(toggle);
    expect(toggleSemantics.flagsCollection.isButton, isTrue);
    expect(toggleSemantics.flagsCollection.isExpanded, Tristate.isFalse);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    for (final (name, time) in <(String, String)>[
      ('역삼', '09:05'),
      ('선릉', '09:07'),
      ('삼성', '09:09'),
      ('종합운동장', '09:12'),
    ]) {
      expect(find.text(name), findsOneWidget);
      expect(find.text(time), findsOneWidget);
    }
    toggleSemantics = tester.getSemantics(toggle);
    expect(toggleSemantics.flagsCollection.isExpanded, Tristate.isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('역삼'), findsNothing);
    expect(
      tester.getSemantics(toggle).flagsCollection.isExpanded,
      Tristate.isFalse,
    );

    // 둘째 탑승은 정차역이 탑승·하차역뿐이라 펼침 없이 문구만 둔다.
    expect(find.byKey(const Key('journey-ride-stops-toggle-3')), findsNothing);
    expect(find.text('1개 역 이동 · 8분'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('(11)(12) 구간 막대·탭·요약·타임라인 Semantics 라벨이 정확하다', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository()
      ..journeyIds = <String>['journey-spec', 'journey-spec-express'];
    await _pumpScreen(
      tester,
      repository: repository,
      stationNameResolver: _specStationName,
    );
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('구간: 도보 2분, 2호선 12분, 환승 도보 3분, 3호선 8분, 도보 1분'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('최단시간, 35분, 환승 1회, 09:35 도착'), findsOneWidget);
    expect(
      find.bySemanticsLabel('최소환승, 무단차, 40분, 환승 없음, 09:41 도착'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '35분 소요, 09:00 출발, 09:35 도착, 환승 1회, 카드 1,550원, 도보 320m',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '2호선 교대 방면 탑승, 09:03 출발, 빠른 환승 3호차 2번 문, 5개 역 이동, 12분',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('강남, 09:00 출발, 승강장까지 도보 2분'), findsOneWidget);
    expect(find.bySemanticsLabel('교대 환승, 도보 3분'), findsOneWidget);
    // 노드 원 안의 노선 번호는 장식이라 따로 읽지 않는다.
    expect(find.bySemanticsLabel('2'), findsNothing);
    expect(find.bySemanticsLabel('양재, 09:35 도착, 출구까지 도보 1분'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('journey-candidate-journey-spec-express')),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('9호선 급행 중앙보훈병원 방면 탑승, 09:04 출발, 2개 역 이동, 10분'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '40분 소요, 09:01 출발, 09:41 도착, 환승 없음, 도보 150m, 실시간 반영',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('(13) 글자 2.0배에서 탭·요약·타임라인이 overflow 없이 48dp 터치 영역을 지킨다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = _Repository()
      ..journeyIds = <String>['journey-spec', 'journey-spec-express'];
    await _pumpScreen(
      tester,
      repository: repository,
      mobilityType: 'WHEELCHAIR',
      stationNameResolver: _specStationName,
    );
    final search = find.widgetWithText(FilledButton, '경로 찾기');
    await tester.ensureVisible(search);
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final id in <String>['journey-spec', 'journey-spec-express']) {
      final tab = find.byKey(Key('journey-candidate-$id'));
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(tab).width, greaterThanOrEqualTo(48));
    }
    final toggle = find.byKey(const Key('journey-ride-stops-toggle-1'));
    await tester.ensureVisible(toggle);
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final expressTab = find.byKey(
      const Key('journey-candidate-journey-spec-express'),
    );
    await tester.ensureVisible(expressTab);
    await tester.tap(expressTab);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('공유 문구는 운임이 있을 때만 카드 운임을 넣는다', (tester) async {
    final repository = _Repository()
      ..journeyIds = <String>['journey-spec', 'journey-spec-express'];
    final shared = <String>[];
    await _pumpScreen(
      tester,
      repository: repository,
      stationNameResolver: _specStationName,
      shareInvoker: (text, _) async => shared.add(text),
    );
    await tester.tap(find.widgetWithText(FilledButton, '경로 찾기'));
    await tester.pumpAndSettle();

    final shareButton = find.widgetWithText(OutlinedButton, '공유');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    expect(
      shared.last,
      '용산역 → 춘천역\n35분 · 환승 1회 · 카드 1,550원 · 09:35 도착 · 무단차 경로 아님',
    );

    final expressTab = find.byKey(
      const Key('journey-candidate-journey-spec-express'),
    );
    await tester.ensureVisible(expressTab);
    await tester.tap(expressTab);
    await tester.pumpAndSettle();
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    expect(shared.last, '용산역 → 춘천역\n40분 · 환승 없음 · 09:41 도착 · 무단차 경로');
  });
}

Future<String> _specStationName(String stationId) async => switch (stationId) {
  'st-gangnam' => '강남',
  'st-yeoksam' => '역삼',
  'st-seolleung' => '선릉',
  'st-samseong' => '삼성',
  'st-sports' => '종합운동장',
  'st-gyodae' => '교대',
  'st-yangjae' => '양재',
  'st-ogeum' => '오금',
  'st-sinnonhyeon' => '신논현',
  'st-express-mid' => '고속터미널',
  'st-dongjak' => '동작',
  'st-bohun' => '중앙보훈병원',
  _ => '$stationId 이름',
};

class _RecordingCrashlytics implements CrashlyticsGateway {
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

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _Repository repository,
  RouteDraft? draft,
  String mobilityType = 'STANDARD',
  JourneyShareInvoker? shareInvoker,
  GetOffAlarmController? getOffAlarmController,
  Future<String> Function(String stationId)? stationNameResolver,
  DateTime Function()? getOffAlarmNow,
  DateTime Function()? journeyNow,
  bool hasUnlimitedTransitPass = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: JourneySearchScreen(
        repository: repository,
        attestor: const _Attestor(),
        draft: draft ?? _completeDraft(),
        mobilityType: mobilityType,
        onShellBackToHome: () {},
        shareInvoker: shareInvoker,
        getOffAlarmController: getOffAlarmController,
        stationNameResolver: stationNameResolver,
        getOffAlarmNow: getOffAlarmNow,
        journeyNow: journeyNow ?? () => DateTime.utc(2026, 8, 12),
        hasUnlimitedTransitPass: hasUnlimitedTransitPass,
      ),
    ),
  );
}

RouteDraft _completeDraft({RouteDraftStation? waypoint}) => RouteDraft(
  origin: _station('station-origin', '용산'),
  destination: _station('station-destination', '춘천'),
  waypoint: waypoint,
  lastModifiedAt: DateTime.utc(2026, 8, 12),
);

RouteDraftStation _station(String id, String name) =>
    RouteDraftStation(id: id, nameKo: name);

class _Attestor implements JourneyV3IntegrityAttestor {
  const _Attestor();

  @override
  Future<String> attest(String requestHash) async => 'integrity-token';
}

class _Repository implements JourneyRepository {
  int sessionRequests = 0;
  int failuresRemaining = 0;
  JourneyRejectedFailure? rejectionToThrow;
  JourneyStairFreeAlternative stairFreeAlternative =
      const JourneyStairFreeAlternative(
        status: JourneyStairFreeAlternativeStatus.included,
        facilityStatus: JourneyStairFreeFacilityStatus.applied,
      );
  Completer<JourneySessionResponse>? sessionCompleter;
  DateTime? responseNow;
  List<String> journeyIds = <String>['journey-2', 'journey-1'];
  final List<JourneySearchRequest> requests = <JourneySearchRequest>[];
  final List<JourneyProfileRequest> profileRequests = <JourneyProfileRequest>[];

  @override
  Future<JourneySessionResponse> issueSession(
    JourneySessionRequest request,
  ) async {
    sessionRequests++;
    return sessionCompleter?.future ?? _sessionResponse(responseNow);
  }

  @override
  Future<JourneySearchSuccess> searchJourneys(
    JourneySearchRequest request, {
    required String sessionToken,
  }) async {
    requests.add(request);
    if (rejectionToThrow != null) {
      final rejection = rejectionToThrow!;
      rejectionToThrow = null;
      throw rejection;
    }
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const JourneyTransportFailure(
        JourneyOperation.searchJourneys,
        'private transport detail',
      );
    }
    return _success(
      request,
      journeyIds,
      now: responseNow,
      stairFreeAlternative: stairFreeAlternative,
    );
  }

  @override
  Future<JourneyProfileSuccess> profileJourneys(
    JourneyProfileRequest request, {
    required String sessionToken,
  }) async {
    profileRequests.add(request);
    if (rejectionToThrow != null) {
      final rejection = rejectionToThrow!;
      rejectionToThrow = null;
      throw rejection;
    }
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const JourneyTransportFailure(
        JourneyOperation.searchJourneys,
        'private transport detail',
      );
    }
    final responseTime = responseNow ?? DateTime.utc(2026, 8, 12);
    return JourneyProfileSuccess(
      contractVersion: 'JOURNEY_PROFILE_V1',
      requestId: request.requestId,
      queryId: 'profile-query-1',
      calculatedAt: responseTime,
      validUntil: responseTime.add(const Duration(minutes: 5)),
      temporalQuery: request.temporalQuery,
      serviceDayCutoff: '03:00',
      journeys: journeyIds
          .map(
            (id) => JourneyProfileJourneyCandidate(
              journeyId: id,
              readyAt: responseTime,
              journeyStartTime: responseTime,
              firstBoardingTime: responseTime,
              arrivalAtPlatform: responseTime.add(const Duration(minutes: 5)),
              arrivalAtDestination: responseTime.add(
                const Duration(minutes: 5),
              ),
              objectiveTags: const ['PROFILE_TEST'],
              journey: _journey(id, responseTime),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<StationTimetableSearchSuccess> searchStationTimetables(
    StationTimetableSearchRequest request, {
    required String sessionToken,
  }) async => throw const JourneyTransportFailure(
    JourneyOperation.searchStationTimetables,
    'unused in journey screen test',
  );
}

JourneyRejectedFailure _accessibilityConstraintRejection() =>
    JourneyRejectedFailure(
      JourneyOperation.searchJourneys,
      statusCode: 422,
      error: JourneyV3Error(
        contractVersion: JourneyErrorContractVersion.journeyErrorV1,
        requestId: '01K1Y000000000000000000000',
        code: JourneyErrorCode.accessibilityConstraintUnsatisfied,
        retryable: false,
        occurredAt: DateTime.utc(2026, 8, 12),
      ),
      disposition: JourneyErrorDispositions.lookup(
        JourneyOperation.searchJourneys,
        422,
        JourneyErrorCode.accessibilityConstraintUnsatisfied,
      ),
    );

JourneySessionResponse _sessionResponse([DateTime? issuedAt]) {
  final now = issuedAt ?? DateTime.utc(2026, 8, 12);
  return JourneySessionResponse(
    token: 'session-token',
    scope: JourneySessionScope.journeyV3,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
  );
}

JourneySearchSuccess _success(
  JourneySearchRequest request,
  List<String> journeyIds, {
  DateTime? now,
  JourneyStairFreeAlternative stairFreeAlternative =
      const JourneyStairFreeAlternative(
        status: JourneyStairFreeAlternativeStatus.included,
        facilityStatus: JourneyStairFreeFacilityStatus.applied,
      ),
}) {
  final responseNow = now ?? DateTime.utc(2026, 8, 12);
  return JourneySearchSuccess(
    contractVersion: JourneyContractVersion.journeySearchV3,
    requestId: request.requestId,
    queryId: 'query-1',
    calculatedAt: responseNow,
    validUntil: responseNow.add(const Duration(minutes: 5)),
    effectiveDepartureTime: responseNow,
    serviceDate: JourneyDate.parse('2026-08-12'),
    serviceTimezone: 'Asia/Seoul',
    serviceDayCutoff: '03:00',
    stairFreeAlternative: stairFreeAlternative,
    sourceIdentity: JourneySourceIdentity(
      routeBundleId: 'bundle-1',
      routeBundleSha256: 'a' * 64,
      timetableSnapshotId: 'timetable-1',
      accessibilitySnapshotId: 'accessibility-1',
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
    journeys: journeyIds
        .map((id) => _journey(id, responseNow))
        .toList(growable: false),
  );
}

Journey _journey(String id, DateTime now) {
  if (id == 'journey-spec') return _specJourney(now);
  if (id == 'journey-spec-express') return _specExpressJourney(now);
  final JourneyTransferLeg transferLeg;
  if (id == 'journey-oos-green') {
    transferLeg = const JourneyTransferLeg(
      fromStationId: 'station-transfer',
      toStationId: 'station-destination',
      durationSeconds: 15 * 60,
      transferType: 'OUT_OF_STATION',
    );
  } else if (id == 'journey-oos-amber') {
    transferLeg = const JourneyTransferLeg(
      fromStationId: 'station-transfer',
      toStationId: 'station-destination',
      durationSeconds: 25 * 60,
      transferType: 'OUT_OF_STATION',
    );
  } else if (id == 'journey-oos-red') {
    transferLeg = const JourneyTransferLeg(
      fromStationId: 'station-transfer',
      toStationId: 'station-destination',
      durationSeconds: 40 * 60,
      transferType: 'OUT_OF_STATION',
      farePenaltyApplies: true,
    );
  } else {
    transferLeg = const JourneyTransferLeg(
      fromStationId: 'station-transfer',
      toStationId: 'station-destination',
      durationSeconds: 60,
    );
  }

  if (id == 'journey-multileg') {
    return Journey(
      journeyId: id,
      status: JourneyStatus.found,
      planSource: JourneyPlanSource.serverTimetableRaptor,
      plannedDepartureTime: now,
      plannedArrivalTime: now.add(const Duration(minutes: 20)),
      realtimeDepartureTime: null,
      realtimeArrivalTime: null,
      durationSeconds: 1200,
      transferCount: 1,
      walkingDistanceMeters: 50,
      timeSource: JourneyTimeSource.timetable,
      accessibility: const JourneyAccessibility(
        result: JourneyAccessibilityResult.verified,
        stairFree: true,
        reasonCodes: <String>[],
      ),
      legs: <JourneyLeg>[
        const JourneyEntryLeg(
          fromStationId: 'station-origin',
          durationSeconds: 60,
        ),
        JourneyRideLeg(
          lineId: 'gyeonggang',
          tripId: 'trip-1',
          directionStationId: 'station-direction',
          fromStationId: 'station-origin',
          toStationId: 'station-transfer',
          plannedDepartureTime: now,
          plannedArrivalTime: now.add(const Duration(minutes: 10)),
          realtimeDepartureTime: null,
          realtimeArrivalTime: null,
          servicePattern: JourneyServicePattern.local,
          stops: <JourneyRideStop>[
            JourneyRideStop(
              stationId: 'station-origin',
              plannedArrivalTime: null,
              plannedDepartureTime: now,
              realtimeArrivalTime: null,
              realtimeDepartureTime: null,
            ),
            JourneyRideStop(
              stationId: 'station-transfer',
              plannedArrivalTime: now.add(const Duration(minutes: 10)),
              plannedDepartureTime: null,
              realtimeArrivalTime: null,
              realtimeDepartureTime: null,
            ),
          ],
        ),
        const JourneyTransferLeg(
          fromStationId: 'station-transfer',
          toStationId: 'station-destination',
          durationSeconds: 120,
        ),
        JourneyRideLeg(
          lineId: 'line-2',
          tripId: 'trip-2',
          directionStationId: 'station-direction',
          fromStationId: 'station-transfer',
          toStationId: 'station-destination',
          plannedDepartureTime: now.add(const Duration(minutes: 12)),
          plannedArrivalTime: now.add(const Duration(minutes: 18)),
          realtimeDepartureTime: null,
          realtimeArrivalTime: null,
          servicePattern: JourneyServicePattern.local,
          stops: <JourneyRideStop>[
            JourneyRideStop(
              stationId: 'station-transfer',
              plannedArrivalTime: null,
              plannedDepartureTime: now.add(const Duration(minutes: 12)),
              realtimeArrivalTime: null,
              realtimeDepartureTime: null,
            ),
            JourneyRideStop(
              stationId: 'station-destination',
              plannedArrivalTime: now.add(const Duration(minutes: 18)),
              plannedDepartureTime: null,
              realtimeArrivalTime: null,
              realtimeDepartureTime: null,
            ),
          ],
        ),
        const JourneyExitLeg(
          fromStationId: 'station-destination',
          durationSeconds: 60,
        ),
      ],
      fare: const JourneyFare(
        status: JourneyFareStatus.unavailable,
        sourceSnapshotIds: <String>[],
      ),
    );
  }

  return Journey(
    journeyId: id,
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now,
    plannedArrivalTime: now.add(const Duration(minutes: 5)),
    realtimeDepartureTime: null,
    realtimeArrivalTime: null,
    durationSeconds: id == 'journey-least-transfer'
        ? 900
        : (id.startsWith('journey-oos-') ? 1800 : 300),
    transferCount: id == 'journey-1'
        ? 2
        : (id.startsWith('journey-oos-') ? 1 : 0),
    walkingDistanceMeters: 0,
    timeSource: JourneyTimeSource.timetable,
    accessibility: const JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: false,
      reasonCodes: <String>[],
    ),
    legs: <JourneyLeg>[
      const JourneyEntryLeg(
        fromStationId: 'station-origin',
        durationSeconds: 60,
      ),
      JourneyRideLeg(
        lineId: id == 'journey-1' ? 'line-2' : 'line-private',
        tripId: 'trip-private',
        directionStationId: id == 'journey-least-transfer'
            ? ''
            : 'station-direction',
        fromStationId: 'station-origin',
        toStationId: 'station-transfer',
        plannedDepartureTime: now,
        plannedArrivalTime: now.add(const Duration(minutes: 3)),
        realtimeDepartureTime: null,
        realtimeArrivalTime: null,
        servicePattern: JourneyServicePattern.local,
        stops: <JourneyRideStop>[
          JourneyRideStop(
            stationId: 'station-origin',
            plannedArrivalTime: null,
            plannedDepartureTime: now,
            realtimeArrivalTime: null,
            realtimeDepartureTime: null,
          ),
          JourneyRideStop(
            stationId: 'station-transfer',
            plannedArrivalTime: now.add(const Duration(minutes: 3)),
            plannedDepartureTime: null,
            realtimeArrivalTime: null,
            realtimeDepartureTime: null,
          ),
        ],
      ),
      transferLeg,
      const JourneyExitLeg(
        fromStationId: 'station-destination',
        durationSeconds: 60,
      ),
    ],
    fare: const JourneyFare(
      status: JourneyFareStatus.unavailable,
      sourceSnapshotIds: <String>[],
    ),
  );
}

JourneyRideStop _stopAt(
  String stationId, {
  DateTime? plannedArrival,
  DateTime? plannedDeparture,
  DateTime? realtimeArrival,
  DateTime? realtimeDeparture,
}) => JourneyRideStop(
  stationId: stationId,
  plannedArrivalTime: plannedArrival,
  plannedDepartureTime: plannedDeparture,
  realtimeArrivalTime: realtimeArrival,
  realtimeDepartureTime: realtimeDeparture,
);

/// 강남 → (2호선 교대 방면, 5개 역) → 교대 환승 → (3호선 오금 방면, 1개 역) → 양재
Journey _specJourney(DateTime now) {
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));
  return Journey(
    journeyId: 'journey-spec',
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now,
    plannedArrivalTime: at(35),
    realtimeDepartureTime: null,
    realtimeArrivalTime: null,
    durationSeconds: 2100,
    transferCount: 1,
    walkingDistanceMeters: 320,
    timeSource: JourneyTimeSource.timetable,
    accessibility: const JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: false,
      reasonCodes: <String>[],
    ),
    legs: <JourneyLeg>[
      const JourneyEntryLeg(fromStationId: 'st-gangnam', durationSeconds: 120),
      JourneyRideLeg(
        lineId: 'line-2',
        tripId: 'trip-2',
        directionStationId: 'st-gyodae',
        fromStationId: 'st-gangnam',
        toStationId: 'st-gyodae',
        plannedDepartureTime: at(3),
        plannedArrivalTime: at(15),
        realtimeDepartureTime: null,
        realtimeArrivalTime: null,
        servicePattern: JourneyServicePattern.local,
        stops: <JourneyRideStop>[
          _stopAt('st-gangnam', plannedDeparture: at(3)),
          _stopAt('st-yeoksam', plannedArrival: at(5), plannedDeparture: at(5)),
          _stopAt(
            'st-seolleung',
            plannedArrival: at(7),
            plannedDeparture: at(7),
          ),
          _stopAt(
            'st-samseong',
            plannedArrival: at(9),
            plannedDeparture: at(9),
          ),
          _stopAt(
            'st-sports',
            plannedArrival: at(12),
            plannedDeparture: at(12),
          ),
          _stopAt('st-gyodae', plannedArrival: at(15)),
        ],
        alightingCarDoors: const <JourneyAlightingCarDoor>[
          JourneyAlightingCarDoor(
            carNumber: 3,
            doorNumber: 2,
            targetFacilityType: AlightingTargetFacilityType.transfer,
          ),
        ],
      ),
      const JourneyTransferLeg(
        fromStationId: 'st-gyodae',
        toStationId: 'st-gyodae',
        durationSeconds: 180,
      ),
      JourneyRideLeg(
        lineId: 'line-3',
        tripId: 'trip-3',
        directionStationId: 'st-ogeum',
        fromStationId: 'st-gyodae',
        toStationId: 'st-yangjae',
        plannedDepartureTime: at(26),
        plannedArrivalTime: at(34),
        realtimeDepartureTime: null,
        realtimeArrivalTime: null,
        servicePattern: JourneyServicePattern.local,
        stops: <JourneyRideStop>[
          _stopAt('st-gyodae', plannedDeparture: at(26)),
          _stopAt('st-yangjae', plannedArrival: at(34)),
        ],
      ),
      const JourneyExitLeg(fromStationId: 'st-yangjae', durationSeconds: 60),
    ],
    fare: const JourneyFare(
      status: JourneyFareStatus.available,
      adultCardWon: 1550,
      adultCashWon: 1650,
      sourceSnapshotIds: <String>['fare-snapshot-1'],
    ),
  );
}

/// 신논현 → (9호선 급행 중앙보훈병원 방면, 2개 역) → 동작, 실시간·무단차·운임 없음
Journey _specExpressJourney(DateTime now) {
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));
  return Journey(
    journeyId: 'journey-spec-express',
    status: JourneyStatus.found,
    planSource: JourneyPlanSource.serverTimetableRaptor,
    plannedDepartureTime: now,
    plannedArrivalTime: at(40),
    realtimeDepartureTime: at(1),
    realtimeArrivalTime: at(41),
    durationSeconds: 2400,
    transferCount: 0,
    walkingDistanceMeters: 150,
    timeSource: JourneyTimeSource.realtime,
    accessibility: const JourneyAccessibility(
      result: JourneyAccessibilityResult.verified,
      stairFree: true,
      reasonCodes: <String>[],
    ),
    legs: <JourneyLeg>[
      const JourneyEntryLeg(
        fromStationId: 'st-sinnonhyeon',
        durationSeconds: 180,
      ),
      JourneyRideLeg(
        lineId: 'line-9',
        tripId: 'trip-9',
        directionStationId: 'st-bohun',
        fromStationId: 'st-sinnonhyeon',
        toStationId: 'st-dongjak',
        plannedDepartureTime: at(3),
        plannedArrivalTime: at(13),
        realtimeDepartureTime: at(4),
        realtimeArrivalTime: at(14),
        servicePattern: JourneyServicePattern.express,
        stops: <JourneyRideStop>[
          _stopAt(
            'st-sinnonhyeon',
            plannedDeparture: at(3),
            realtimeDeparture: at(4),
          ),
          _stopAt(
            'st-express-mid',
            plannedArrival: at(7),
            realtimeArrival: at(8),
          ),
          _stopAt(
            'st-dongjak',
            plannedArrival: at(13),
            realtimeArrival: at(14),
          ),
        ],
        boardingPlatformGaps: const <JourneyPlatformGap>[
          JourneyPlatformGap(
            platformPosition: '급행 승강장 3-2',
            carNumber: 3,
            doorNumber: 2,
            gapGrade: PlatformGapGrade.narrow,
            heightDiffGrade: PlatformHeightDiffGrade.low,
            curved: false,
          ),
          JourneyPlatformGap(
            platformPosition: '급행 승강장 6-4',
            carNumber: 6,
            doorNumber: 4,
            gapGrade: PlatformGapGrade.wide,
            heightDiffGrade: PlatformHeightDiffGrade.normal,
            curved: true,
          ),
        ],
        alightingPlatformGaps: const <JourneyPlatformGap>[
          JourneyPlatformGap(
            platformPosition: '동작 하차 1-1',
            carNumber: 1,
            doorNumber: 1,
            gapGrade: PlatformGapGrade.wide,
            heightDiffGrade: PlatformHeightDiffGrade.high,
            curved: false,
          ),
        ],
      ),
      const JourneyExitLeg(fromStationId: 'st-dongjak', durationSeconds: 120),
    ],
    fare: const JourneyFare(
      status: JourneyFareStatus.unavailable,
      sourceSnapshotIds: <String>[],
    ),
  );
}

class _AlarmHarness {
  _AlarmHarness() {
    controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: const _AlarmExactGate(),
      notificationPermissionProvider: const _AlarmPermission(),
      repository: repository,
      now: () => DateTime.utc(2026, 8, 11, 23, 55),
    );
  }

  final notifier = _AlarmNotifier();
  final repository = _AlarmRepository();
  late final GetOffAlarmController controller;

  void dispose() => controller.dispose();
}

class _AlarmNotifier implements GetOffAlarmNotifier {
  Object? cancelErrorOnce;
  Completer<void>? cancelBarrier;
  int cancelAllCount = 0;

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    final error = cancelErrorOnce;
    cancelErrorOnce = null;
    if (error != null) throw error;
    await cancelBarrier?.future;
  }

  @override
  Future<int> pendingAlarmCount() async => 0;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async =>
      ScheduleDeliveryResult(scheduledCount: alarms.length, failedCount: 0);
}

class _AlarmRepository implements GetOffAlarmStateRepository {
  GetOffAlarmSubscription? active;
  final saved = Completer<void>();

  @override
  Future<void> clearActive() async => active = null;

  @override
  Future<GetOffAlarmSubscription?> loadActive() async => active;

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {
    active = subscription;
    if (!saved.isCompleted) saved.complete();
  }
}

class _AlarmExactGate implements ExactAlarmPermissionGate {
  const _AlarmExactGate();

  @override
  Future<bool> isExactAlarmPermitted() async => true;

  @override
  Future<bool> requestExactAlarmPermission() async => true;
}

class _AlarmPermission implements NotificationPermissionProvider {
  const _AlarmPermission();

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async =>
      NotificationPermissionStatus.granted;
}

StationDetail _stationDetail(String id, String nameKo) => StationDetail(
  id: id,
  nameKo: nameKo,
  nameEn: nameKo,
  region: '수도권',
  dataQualityLevel: 'VERIFIED',
  lastVerifiedAt: '2026-08-12T00:00:00Z',
  lines: const [],
);

class _StationRepository implements StationSearchRepository {
  _StationRepository(this.detail);

  final StationDetail detail;

  @override
  Future<StationDetail> getStationDetail(String stationId) async => detail;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
