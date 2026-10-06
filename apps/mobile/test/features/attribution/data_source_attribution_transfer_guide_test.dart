import 'package:easysubway_mobile/core/crashlytics/crashlytics_gateway.dart';
import 'package:easysubway_mobile/features/attribution/presentation/data_source_attribution_screen.dart';
import 'package:easysubway_mobile/features/journey/domain/transfer_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _manifest = <String, Object?>{'maps': <Object?>[]};
const _inventory = <String, Object?>{'sources': <Object?>[]};

class _RecordingCrashlytics implements CrashlyticsGateway {
  final errors = <Object>[];
  final fatalFlags = <bool>[];

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
  }

  @override
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {}

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> setCustomKey(String key, String value) async {}
}

class _Guides implements TransferGuideRepository {
  _Guides(this.sources, {this.failure});

  final List<TransferGuideSource> sources;
  final Object? failure;

  @override
  Future<List<String>> loadSteps(TransferGuideKey key) async => const [];

  @override
  Future<List<TransferGuideSource>> loadSources() async {
    if (failure case final error?) throw error;
    return sources;
  }
}

Future<void> _pump(WidgetTester tester, TransferGuideRepository? guides) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DataSourceAttributionScreen(
        initialManifest: _manifest,
        initialInventory: _inventory,
        transferGuideRepository: guides,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('환승 이동 안내의 출처 표기를 다른 자료와 같은 목록에 보여 준다', (tester) async {
    await _pump(
      tester,
      _Guides(const [
        TransferGuideSource(
          sourceSnapshotId: 'snap-1',
          datasetLabel: '국토교통부 철도역 환승 이동경로',
          attribution: '국토교통부 철도역 환승 이동경로(공공데이터포털 15130556)',
        ),
      ]),
    );

    expect(find.text('국토교통부 철도역 환승 이동경로'), findsOneWidget);
    expect(find.text('출처 표기'), findsOneWidget);
    expect(find.text('국토교통부 철도역 환승 이동경로(공공데이터포털 15130556)'), findsOneWidget);
  });

  testWidgets('출처 행이 없으면 아무 카드도 더하지 않는다', (tester) async {
    await _pump(tester, _Guides(const []));

    expect(find.text('출처 표기'), findsNothing);
    expect(find.textContaining('정보 없음'), findsNothing);
  });

  testWidgets('출처 조회가 실패해도 화면은 열리고 카드는 없다', (tester) async {
    final crashlytics = _RecordingCrashlytics();
    replaceCrashlyticsGatewayForTest(crashlytics);
    addTearDown(resetCrashlyticsGateway);
    await _pump(tester, _Guides(const [], failure: StateError('x')));

    expect(crashlytics.errors, hasLength(1));
    expect(crashlytics.fatalFlags, <bool>[false]);

    expect(
      find.byKey(const Key('dataSourceAttributionScreen')),
      findsOneWidget,
    );
    expect(find.text('출처 표기'), findsNothing);
  });

  testWidgets('저장소가 없으면 현재 화면 그대로다', (tester) async {
    await _pump(tester, null);

    expect(
      find.byKey(const Key('dataSourceAttributionScreen')),
      findsOneWidget,
    );
    expect(find.text('출처 표기'), findsNothing);
  });
}
