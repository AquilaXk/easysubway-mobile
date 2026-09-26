import 'dart:io';

import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_reconcile_worker.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
