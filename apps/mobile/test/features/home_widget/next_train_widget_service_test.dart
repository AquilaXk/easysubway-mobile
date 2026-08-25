import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_reconcile_worker.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_configuration_screen.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_service.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android runtime bindings는 host와 Android plugin 진입을 모두 결정론적으로 실행한다',
    () async {
      var initialized = 0;
      var registered = 0;
      var cancelled = 0;
      final android = NextTrainWidgetAndroidBindings(
        isAndroid: () => true,
        initialize: (_) async => initialized += 1,
        register: () async => registered += 1,
        cancel: () async => cancelled += 1,
        installedWidgetIds: () async => const [42],
        clicks: () => Stream.value(Uri.parse('easysubway://station/sadang')),
      );

      await initializeWorkManagerDispatcher(
        callbackDispatcher: () {},
        bindings: android,
      );
      await registerNextTrainWidgetRefresh(bindings: android);
      await cancelNextTrainWidgetRefresh(bindings: android);
      await initializeAndRegisterNextTrainWidgetRefresh(
        callbackDispatcher: () {},
        bindings: android,
      );

      expect(initialized, 2);
      expect(registered, 2);
      expect(cancelled, 1);
      expect(await installedNextTrainWidgetIds(bindings: android), [42]);
      expect(
        await homeWidgetClicks(
          bindings: android,
        ).map((uri) => uri.toString()).toList(),
        ['easysubway://station/sadang'],
      );
    },
  );

  test('non-Android runtime bindings는 plugin 작업을 시작하지 않는다', () async {
    final host = NextTrainWidgetAndroidBindings(
      isAndroid: () => false,
      initialize: (_) => throw StateError('must not initialize'),
      register: () => throw StateError('must not register'),
      cancel: () => throw StateError('must not cancel'),
      installedWidgetIds: () => throw StateError('must not list'),
      clicks: () => Stream.error(StateError('must not listen')),
    );

    await initializeWorkManagerDispatcher(
      callbackDispatcher: () {},
      bindings: host,
    );
    await registerNextTrainWidgetRefresh(bindings: host);
    await cancelNextTrainWidgetRefresh(bindings: host);
    expect(await installedNextTrainWidgetIds(bindings: host), isEmpty);
    expect(await homeWidgetClicks(bindings: host).toList(), isEmpty);
  });

  test(
    'host refresh는 injected non-Android와 기본 host 경로 모두 plugin 없이 종료한다',
    () async {
      final catalog = CatalogDatabase.memory();
      final user = UserDatabase.memory();
      addTearDown(catalog.close);
      addTearDown(user.close);
      final repository = NextTrainWidgetRepository(
        catalogDatabase: catalog,
        userDatabase: user,
        timetableRepository: _NoopTimetableRepository(),
      );
      final host = NextTrainWidgetAndroidBindings(
        isAndroid: () => false,
        initialize: (_) => throw StateError('must not initialize'),
        register: () => throw StateError('must not register'),
        cancel: () => throw StateError('must not cancel'),
        installedWidgetIds: () => throw StateError('must not list'),
        clicks: () => Stream.error(StateError('must not listen')),
      );

      await refreshNextTrainWidgets(
        repository,
        widgetIds: const [42],
        bindings: host,
      );
      await refreshNextTrainWidgets(repository, widgetIds: const [42]);
    },
  );

  test(
    'Android refresh는 injected platform에서 explicit widget IDs만 실행한다',
    () async {
      final catalog = CatalogDatabase.memory();
      final user = UserDatabase.memory();
      addTearDown(catalog.close);
      addTearDown(user.close);
      final repository = NextTrainWidgetRepository(
        catalogDatabase: catalog,
        userDatabase: user,
        timetableRepository: _NoopTimetableRepository(),
      );
      final android = NextTrainWidgetAndroidBindings(
        isAndroid: () => true,
        initialize: (_) async {},
        register: () async {},
        cancel: () async {},
        installedWidgetIds: () async => const [],
        clicks: Stream.empty,
      );

      await refreshNextTrainWidgets(
        repository,
        widgetIds: const [],
        now: DateTime.utc(2026, 8, 11),
        bindings: android,
      );
    },
  );

  test(
    'headless refresh는 injected open, create, refresh, close 순서를 보장한다',
    () async {
      final catalog = CatalogDatabase.memory();
      final user = UserDatabase.memory();
      addTearDown(catalog.close);
      addTearDown(user.close);
      var opened = 0;
      var created = 0;
      var refreshed = 0;
      var closed = 0;

      expect(
        await runHeadlessNextTrainWidgetRefresh(
          createTimetableRepository: () {
            created += 1;
            return _NoopTimetableRepository();
          },
          openDatabases: () async {
            opened += 1;
            return (catalog: catalog, user: user);
          },
          refresh: (repository) async {
            refreshed += 1;
            expect(repository.catalogDatabase, same(catalog));
            expect(repository.userDatabase, same(user));
          },
          closeDatabases: ({required catalog, required user}) async {
            closed += 1;
          },
        ),
        isTrue,
      );

      expect((opened, created, refreshed, closed), (1, 1, 1, 1));
    },
  );

  test(
    'headless refresh 실패도 injected database close 후 typed error를 전달한다',
    () async {
      final catalog = CatalogDatabase.memory();
      final user = UserDatabase.memory();
      addTearDown(catalog.close);
      addTearDown(user.close);
      var closed = 0;

      await expectLater(
        runHeadlessNextTrainWidgetRefresh(
          createTimetableRepository: _NoopTimetableRepository.new,
          openDatabases: () async => (catalog: catalog, user: user),
          refresh: (_) async => throw StateError('headless refresh failed'),
          closeDatabases: ({required catalog, required user}) async {
            closed += 1;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(closed, 1);
    },
  );

  test(
    'widget configuration은 injected catalog open/close와 registration을 실행한다',
    () async {
      final catalog = CatalogDatabase.memory();
      final user = UserDatabase.memory();
      addTearDown(catalog.close);
      addTearDown(user.close);
      await _seedWidgetCatalog(catalog);
      Widget? capturedApp;
      var created = 0;
      var opened = 0;
      var closed = 0;
      var registered = 0;
      var finished = 0;
      var updated = 0;
      final stored = <String, Object?>{};

      await configureMain(
        createTimetableRepository: () {
          created += 1;
          return _AvailableTimetableRepository();
        },
        initializeAndRegisterRefresh: () async => registered += 1,
        readWidgetId: () async => '42',
        runWidgetApp: (widget) => capturedApp = widget,
        openDatabases: () async {
          opened += 1;
          return (catalog: catalog, user: user);
        },
        closeDatabases: ({required catalog, required user}) async {
          closed += 1;
        },
        saveWidgetValue: (key, value) async => stored[key] = value,
        updateNativeWidget: () async => updated += 1,
        finishConfiguration: () async => finished += 1,
      );

      final screen =
          (capturedApp! as MaterialApp).home!
              as NextTrainWidgetConfigurationScreen;
      expect(await screen.loadSelections(), isEmpty);
      await screen.configure(_selection);

      expect(
        (opened, created, closed, updated, registered, finished),
        (2, 2, 2, 1, 1, 1),
      );
      expect(stored['widget_42_station_id'], 'station-sadang');
    },
  );

  test('widget configuration은 widget ID 부재를 typed failure로 종료한다', () async {
    await expectLater(
      configureMain(
        createTimetableRepository: _NoopTimetableRepository.new,
        initializeAndRegisterRefresh: () async {},
        readWidgetId: () async => null,
        runWidgetApp: (_) => throw StateError('must not launch'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'configuration 완료 실패는 current pending widget뿐일 때 host refresh를 취소한다',
    () async {
      final catalog = CatalogDatabase.memory();
      final user = UserDatabase.memory();
      addTearDown(catalog.close);
      addTearDown(user.close);
      await _seedWidgetCatalog(catalog);
      Widget? capturedApp;
      var registered = 0;
      var closed = 0;

      await configureMain(
        createTimetableRepository: _AvailableTimetableRepository.new,
        initializeAndRegisterRefresh: () async => registered += 1,
        readWidgetId: () async => '42',
        runWidgetApp: (widget) => capturedApp = widget,
        openDatabases: () async => (catalog: catalog, user: user),
        closeDatabases: ({required catalog, required user}) async =>
            closed += 1,
        saveWidgetValue: (_, _) async {},
        updateNativeWidget: () async {},
        finishConfiguration: () async => throw StateError('finish failed'),
      );

      final screen =
          (capturedApp! as MaterialApp).home!
              as NextTrainWidgetConfigurationScreen;
      await expectLater(
        screen.configure(_selection),
        throwsA(isA<StateError>()),
      );

      expect(registered, 1);
      expect(closed, 1);
    },
  );

  test('위젯 startup plugin 실패를 보고하고 core startup은 계속한다', () async {
    final errors = <Object>[];
    var refreshed = false;

    await runNextTrainWidgetStartup(
      installedWidgetIds: () async => const [42],
      registerRefresh: () async => throw StateError('plugin unavailable'),
      cancelRefresh: () async {},
      refresh: (_) async => refreshed = true,
      reportError: (error, _) => errors.add(error),
    );

    expect(errors.single, isA<StateError>());
    expect(refreshed, isTrue);
  });

  test('설치 widget이 없으면 startup은 periodic을 취소하고 등록하지 않는다', () async {
    var registerCount = 0;
    var cancelCount = 0;
    var refreshCount = 0;

    await runNextTrainWidgetStartup(
      installedWidgetIds: () async => const [],
      registerRefresh: () async => registerCount += 1,
      cancelRefresh: () async => cancelCount += 1,
      refresh: (_) async => refreshCount += 1,
      reportError: (_, _) {},
    );

    expect(registerCount, 0);
    expect(cancelCount, 1);
    expect(refreshCount, 0);
  });

  test('설치 widget이 있으면 startup은 periodic을 등록하고 해당 ID를 갱신한다', () async {
    var registerCount = 0;
    var cancelCount = 0;
    List<int>? refreshedWidgetIds;

    await runNextTrainWidgetStartup(
      installedWidgetIds: () async => const [42],
      registerRefresh: () async => registerCount += 1,
      cancelRefresh: () async => cancelCount += 1,
      refresh: (widgetIds) async => refreshedWidgetIds = widgetIds,
      reportError: (_, _) {},
    );

    expect(registerCount, 1);
    expect(cancelCount, 0);
    expect(refreshedWidgetIds, [42]);
  });

  test('direct configuration 성공은 구성 뒤 periodic을 등록하고 완료한다', () async {
    final events = <String>[];

    await configureNextTrainWidgetSelection(
      selection: _selection,
      configure: (_) async => events.add('configure'),
      registerRefresh: () async => events.add('register'),
      finish: () async => events.add('finish'),
      cancelRefresh: () async => events.add('cancel'),
    );

    expect(events, ['configure', 'register', 'finish']);
  });

  test('direct configuration 구성 실패는 periodic을 등록하거나 취소하지 않는다', () async {
    var registerCount = 0;
    var cancelCount = 0;
    var finishCount = 0;

    await expectLater(
      configureNextTrainWidgetSelection(
        selection: _selection,
        configure: (_) async => throw StateError('configure failed'),
        registerRefresh: () async => registerCount += 1,
        finish: () async => finishCount += 1,
        cancelRefresh: () async => cancelCount += 1,
      ),
      throwsA(isA<StateError>()),
    );

    expect(registerCount, 0);
    expect(cancelCount, 0);
    expect(finishCount, 0);
  });

  test('direct configuration 완료 실패는 등록한 periodic을 취소한다', () async {
    var registerCount = 0;
    var cancelCount = 0;

    await expectLater(
      configureNextTrainWidgetSelection(
        selection: _selection,
        configure: (_) async {},
        registerRefresh: () async => registerCount += 1,
        finish: () async => throw StateError('finish failed'),
        cancelRefresh: () async => cancelCount += 1,
      ),
      throwsA(isA<StateError>()),
    );

    expect(registerCount, 1);
    expect(cancelCount, 1);
  });

  test('완료 실패에서 current pending widget만 있으면 periodic을 취소한다', () {
    expect(
      shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
        installedWidgetIds: const [42],
        configuringWidgetId: 42,
      ),
      isTrue,
    );
  });

  test('완료 실패에서 installed widget이 없으면 periodic을 취소한다', () {
    expect(
      shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
        installedWidgetIds: const [],
        configuringWidgetId: 42,
      ),
      isTrue,
    );
  });

  test('완료 실패에서 다른 정상 widget이 있으면 periodic을 유지한다', () {
    expect(
      shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
        installedWidgetIds: const [7, 42],
        configuringWidgetId: 42,
      ),
      isFalse,
    );
  });

  test('configuration operation 오류에서도 resource를 한 번 닫는다', () async {
    var closeCount = 0;

    await expectLater(
      runNextTrainWidgetConfigurationOperation<void>(
        operation: () async => throw StateError('configure failed'),
        close: () async => closeCount += 1,
      ),
      throwsA(isA<StateError>()),
    );

    expect(closeCount, 1);
  });

  test('widget id가 없으면 configuration을 열지 않는다', () async {
    var launched = false;

    await expectLater(
      launchNextTrainWidgetConfiguration(
        readWidgetId: () async => null,
        launch: (_) async => launched = true,
      ),
      throwsA(isA<StateError>()),
    );

    expect(launched, isFalse);
  });

  test('알 수 없는 WorkManager task는 fail-closed로 false를 돌려준다', () async {
    var widgetRan = false;
    var reconcileRan = false;
    final worker = NextTrainWidgetWorkmanagerApi(
      runWidgetRefresh: () async {
        widgetRan = true;
        return true;
      },
      runGetOffAlarmReconcile: () async {
        reconcileRan = true;
        return true;
      },
    );

    expect(await worker.executeTask('other-task', null), isFalse);
    expect(widgetRan, isFalse);
    expect(reconcileRan, isFalse);
  });

  test('단일 dispatcher가 task 이름별로 각 handler에 라우팅한다', () async {
    final calls = <String>[];
    final worker = NextTrainWidgetWorkmanagerApi(
      runWidgetRefresh: () async {
        calls.add('widget');
        return true;
      },
      runGetOffAlarmReconcile: () async {
        calls.add('reconcile');
        return true;
      },
    );

    expect(await worker.executeTask(nextTrainWidgetRefreshTask, null), isTrue);
    expect(await worker.executeTask(getOffAlarmReconcileTask, null), isTrue);
    expect(calls, ['widget', 'reconcile']);
  });

  test(
    'injected headless facade runs once and keeps unavailable widget output explicit',
    () async {
      final stored = <String, Object?>{
        'widget_42_direction_1': '상록수 방면',
        'widget_42_departure_1': '09:12',
        'widget_42_direction_2': '사당 방면',
        'widget_42_departure_2': '09:18',
      };
      var facadeCalls = 0;
      final service = NextTrainWidgetService(
        load: (selection, now) async =>
            NextTrainWidgetData.unavailable(selection, now),
        saveValue: (key, value) async => stored[key] = value,
        updateWidget: () async {},
      );
      final previousInstaller = app.debugMainNextTrainWidgetCallbackInstaller;
      final previousRefresh = app.debugMainHeadlessWidgetRefresh;
      Future<bool> Function()? injectedRefresh;
      app.debugMainNextTrainWidgetCallbackInstaller =
          ({required runWidgetRefresh}) {
            injectedRefresh = runWidgetRefresh;
          };
      app.debugMainHeadlessWidgetRefresh = () async {
        facadeCalls += 1;
        await service.refresh(
          appWidgetId: 42,
          selection: _selection,
          now: DateTime(2027, 1, 1, 9),
        );
        return true;
      };
      try {
        app.nextTrainWidgetCallbackDispatcher();
        expect(await injectedRefresh!(), isTrue);
        expect(facadeCalls, 1);
        expect(stored['widget_42_status'], 'timetableUnavailable');
        expect(stored['widget_42_direction_1'], '');
        expect(stored['widget_42_departure_1'], '');
        expect(stored['widget_42_direction_2'], '');
        expect(stored['widget_42_departure_2'], '');
      } finally {
        app.debugMainNextTrainWidgetCallbackInstaller = previousInstaller;
        app.debugMainHeadlessWidgetRefresh = previousRefresh;
      }
    },
  );

  test('configure는 widget id별 시간표 snapshot을 저장하고 provider를 갱신한다', () async {
    final stored = <String, Object?>{};
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (_, _) async => _availableData,
      saveValue: (key, value) async => stored[key] = value,
      updateWidget: () async => updateCount += 1,
    );

    await service.configure(
      appWidgetId: 42,
      selection: _selection,
      now: DateTime(2026, 7, 10, 9),
    );

    expect(stored, {
      'widget_42_station_id': 'station-sadang',
      'widget_42_line_id': 'seoul-4',
      'widget_42_station_name': '사당',
      'widget_42_line_name': '수도권 4호선',
      'widget_42_direction_1': '상록수 방면',
      'widget_42_departure_1': '09:12',
      'widget_42_direction_2': '사당 방면',
      'widget_42_departure_2': '09:18',
      'widget_42_status': 'available',
      'widget_42_status_label': '시간표 기준',
      'widget_42_updated_at': '2026-07-10T09:00:00.000',
    });
    expect(updateCount, 1);
  });

  test('시간표 unavailable 선택은 저장하지 않는다', () async {
    final stored = <String, Object?>{};
    final service = NextTrainWidgetService(
      load: (selection, now) async =>
          NextTrainWidgetData.unavailable(selection, now),
      saveValue: (key, value) async => stored[key] = value,
      updateWidget: () async {},
    );

    await expectLater(
      service.configure(
        appWidgetId: 42,
        selection: _selection,
        now: DateTime(2027, 1, 1, 9),
      ),
      throwsA(isA<StateError>()),
    );
    expect(stored, isEmpty);
  });

  test('available이어도 한 방향뿐이면 configure는 저장하거나 갱신하지 않는다', () async {
    var saveCount = 0;
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (_, _) async => NextTrainWidgetData(
        selection: _selection,
        status: NextTrainWidgetStatus.available,
        directions: [_availableData.directions.first],
        statusLabel: '시간표 기준',
        updatedAt: DateTime(2026, 7, 10, 9),
      ),
      saveValue: (_, _) async => saveCount += 1,
      updateWidget: () async => updateCount += 1,
    );

    await expectLater(
      service.configure(
        appWidgetId: 42,
        selection: _selection,
        now: DateTime(2026, 7, 10, 9),
      ),
      throwsA(isA<StateError>()),
    );
    expect(saveCount, 0);
    expect(updateCount, 0);
  });

  test('기존 widget refresh는 unavailable 상태를 정직하게 저장한다', () async {
    final stored = <String, Object?>{
      'widget_42_direction_1': '상록수 방면',
      'widget_42_departure_1': '09:12',
      'widget_42_direction_2': '사당 방면',
      'widget_42_departure_2': '09:18',
      'widget_42_status': 'available',
    };
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (selection, now) async =>
          NextTrainWidgetData.unavailable(selection, now),
      saveValue: (key, value) async => stored[key] = value,
      updateWidget: () async => updateCount += 1,
    );

    await service.refresh(
      appWidgetId: 42,
      selection: _selection,
      now: DateTime(2027, 1, 1, 9),
    );

    expect(stored['widget_42_status'], 'timetableUnavailable');
    expect(stored['widget_42_status_label'], '시간표를 확인할 수 없어요.');
    expect(stored['widget_42_direction_1'], '');
    expect(stored['widget_42_departure_1'], '');
    expect(stored['widget_42_direction_2'], '');
    expect(stored['widget_42_departure_2'], '');
    expect(updateCount, 1);
  });

  test('설치 widget 중 완전한 station-line 선택만 갱신한다', () async {
    final values = <String, String>{
      'widget_42_station_id': 'station-sadang',
      'widget_42_line_id': 'seoul-4',
      'widget_42_station_name': '사당',
      'widget_42_line_name': '수도권 4호선',
    };
    final loaded = <WidgetStationSelection>[];
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (selection, _) async {
        loaded.add(selection);
        return _availableData;
      },
      saveValue: (_, _) async {},
      updateWidget: () async => updateCount += 1,
    );

    await refreshInstalledNextTrainWidgets(
      widgetIds: const [42, 43],
      readValue: (key) async => values[key],
      service: service,
      now: DateTime(2026, 7, 10, 9),
    );

    expect(loaded.single.stationId, 'station-sadang');
    expect(updateCount, 1);
  });

  test('한 widget 설정 읽기 실패 뒤에도 나머지를 갱신하고 전체 작업은 실패한다', () async {
    final values = _twoWidgetValues();
    final loaded = <String>[];
    final service = NextTrainWidgetService(
      load: (selection, _) async {
        loaded.add(selection.stationId);
        return _availableData;
      },
      saveValue: (_, _) async {},
      updateWidget: () async {},
    );

    await expectLater(
      refreshInstalledNextTrainWidgets(
        widgetIds: const [42, 43],
        readValue: (key) async {
          if (key == 'widget_42_station_id') {
            throw StateError('read failed');
          }
          return values[key];
        },
        service: service,
        now: DateTime(2026, 7, 10, 9),
      ),
      throwsA(
        isA<StateError>()
            .having((error) => error.toString(), 'context', contains('42'))
            .having(
              (error) => error.toString(),
              'cause',
              contains('read failed'),
            ),
      ),
    );
    expect(loaded, ['station-b']);
  });

  test('한 widget refresh 실패 뒤에도 나머지를 갱신하고 전체 작업은 실패한다', () async {
    final values = _twoWidgetValues();
    final loaded = <String>[];
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (selection, _) async {
        loaded.add(selection.stationId);
        if (selection.stationId == 'station-a') {
          throw StateError('refresh failed');
        }
        return _availableData;
      },
      saveValue: (_, _) async {},
      updateWidget: () async => updateCount += 1,
    );

    await expectLater(
      refreshInstalledNextTrainWidgets(
        widgetIds: const [42, 43],
        readValue: (key) async => values[key],
        service: service,
        now: DateTime(2026, 7, 10, 9),
      ),
      throwsA(
        isA<StateError>()
            .having((error) => error.toString(), 'context', contains('42'))
            .having(
              (error) => error.toString(),
              'cause',
              contains('refresh failed'),
            ),
      ),
    );
    expect(loaded, ['station-a', 'station-b']);
    expect(updateCount, 1);
  });
}

Map<String, String> _twoWidgetValues() => {
  'widget_42_station_id': 'station-a',
  'widget_42_line_id': 'line-a',
  'widget_42_station_name': 'A역',
  'widget_42_line_name': 'A선',
  'widget_43_station_id': 'station-b',
  'widget_43_line_id': 'line-b',
  'widget_43_station_name': 'B역',
  'widget_43_line_name': 'B선',
};

const _selection = WidgetStationSelection(
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  stationName: '사당',
  lineName: '수도권 4호선',
);

final _availableData = NextTrainWidgetData(
  selection: _selection,
  status: NextTrainWidgetStatus.available,
  directions: [
    NextTrainDirection(
      name: '상록수 방면',
      departureAt: DateTime.utc(2026, 7, 10, 0, 12),
    ),
    NextTrainDirection(
      name: '사당 방면',
      departureAt: DateTime.utc(2026, 7, 10, 0, 18),
    ),
  ],
  statusLabel: '시간표 기준',
  updatedAt: DateTime(2026, 7, 10, 9),
);

Future<void> _seedWidgetCatalog(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO operators (id, name_ko, name_en)
    VALUES ('seoul-metro', '서울교통공사', 'Seoul Metro')
  ''');
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES ('seoul-4', 'seoul-metro', '수도권 4호선', 'Line 4', '#00A5DE')
  ''');
  await database.customStatement('''
    INSERT INTO stations (
      id, name_ko, name_en, name_sub, normalized_name, region,
      data_quality_level, data_source_type
    ) VALUES ('station-sadang', '사당', 'Sadang', '', '사당', '수도권',
      'LEVEL_2', 'OFFICIAL_FILE')
  ''');
  await database.customStatement('''
    INSERT INTO station_lines (
      station_id, line_id, station_code, line_sequence, platform_info
    ) VALUES ('station-sadang', 'seoul-4', '433', 28, '당고개 / 오이도')
  ''');
}

class _AvailableTimetableRepository extends _NoopTimetableRepository {
  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) async => StationTimetable(
    stationId: stationId,
    lineId: lineId,
    dayType: StationTimetableDayType.weekday,
    directions: [
      StationTimetableDirection(
        name: '상록수 방면',
        departures: [
          StationTimetableDeparture(
            directionName: '상록수 방면',
            seconds: 1,
            departureAt: asOf.add(const Duration(minutes: 1)),
          ),
        ],
      ),
      StationTimetableDirection(
        name: '사당 방면',
        departures: [
          StationTimetableDeparture(
            directionName: '사당 방면',
            seconds: 2,
            departureAt: asOf.add(const Duration(minutes: 2)),
          ),
        ],
      ),
    ],
  );
}

class _NoopTimetableRepository implements StationTimetableRepository {
  @override
  Future<StationTimetable> loadNextStationTimetable({
    required String stationId,
    required String lineId,
    required DateTime asOf,
    int horizonDays = 1,
  }) => throw UnimplementedError();

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) => throw UnimplementedError();

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) => throw UnimplementedError();
}
