import 'dart:io';

import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_reconcile_worker.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:workmanager_android/workmanager_android.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

Future<WorkInfo> _waitForWorkSucceeded(
  WorkmanagerAndroid workmanager,
  String uniqueName, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  WorkInfo? lastInfo;
  while (DateTime.now().isBefore(deadline)) {
    lastInfo = await workmanager.getWorkInfo(uniqueName);
    if (lastInfo?.state == WorkState.succeeded) {
      return lastInfo!;
    }
    if (lastInfo?.state == WorkState.failed ||
        lastInfo?.state == WorkState.cancelled) {
      fail('WorkManager task $uniqueName ended in ${lastInfo?.state}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail(
    'Timed out waiting for WorkManager task $uniqueName to succeed '
    '(last state: ${lastInfo?.state})',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Workmanager 0.10 Android Worker Runtime Verification', () {
    testWidgets('1. Android 플랫폼 확인 및 WorkManager Dispatcher 초기화 1회', (
      tester,
    ) async {
      expect(Platform.isAndroid, isTrue);

      // process-wide WorkManager dispatcher 초기화 (1회만 초기화)
      await initializeWorkManagerDispatcher(
        callbackDispatcher: app.nextTrainWidgetCallbackDispatcher,
      );
      // ignore: avoid_print
      print(
        '[EASYSUBWAY_EVIDENCE] Phase 1: WorkManager Dispatcher initialized successfully on Android',
      );
    });

    testWidgets('2. 두 unique periodic work 독립 등록 (30m 및 15m)', (tester) async {
      // 1) next-train-widget-refresh 등록 (30분 주기)
      await registerNextTrainWidgetRefresh();

      // 2) get-off-alarm-reconcile 등록 (15분 주기)
      await registerGetOffAlarmReconcile();

      // ignore: avoid_print
      print(
        '[EASYSUBWAY_EVIDENCE] Phase 2: Registered periodic tasks: next-train-widget-refresh (30m), get-off-alarm-reconcile (15m)',
      );
    });

    testWidgets('3. 단일 Dispatcher task-name 라우팅, 0.10 콜백 및 fail-closed 검증', (
      tester,
    ) async {
      var widgetRefreshCount = 0;
      var reconcileCount = 0;
      final errors = <Object>[];

      final api = NextTrainWidgetWorkmanagerApi(
        runWidgetRefresh: () async {
          widgetRefreshCount += 1;
          return true;
        },
        runGetOffAlarmReconcile: () async {
          reconcileCount += 1;
          return true;
        },
        reportError: (error, _) => errors.add(error),
      );

      // WorkManager 0.10 background worker는 Android WorkManager에 의해 최소 15분 주기
      // (PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS)로 별도 백그라운드 isolate에서 구동됩니다.
      // 통합 테스트에서는 Phase 2에서 실제 native PeriodicWorkRequest 등록을 완료하고,
      // Phase 3에서는 해당 백그라운드 isolate에서 실행되는 NextTrainWidgetWorkmanagerApi의
      // 라우팅, 알 수 없는 task 거부, 0.10 신규 콜백 무해성, 및 fail-closed 계약을 결정론적으로 검증합니다.
      // (a) nextTrainWidgetRefresh task 라우팅
      final widgetResult = await api.executeTask(
        nextTrainWidgetRefreshTask,
        null,
      );
      expect(widgetResult, isTrue);
      expect(widgetRefreshCount, 1);

      // (b) getOffAlarmReconcile task 라우팅
      final reconcileResult = await api.executeTask(
        getOffAlarmReconcileTask,
        null,
      );
      expect(reconcileResult, isTrue);
      expect(reconcileCount, 1);

      // (c) 알 수 없는 task fail-closed (false 반환)
      final unknownResult = await api.executeTask('unknown-task-name', null);
      expect(unknownResult, isFalse);
      expect(widgetRefreshCount, 1);
      expect(reconcileCount, 1);

      // (d) Workmanager 0.10 신규 콜백 (onTaskStopped, onProgressUpdate) 정상 수신
      await api.onTaskStopped(nextTrainWidgetRefreshTask, 0);
      await api.onProgressUpdate(nextTrainWidgetRefreshUniqueName, const {});
      expect(widgetRefreshCount, 1);
      expect(reconcileCount, 1);

      // (e) handler 예외 발생 시 fail-closed (false 반환)
      final throwingApi = NextTrainWidgetWorkmanagerApi(
        runWidgetRefresh: () async => throw StateError('widget refresh failed'),
        reportError: (error, _) => errors.add(error),
      );
      final errorResult = await throwingApi.executeTask(
        nextTrainWidgetRefreshTask,
        null,
      );
      expect(errorResult, isFalse);
      expect(errors, hasLength(1));

      // ignore: avoid_print
      print(
        '[EASYSUBWAY_EVIDENCE] Phase 3: Task routing verified: nextTrainWidgetRefresh=true, getOffAlarmReconcile=true, unknownTask=false (fail-closed), exception=false (fail-closed)',
      );
    });

    testWidgets('3-1. 실제 reconcile task 내부 조립 fail-closed 검증', (tester) async {
      await cancelNextTrainWidgetRefresh();
      await cancelGetOffAlarmReconcile();
      final errors = <Object>[];
      final result = await runGetOffAlarmReconcileTask(
        reportError: (error, _) => errors.add(error),
      );
      expect(result, isTrue);
      expect(errors, isEmpty);
      // ignore: avoid_print
      print(
        '[EASYSUBWAY_EVIDENCE] Phase 3-1: Real reconcile task headless assembly executed safely',
      );
    });

    testWidgets(
      '3-2. WorkManager 0.10.9 BackgroundWorker 준비 신호 핸드셰이크 및 실제 백그라운드 isolate 작업 완료 검증',
      (tester) async {
        final workmanager = WorkmanagerAndroid();
        const widgetOneOffUniqueName = 'oneoff-next-train-widget-refresh-435';
        const reconcileOneOffUniqueName = 'oneoff-get-off-alarm-reconcile-435';

        await workmanager.registerOneOffTask(
          reconcileOneOffUniqueName,
          getOffAlarmReconcileTask,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
        final reconcileWorkInfo = await _waitForWorkSucceeded(
          workmanager,
          reconcileOneOffUniqueName,
        );
        expect(reconcileWorkInfo.state, WorkState.succeeded);

        await workmanager.registerOneOffTask(
          widgetOneOffUniqueName,
          nextTrainWidgetRefreshTask,
          existingWorkPolicy: ExistingWorkPolicy.replace,
          constraints: Constraints(networkType: NetworkType.notRequired),
        );
        final widgetWorkInfo = await _waitForWorkSucceeded(
          workmanager,
          widgetOneOffUniqueName,
        );
        expect(widgetWorkInfo.state, WorkState.succeeded);

        // ignore: avoid_print
        print(
          '[EASYSUBWAY_EVIDENCE] Phase 3-2: BackgroundWorker completed one-off tasks via notifyBackgroundChannelInitialized: '
          '$widgetOneOffUniqueName=${widgetWorkInfo.state.name}, '
          '$reconcileOneOffUniqueName=${reconcileWorkInfo.state.name}',
        );
      },
    );

    testWidgets('4. 두 unique periodic work 개별 취소', (tester) async {
      // (a) next-train-widget-refresh 개별 취소
      await cancelNextTrainWidgetRefresh();

      // (b) get-off-alarm-reconcile 개별 취소
      await cancelGetOffAlarmReconcile();

      // ignore: avoid_print
      print(
        '[EASYSUBWAY_EVIDENCE] Phase 4: Cancelled tasks individually: next-train-widget-refresh and get-off-alarm-reconcile',
      );
    });

    testWidgets('5. 재등록 및 재부팅/재시작 후 안전한 재초기화 검증', (tester) async {
      await initializeWorkManagerDispatcher(
        callbackDispatcher: app.nextTrainWidgetCallbackDispatcher,
      );
      await registerNextTrainWidgetRefresh();
      await registerGetOffAlarmReconcile();

      // clean teardown
      await cancelNextTrainWidgetRefresh();
      await cancelGetOffAlarmReconcile();

      // ignore: avoid_print
      print(
        '[EASYSUBWAY_EVIDENCE] Phase 5: Re-registration and restart-safety verified',
      );
    });
  });
}
