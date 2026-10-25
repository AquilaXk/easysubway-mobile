import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_index.dart';

const _uiSinseolLineId = 'line-30886152e4f8';
const _seoulLine2Id = 'seoul-2';

const _camera = MapCameraState(
  sourceBounds: Rect.fromLTWH(0, 0, 1000, 1000),
  viewportSize: Size(400, 800),
  center: Offset(500, 500),
  scale: 2.0,
  minScale: 0.5,
  maxScale: 10.0,
  revision: 1,
);

RouteMapBasemapVariantFiles _files(RouteMapBasemapAssets assets) =>
    bundledBasemapIndex.variant(assets.variant);

String _overlay(RouteMapBasemapAssets assets, String lineId) =>
    _files(assets).overlayAssetFor(regionId: 'seoul', lineId: lineId);

/// 바탕 뷰. 권역을 바꿔도 부모가 key를 달아 주지 않는다.
Widget _view(
  RouteMapBasemapAssets assets, {
  required String region,
  String? lineId,
  Key? key,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RouteMapBasemapView(
    key: key,
    region: region,
    camera: _camera,
    highlightedLineId: lineId,
    assets: assets,
  ),
);

/// 바탕 뷰가 지금 그리는 그림. 노선을 골랐으면 흐린 바탕, 노선 레이어 순이다.
List<ui.Picture?> _paintedPictures(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(RouteMapBasemapView),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => (paint.painter! as RouteMapBasemapPainter).picture)
    .toList();

/// 자산을 읽고 벡터로 그린 프레임에서 멈춘다. 시계를 돌리지 않아 바탕 타일은 굽지 않는다.
Future<void> _settleLoads(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

/// [body]가 도는 동안 보고된 Flutter 오류.
Future<List<FlutterErrorDetails>> _errorsDuring(
  Future<void> Function() body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previousOnError;
  }
  return errors;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('렌더러 변형', () {
    for (final variant in RouteMapBasemapVariant.values) {
      testWidgets('${variant.indexKey} 변형이면 바탕과 노선 레이어를 모두 그 변형 파일로 그린다', (
        tester,
      ) async {
        final assets = RouteMapBasemapAssets(variant: variant);
        addTearDown(assets.resetForTest);
        await tester.pumpWidget(
          _view(assets, region: '수도권', lineId: _uiSinseolLineId),
        );
        await _settleLoads(tester);

        final base = assets.picture(_files(assets).baseAssetFor('seoul'));
        final overlay = assets.picture(_overlay(assets, _uiSinseolLineId));
        expect(base, isNotNull);
        expect(overlay, isNotNull);
        expect(_paintedPictures(tester), [base!.picture, overlay!.picture]);
      });
    }
  });

  group('RouteMapBasemapPainter', () {
    test('sourceToViewport는 카메라와 sourceOrigin을 반영해 1:1 변환한다', () {
      const origin = Offset(100, 50);
      final painter = RouteMapBasemapPainter(
        picture: null,
        camera: _camera,
        sourceOrigin: origin,
      );

      final point = painter.sourceToViewport(const Offset(600, 550));
      // vc = (200, 400), viewBox = (600, 550), origin = (100, 50), center = (500, 500), scale = 2.0
      // diff = (600 - 100 - 500, 550 - 50 - 500) = (0, 0)
      // vc + (0, 0) * 2.0 = (200, 400)
      expect(point, const Offset(200, 400));
    });

    test('shouldRepaint는 카메라, picture, sourceOrigin, attribution 변화를 감지한다', () {
      final painter1 = RouteMapBasemapPainter(
        picture: null,
        camera: _camera,
        sourceOrigin: Offset.zero,
        attributionText: '출처 A',
      );
      final painter2 = RouteMapBasemapPainter(
        picture: null,
        camera: _camera,
        sourceOrigin: Offset.zero,
        attributionText: '출처 A',
      );
      expect(painter1.shouldRepaint(painter2), isFalse);

      final painterCameraChanged = RouteMapBasemapPainter(
        picture: null,
        camera: _camera.copyWith(scale: 3.0),
        sourceOrigin: Offset.zero,
        attributionText: '출처 A',
      );
      expect(painterCameraChanged.shouldRepaint(painter1), isTrue);

      final painterOriginChanged = RouteMapBasemapPainter(
        picture: null,
        camera: _camera,
        sourceOrigin: const Offset(10, 10),
        attributionText: '출처 A',
      );
      expect(painterOriginChanged.shouldRepaint(painter1), isTrue);

      final painterAttributionChanged = RouteMapBasemapPainter(
        picture: null,
        camera: _camera,
        sourceOrigin: Offset.zero,
        attributionText: '출처 B',
      );
      expect(painterAttributionChanged.shouldRepaint(painter1), isTrue);
    });
  });

  group('RouteMapBasemapView 위젯과 자산 수명주기', () {
    late RouteMapBasemapAssets assets;

    setUp(() {
      assets = RouteMapBasemapAssets(variant: RouteMapBasemapVariant.text);
    });

    tearDown(() {
      assets.resetForTest();
      stopServingBasemapAssets();
    });

    String base(String regionId) => _files(assets).baseAssetFor(regionId);

    testWidgets('매핑에 없는 권역은 바탕을 그리지 않고 뷰마다 한 번 보고한다', (tester) async {
      final errors = await _errorsDuring(() async {
        await tester.pumpWidget(_view(assets, region: '알 수 없음'));
        await _settleLoads(tester);
        await tester.pumpWidget(
          _view(assets, region: '알 수 없음', lineId: _seoulLine2Id),
        );
        await _settleLoads(tester);
      });

      expect(_paintedPictures(tester), [null]);
      expect(errors, hasLength(1));
      expect(errors.single.library, 'network_map');
      expect(errors.single.exception, isA<ArgumentError>());
      expect(errors.single.context.toString(), contains('알 수 없음'));
    });

    testWidgets('권역을 바꿔 새로 만든 뷰는 한 번 디코드한 바탕을 첫 프레임에 바로 그린다', (tester) async {
      await tester.pumpWidget(_view(assets, region: '대전'));
      await _settleLoads(tester);
      final daejeon = assets.picture(base('daejeon'));
      expect(daejeon, isNotNull);

      await tester.pumpWidget(_view(assets, region: '광주'));
      await _settleLoads(tester);
      await tester.pumpWidget(_view(assets, region: '대전'));

      expect(_paintedPictures(tester), [daejeon!.picture]);
    });

    testWidgets('같은 자리의 뷰가 권역을 바꾸면 이전 권역 바탕은 한 프레임도 남지 않는다', (tester) async {
      await tester.pumpWidget(_view(assets, region: '대전'));
      await _settleLoads(tester);
      final daejeon = assets.picture(base('daejeon'))!.picture;
      expect(_paintedPictures(tester), [daejeon]);

      await tester.pumpWidget(_view(assets, region: '광주'));

      expect(_paintedPictures(tester), isNot(contains(daejeon)));

      await _settleLoads(tester);

      expect(_paintedPictures(tester), [
        assets.picture(base('gwangju'))!.picture,
      ]);
    });

    testWidgets('같은 권역을 그리는 두 뷰는 한 번 디코드한 같은 그림을 그린다', (tester) async {
      final requests = serveBasemapAssets();
      await tester.pumpWidget(
        Stack(
          textDirection: TextDirection.ltr,
          children: [
            _view(assets, region: '대구', key: const ValueKey('첫째')),
            _view(assets, region: '대구', key: const ValueKey('둘째')),
          ],
        ),
      );
      await _settleLoads(tester);

      final daegu = assets.picture(base('daegu'));
      expect(daegu, isNotNull);
      expect(_paintedPictures(tester), [daegu!.picture, daegu.picture]);
      expect(requests.where((key) => key == base('daegu')), hasLength(1));
    });

    group('읽지 못한 자산은 그리지 않고 시도마다 한 번 보고한다', () {
      testWidgets('바탕 .vec를 읽지 못하면 한 번 보고하고, 다음에 만든 뷰가 다시 읽는다', (tester) async {
        final busan = base('busan');
        serveBasemapAssets({busan: () async => null});

        final errors = await _errorsDuring(() async {
          await tester.pumpWidget(_view(assets, region: '부산'));
          await _settleLoads(tester);
        });

        expect(_paintedPictures(tester), [null]);
        expect(errors, hasLength(1));
        expect(errors.single.library, 'network_map');
        expect(errors.single.context.toString(), contains(busan));

        serveBasemapAssets();
        final retryErrors = await _errorsDuring(() async {
          await tester.pumpWidget(
            _view(assets, region: '부산', key: const ValueKey('다시')),
          );
          await _settleLoads(tester);
        });

        expect(retryErrors, isEmpty);
        expect(_paintedPictures(tester), [assets.picture(busan)!.picture]);
      });

      testWidgets('바탕 색인을 읽지 못하면 노선을 골랐어도 한 번만 보고하고, 다음에 만든 뷰가 다시 읽는다', (
        tester,
      ) async {
        serveBasemapAssets({
          kRouteMapLineOverlayIndexAssetPath: () async => null,
        });

        final errors = await _errorsDuring(() async {
          await tester.pumpWidget(
            _view(assets, region: '부산', lineId: 'line-ab1a041f6266'),
          );
          await _settleLoads(tester);
        });

        expect(_paintedPictures(tester), [null]);
        expect(errors, hasLength(1));
        expect(
          errors.single.context.toString(),
          contains(kRouteMapLineOverlayIndexAssetPath),
        );

        serveBasemapAssets();
        final retryErrors = await _errorsDuring(() async {
          await tester.pumpWidget(_view(assets, region: '대구'));
          await _settleLoads(tester);
        });

        expect(retryErrors, isEmpty);
        expect(_paintedPictures(tester), [
          assets.picture(base('daegu'))!.picture,
        ]);
      });

      testWidgets('바탕 색인에 권역이 없음', (tester) async {
        final index =
            jsonDecode(
                  File(kRouteMapLineOverlayIndexAssetPath).readAsStringSync(),
                )
                as Map<String, dynamic>;
        for (final variant in (index['variants'] as Map).values) {
          ((variant as Map)['regions'] as Map).remove('busan');
        }
        serveBasemapAssets({
          kRouteMapLineOverlayIndexAssetPath: () async =>
              ByteData.sublistView(utf8.encode(jsonEncode(index))),
        });

        final errors = await _errorsDuring(() async {
          await tester.pumpWidget(_view(assets, region: '부산'));
          await _settleLoads(tester);
        });

        expect(_paintedPictures(tester), [null]);
        expect(errors, hasLength(1));
        expect(
          errors.single.exception,
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('regions'),
          ),
        );
      });

      testWidgets('색인을 기다리는 동안 노선을 바꿔도 색인을 읽은 뒤 한 번만 맞춘다', (tester) async {
        final index = Completer<ByteData?>();
        serveBasemapAssets({
          kRouteMapLineOverlayIndexAssetPath: () => index.future,
        });

        final errors = await _errorsDuring(() async {
          await tester.pumpWidget(
            _view(assets, region: '수도권', lineId: _uiSinseolLineId),
          );
          await tester.pumpWidget(
            _view(assets, region: '수도권', lineId: 'line-unknown'),
          );
          index.complete(bundledAsset(kRouteMapLineOverlayIndexAssetPath));
          await _settleLoads(tester);
        });

        expect(errors, hasLength(1));
        expect(errors.single.exception, isA<RouteMapLineOverlayMissing>());
        expect(_paintedPictures(tester), [
          assets.picture(base('seoul'))!.picture,
        ]);
      });

      testWidgets('노선을 A→B→A로 바꾸는 사이 끝난 A 레이어 실패도 보고하고, 다시 고르면 다시 읽는다', (
        tester,
      ) async {
        final lineA = _overlay(assets, _uiSinseolLineId);
        final firstA = Completer<ByteData?>();
        var requestsA = 0;
        serveBasemapAssets({
          lineA: () => requestsA++ == 0
              ? firstA.future
              : Future.value(bundledAsset(lineA)),
        });

        final errors = await _errorsDuring(() async {
          await tester.pumpWidget(
            _view(assets, region: '수도권', lineId: _uiSinseolLineId),
          );
          await _settleLoads(tester);
          await tester.pumpWidget(
            _view(assets, region: '수도권', lineId: _seoulLine2Id),
          );
          await _settleLoads(tester);
          firstA.complete(null);
          await _settleLoads(tester);
        });

        final seoul = assets.picture(base('seoul'))!.picture;
        expect(errors, hasLength(1));
        expect(errors.single.context.toString(), contains(lineA));
        expect(_paintedPictures(tester), [
          seoul,
          assets.picture(_overlay(assets, _seoulLine2Id))!.picture,
        ]);

        final retryErrors = await _errorsDuring(() async {
          await tester.pumpWidget(
            _view(assets, region: '수도권', lineId: _uiSinseolLineId),
          );
          await _settleLoads(tester);
        });

        expect(retryErrors, isEmpty);
        expect(_paintedPictures(tester), [
          seoul,
          assets.picture(lineA)!.picture,
        ]);
      });
    });
  });
}
