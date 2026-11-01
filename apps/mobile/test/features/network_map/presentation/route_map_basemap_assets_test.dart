import 'dart:async';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_index.dart';
import '../../../support/basemap_waits.dart';

/// 첫 [loadString]이 비동기 함수의 첫 await에 닿기도 전에 던지는 묶음.
class _ThrowsBeforeFirstAwaitBundle extends FakeBasemapBundle {
  int loadStringCalls = 0;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (loadStringCalls++ == 0) {
      throw StateError('색인 읽기 시작 실패');
    }
    return super.loadString(key, cache: cache);
  }
}

/// 첫 [load]가 호출 자리에서 바로 던지는 묶음.
class _ThrowsOnFirstLoadBundle extends FakeBasemapBundle {
  @override
  Future<ByteData> load(String key) {
    if (requests.isEmpty) {
      requests.add(key);
      throw StateError('그림 읽기 시작 실패');
    }
    return super.load(key);
  }
}

/// [hasPendingReads]가 [script]의 값을 차례로 돌려주고, 다 쓰면 마지막 값을 계속 돌려주는
/// 자산. 조용한 상태의 판정만 따로 확인하려고 쓴다.
class _ScriptedReadsAssets extends RouteMapBasemapAssets {
  _ScriptedReadsAssets(this._script)
    : super(variant: RouteMapBasemapVariant.text);

  final List<bool> _script;
  int reads = 0;

  @override
  bool get hasPendingReads {
    final value = _script[reads < _script.length ? reads : _script.length - 1];
    reads++;
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const variant = RouteMapBasemapVariant.text;
  final daejeon = bundledBasemapIndex.variant(variant).baseAssetFor('daejeon');

  late RouteMapBasemapAssets assets;
  late List<FlutterErrorDetails> errors;
  late FlutterExceptionHandler? previousOnError;

  setUp(() {
    assets = RouteMapBasemapAssets(variant: variant);
    errors = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
  });

  tearDown(() {
    FlutterError.onError = previousOnError;
    assets.resetForTest();
    stopServingBasemapAssets();
  });

  Iterable<String> requestsFor(List<String> requests, String key) =>
      requests.where((request) => request == key);

  test('같은 그림을 함께 디코드하면 한 번 읽고 같은 그림을 준다', () async {
    final requests = serveBasemapAssets();

    final decoded = await Future.wait([
      assets.decode(daejeon),
      assets.decode(daejeon),
    ]);

    expect(decoded.first, isNotNull);
    expect(decoded.last, same(decoded.first));
    expect(assets.picture(daejeon), same(decoded.first));
    expect(requestsFor(requests, daejeon), hasLength(1));
  });

  test('끝난 그림을 다시 디코드하면 다시 읽지 않고 같은 그림을 준다', () async {
    final bundle = FakeBasemapBundle();
    final assets = RouteMapBasemapAssets(variant: variant, bundle: bundle);
    addTearDown(assets.resetForTest);

    final first = await assets.decode(daejeon);
    final second = await assets.decode(daejeon);

    expect(first, isNotNull);
    expect(second, same(first));
    expect(assets.picture(daejeon), same(first));
    expect(requestsFor(bundle.requests, daejeon), hasLength(1));
  });

  test('그림 읽기가 호출 자리에서 던져도 보고하고 디코드를 남기지 않아 다음 디코드가 다시 읽는다', () async {
    final bundle = _ThrowsOnFirstLoadBundle();
    final assets = RouteMapBasemapAssets(variant: variant, bundle: bundle);
    addTearDown(assets.resetForTest);

    expect(await assets.decode(daejeon), isNull);
    expect(assets.picture(daejeon), isNull);
    expect(errors, hasLength(1));
    expect(errors.single.context.toString(), contains(daejeon));

    final retried = await assets.decode(daejeon);

    expect(retried, isNotNull);
    expect(assets.picture(daejeon), same(retried));
    expect(requestsFor(bundle.requests, daejeon), hasLength(2));
    expect(errors, hasLength(1));
  });

  test('디코드에 실패하면 기다리는 곳이 둘이어도 한 번 보고하고, 다음 디코드가 다시 읽는다', () async {
    serveBasemapAssets({daejeon: () async => null});

    final failed = await Future.wait([
      assets.decode(daejeon),
      assets.decode(daejeon),
    ]);

    expect(failed, [null, null]);
    expect(assets.picture(daejeon), isNull);
    expect(errors, hasLength(1));
    expect(errors.single.context.toString(), contains(daejeon));

    final requests = serveBasemapAssets();
    final retried = await assets.decode(daejeon);

    expect(retried, isNotNull);
    expect(assets.picture(daejeon), same(retried));
    expect(requestsFor(requests, daejeon), hasLength(1));
    expect(errors, hasLength(1));
  });

  test('색인을 읽지 못하면 한 번 보고하고, 다음 읽기가 다시 읽는다', () async {
    serveBasemapAssets({kRouteMapLineOverlayIndexAssetPath: () async => null});

    final failed = await Future.wait([assets.loadFiles(), assets.loadFiles()]);

    expect(failed, [null, null]);
    expect(assets.files, isNull);
    expect(errors, hasLength(1));
    expect(
      errors.single.context.toString(),
      contains(kRouteMapLineOverlayIndexAssetPath),
    );

    serveBasemapAssets();
    final files = await assets.loadFiles();

    expect(files, isNotNull);
    expect(assets.files, same(files));
    expect(files!.baseAssetFor('daejeon'), daejeon);
    expect(errors, hasLength(1));
  });

  test('색인 읽기가 첫 await 전에 던져도 보고하고 로드를 남기지 않아 다음 읽기가 다시 읽는다', () async {
    final bundle = _ThrowsBeforeFirstAwaitBundle();
    final assets = RouteMapBasemapAssets(variant: variant, bundle: bundle);
    addTearDown(assets.resetForTest);

    expect(await assets.loadFiles(), isNull);
    expect(assets.files, isNull);
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<StateError>());

    final files = await assets.loadFiles();

    expect(files, isNotNull);
    expect(assets.files, same(files));
    expect(bundle.loadStringCalls, 2);
    expect(errors, hasLength(1));
  });

  test('읽은 색인은 다시 읽지 않는다', () async {
    final requests = serveBasemapAssets();

    final first = await assets.loadFiles();
    final second = await assets.loadFiles();

    expect(second, same(first));
    expect(
      requestsFor(requests, kRouteMapLineOverlayIndexAssetPath),
      hasLength(1),
    );
  });

  group('끝나지 않은 읽기가 있는지', () {
    test('디코드하는 동안만 true이고, 성공하면 false다', () async {
      final bytes = Completer<ByteData?>();
      serveBasemapAssets({daejeon: () => bytes.future});
      expect(assets.hasPendingReads, isFalse);

      final decoded = assets.decode(daejeon);

      expect(assets.hasPendingReads, isTrue);

      bytes.complete(bundledAsset(daejeon));
      expect(await decoded, isNotNull);

      expect(assets.hasPendingReads, isFalse);
    });

    test('디코드에 실패하면 false이고, 기억을 남기지 않아 다시 디코드하면 다시 true다', () async {
      final bytes = Completer<ByteData?>();
      serveBasemapAssets({daejeon: () => bytes.future});
      final failed = assets.decode(daejeon);
      bytes.complete(null);
      expect(await failed, isNull);

      expect(assets.hasPendingReads, isFalse);

      serveBasemapAssets({daejeon: () => Completer<ByteData?>().future});
      unawaited(assets.decode(daejeon));

      expect(assets.hasPendingReads, isTrue);
    });

    test('색인을 읽는 동안만 true이고, 성공하면 false다', () async {
      final index = Completer<ByteData?>();
      serveBasemapAssets({
        kRouteMapLineOverlayIndexAssetPath: () => index.future,
      });
      expect(assets.hasPendingReads, isFalse);

      final files = assets.loadFiles();

      expect(assets.hasPendingReads, isTrue);

      index.complete(bundledAsset(kRouteMapLineOverlayIndexAssetPath));
      expect(await files, isNotNull);

      expect(assets.hasPendingReads, isFalse);
    });

    test('색인 읽기에 실패하면 false이고, 기억을 남기지 않아 다시 읽으면 다시 true다', () async {
      final index = Completer<ByteData?>();
      serveBasemapAssets({
        kRouteMapLineOverlayIndexAssetPath: () => index.future,
      });
      final failed = assets.loadFiles();
      index.complete(null);
      expect(await failed, isNull);

      expect(assets.hasPendingReads, isFalse);

      serveBasemapAssets({
        kRouteMapLineOverlayIndexAssetPath: () => Completer<ByteData?>().future,
      });
      unawaited(assets.loadFiles());

      expect(assets.hasPendingReads, isTrue);
    });

    test('읽는 중에 초기화하면 false이고, 늦게 끝나도 false다', () async {
      final bytes = Completer<ByteData?>();
      final index = Completer<ByteData?>();
      serveBasemapAssets({
        daejeon: () => bytes.future,
        kRouteMapLineOverlayIndexAssetPath: () => index.future,
      });
      final stale = [assets.decode(daejeon), assets.loadFiles()];
      expect(assets.hasPendingReads, isTrue);

      assets.resetForTest();

      expect(assets.hasPendingReads, isFalse);

      bytes.complete(bundledAsset(daejeon));
      index.complete(bundledAsset(kRouteMapLineOverlayIndexAssetPath));
      expect(await Future.wait(stale), [null, null]);

      expect(assets.hasPendingReads, isFalse);
    });
  });

  group('조용해질 때까지 기다리기', () {
    testWidgets('막힌 디코드가 끝나기 전에는 돌아오지 않는다', (tester) async {
      final bytes = Completer<ByteData?>();
      serveBasemapAssets({daejeon: () => bytes.future});
      unawaited(assets.decode(daejeon));
      await tester.runAsync(
        () async => Timer(
          const Duration(milliseconds: 100),
          () => bytes.complete(bundledAsset(daejeon)),
        ),
      );

      await pumpUntilQuiet(tester, assets);

      expect(assets.picture(daejeon), isNotNull);
    });

    testWidgets('읽는 일이 없는 상태가 이어지면 돌아온다', (tester) async {
      final scripted = _ScriptedReadsAssets([true, true, false]);

      await pumpUntilQuiet(tester, scripted);

      expect(scripted.hasPendingReads, isFalse);
    });

    testWidgets('조용해진 뒤 마지막 바퀴에 읽기가 다시 시작하면 그 바퀴를 밝혀 실패한다', (tester) async {
      final scripted = _ScriptedReadsAssets([true, false, false, false, true]);

      await expectLater(
        () => pumpUntilQuiet(tester, scripted),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('3번째 바퀴'),
          ),
        ),
      );
    });

    testWidgets('조용해진 첫 바퀴에 읽기가 다시 시작해도 그 바퀴를 밝혀 실패한다', (tester) async {
      final scripted = _ScriptedReadsAssets([false, true]);

      await expectLater(
        () => pumpUntilQuiet(tester, scripted),
        throwsA(
          isA<TestFailure>().having(
            (failure) => failure.message,
            'message',
            contains('1번째 바퀴'),
          ),
        ),
      );
    });
  });

  group('초기화 전에 시작한 로드는 늦게 끝나도 아무것도 남기지 않는다', () {
    test('디코드한 그림', () async {
      final bytes = Completer<ByteData?>();
      serveBasemapAssets({daejeon: () => bytes.future});

      final stale = assets.decode(daejeon);
      assets.resetForTest();
      bytes.complete(bundledAsset(daejeon));

      expect(await stale, isNull);
      expect(assets.picture(daejeon), isNull);
    });

    test('읽지 못한 색인의 보고', () async {
      final index = Completer<ByteData?>();
      serveBasemapAssets({
        kRouteMapLineOverlayIndexAssetPath: () => index.future,
      });

      final stale = assets.loadFiles();
      assets.resetForTest();
      index.complete(null);

      expect(await stale, isNull);
      expect(assets.files, isNull);
      expect(errors, isEmpty);
    });

    test('읽은 색인', () async {
      final index = Completer<ByteData?>();
      serveBasemapAssets({
        kRouteMapLineOverlayIndexAssetPath: () => index.future,
      });

      final stale = assets.loadFiles();
      assets.resetForTest();
      index.complete(bundledAsset(kRouteMapLineOverlayIndexAssetPath));

      expect(await stale, isNull);
      expect(assets.files, isNull);
    });
  });
}
