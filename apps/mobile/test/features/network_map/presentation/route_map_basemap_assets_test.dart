import 'dart:async';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_index.dart';

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
