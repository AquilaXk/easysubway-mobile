import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'clearAllNextTrainWidgetData는 Android 위젯별 모든 키를 비우고 갱신 예약을 취소한다',
    () async {
      final clearedKeys = <String>[];
      var cancelCalls = 0;
      var updateCalls = 0;
      final bindings = NextTrainWidgetAndroidBindings(
        isAndroid: () => true,
        initialize: (_) async {},
        register: () async {},
        cancel: () async {
          cancelCalls += 1;
        },
        installedWidgetIds: () async => const [11, 22],
        clicks: () => const Stream.empty(),
      );

      await clearAllNextTrainWidgetData(
        bindings: bindings,
        clearValue: (key) async {
          clearedKeys.add(key);
        },
        updateWidget: () async {
          updateCalls += 1;
        },
      );

      const expectedSuffixes = [
        'station_id',
        'line_id',
        'station_name',
        'line_name',
        'direction_1',
        'departure_1',
        'direction_2',
        'departure_2',
        'status',
        'status_label',
        'updated_at',
      ];
      expect(clearedKeys, [
        for (final id in const [11, 22])
          for (final suffix in expectedSuffixes) 'widget_${id}_$suffix',
      ]);
      expect(cancelCalls, 1);
      expect(updateCalls, 1);
    },
  );

  test('clearAllNextTrainWidgetData는 비-Android 환경에서 아무 작업도 하지 않는다', () async {
    var installedQueried = false;
    var cancelCalls = 0;
    var updateCalls = 0;
    final clearedKeys = <String>[];
    final bindings = NextTrainWidgetAndroidBindings(
      isAndroid: () => false,
      initialize: (_) async {},
      register: () async {},
      cancel: () async {
        cancelCalls += 1;
      },
      installedWidgetIds: () async {
        installedQueried = true;
        return const [11];
      },
      clicks: () => const Stream.empty(),
    );

    await clearAllNextTrainWidgetData(
      bindings: bindings,
      clearValue: (key) async {
        clearedKeys.add(key);
      },
      updateWidget: () async {
        updateCalls += 1;
      },
    );

    expect(installedQueried, isFalse);
    expect(clearedKeys, isEmpty);
    expect(cancelCalls, 0);
    expect(updateCalls, 0);
  });

  test(
    'clearAllNextTrainWidgetData는 기본 clearValue로 HomeWidget 채널에 null 저장을 위임한다',
    () async {
      const channel = MethodChannel('home_widget');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final savedCalls = <({String? id, Object? data})>[];
      final updatedProviders = <String?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'saveWidgetData') {
          final args = call.arguments as Map<Object?, Object?>;
          savedCalls.add((id: args['id'] as String?, data: args['data']));
          return true;
        }
        if (call.method == 'updateWidget') {
          final args = call.arguments as Map<Object?, Object?>;
          updatedProviders.add(args['qualifiedAndroidName'] as String?);
          return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      var cancelCalls = 0;
      final bindings = NextTrainWidgetAndroidBindings(
        isAndroid: () => true,
        initialize: (_) async {},
        register: () async {},
        cancel: () async {
          cancelCalls += 1;
        },
        installedWidgetIds: () async => const [7],
        clicks: () => const Stream.empty(),
      );

      await clearAllNextTrainWidgetData(bindings: bindings);

      const expectedSuffixes = [
        'station_id',
        'line_id',
        'station_name',
        'line_name',
        'direction_1',
        'departure_1',
        'direction_2',
        'departure_2',
        'status',
        'status_label',
        'updated_at',
      ];
      expect(savedCalls.map((entry) => entry.id).toList(), [
        for (final suffix in expectedSuffixes) 'widget_7_$suffix',
      ]);
      expect(savedCalls.every((entry) => entry.data == null), isTrue);
      expect(cancelCalls, 1);
      expect(updatedProviders, [nextTrainWidgetProviderName]);
    },
  );
}
