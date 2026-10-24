import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_index.dart';

const _uiSinseolLineId = 'line-30886152e4f8';

/// 엔진 렌더러가 고른 변형의 [regionId] 권역 바탕.
String _engineBase(String regionId) => bundledBasemapIndex
    .variant(routeMapBasemapVariantOfEngine())
    .baseAssetFor(regionId);

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

/// [assets]에 든 키는 그 바이트로, 나머지 자산 키는 번들 파일 그대로 답한다. 값이 null이면
/// 읽기 실패다.
void _serveAssets(Map<String, ByteData?> assets) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = Uri.decodeFull(utf8.decode(message!.buffer.asUint8List()));
        if (assets.containsKey(key)) return assets[key];
        return ByteData.sublistView(File(key).readAsBytesSync());
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const camera = MapCameraState(
    sourceBounds: Rect.fromLTWH(0, 0, 1000, 1000),
    viewportSize: Size(400, 800),
    center: Offset(500, 500),
    scale: 2.0,
    minScale: 0.5,
    maxScale: 10.0,
    revision: 1,
  );

  test('엔진이 Impeller로 그리면 윤곽선 변형, Skia로 그리면 텍스트 변형을 고른다', () {
    expect(
      routeMapBasemapVariantOfEngine(),
      ui.ImageFilter.isShaderFilterSupported
          ? RouteMapBasemapVariant.outlined
          : RouteMapBasemapVariant.text,
    );
  });

  group('렌더러 변형', () {
    tearDown(RouteMapBasemapViewState.clearPictureCacheForTest);

    Widget seoul(RouteMapBasemapVariant? variant) => Directionality(
      textDirection: TextDirection.ltr,
      child: RouteMapBasemapView(
        region: '수도권',
        camera: camera,
        highlightedLineId: _uiSinseolLineId,
        variant: variant,
      ),
    );

    for (final variant in RouteMapBasemapVariant.values) {
      testWidgets('${variant.name} 변형은 바탕과 노선 레이어를 모두 그 변형 파일로 그린다', (
        tester,
      ) async {
        await tester.pumpWidget(seoul(variant));
        await _settleLoads(tester);

        final state = tester.state<RouteMapBasemapViewState>(
          find.byType(RouteMapBasemapView),
        );
        final files = bundledBasemapIndex.variant(variant);
        final base = state.debugPictureCache[files.baseAssetFor('seoul')];
        final overlay =
            state.debugPictureCache[files.overlayAssetFor(
              regionId: 'seoul',
              lineId: _uiSinseolLineId,
            )];
        expect(_paintedPictures(tester), [base?.picture, overlay?.picture]);
        expect(base, isNotNull);
        expect(overlay, isNotNull);
        expect(state.debugPictureCache, hasLength(2));
      });
    }

    testWidgets('변형을 바꾸면 이전 변형 바탕 위에 새 변형 레이어를 겹치지 않고 새 변형으로 다시 그린다', (
      tester,
    ) async {
      await tester.pumpWidget(seoul(RouteMapBasemapVariant.outlined));
      await _settleLoads(tester);

      await tester.pumpWidget(seoul(RouteMapBasemapVariant.text));
      expect(_paintedPictures(tester), [null]);

      await _settleLoads(tester);
      final state = tester.state<RouteMapBasemapViewState>(
        find.byType(RouteMapBasemapView),
      );
      final text = bundledBasemapIndex.variant(RouteMapBasemapVariant.text);
      expect(_paintedPictures(tester), [
        state.debugPictureCache[text.baseAssetFor('seoul')]!.picture,
        state
            .debugPictureCache[text.overlayAssetFor(
              regionId: 'seoul',
              lineId: _uiSinseolLineId,
            )]!
            .picture,
      ]);
    });
  });

  group('RouteMapBasemapPainter', () {
    test('sourceToViewport는 카메라와 sourceOrigin을 반영해 1:1 변환한다', () {
      const origin = Offset(100, 50);
      final painter = RouteMapBasemapPainter(
        picture: null,
        camera: camera,
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
        camera: camera,
        sourceOrigin: Offset.zero,
        attributionText: '출처 A',
      );
      final painter2 = RouteMapBasemapPainter(
        picture: null,
        camera: camera,
        sourceOrigin: Offset.zero,
        attributionText: '출처 A',
      );
      expect(painter1.shouldRepaint(painter2), isFalse);

      final painterCameraChanged = RouteMapBasemapPainter(
        picture: null,
        camera: camera.copyWith(scale: 3.0),
        sourceOrigin: Offset.zero,
        attributionText: '출처 A',
      );
      expect(painterCameraChanged.shouldRepaint(painter1), isTrue);

      final painterOriginChanged = RouteMapBasemapPainter(
        picture: null,
        camera: camera,
        sourceOrigin: const Offset(10, 10),
        attributionText: '출처 A',
      );
      expect(painterOriginChanged.shouldRepaint(painter1), isTrue);

      final painterAttributionChanged = RouteMapBasemapPainter(
        picture: null,
        camera: camera,
        sourceOrigin: Offset.zero,
        attributionText: '출처 B',
      );
      expect(painterAttributionChanged.shouldRepaint(painter1), isTrue);
    });
  });

  group('RouteMapBasemapView 위젯 및 캐시 수명주기', () {
    tearDown(RouteMapBasemapViewState.clearPictureCacheForTest);

    testWidgets('매핑에 없는 권역은 바탕을 그리지 않고 안전하게 유지한다', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapBasemapView(region: '알 수 없음', camera: camera),
        ),
      );
      await tester.pumpAndSettle();

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as RouteMapBasemapPainter;
      expect(painter.picture, isNull);
    });

    testWidgets('권역 로드 후 _pictureCache에 캐시되고 권역 전환 후 복귀 시 재사용된다', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapBasemapView(region: '대전', camera: camera),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<RouteMapBasemapViewState>(
        find.byType(RouteMapBasemapView),
      );
      final daejeonAsset = _engineBase('daejeon');
      expect(state.debugPictureCache.containsKey(daejeonAsset), isTrue);
      final daejeonPicture = state.debugPictureCache[daejeonAsset];
      expect(daejeonPicture, isNotNull);

      // 광주로 전환
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapBasemapView(region: '광주', camera: camera),
        ),
      );
      await tester.pumpAndSettle();

      final gwangjuAsset = _engineBase('gwangju');
      expect(state.debugPictureCache.containsKey(gwangjuAsset), isTrue);
      expect(state.debugPictureCache.containsKey(daejeonAsset), isTrue);

      // 대전으로 즉시 복귀: 캐시된 Picture를 그대로 재사용하여 pendingLoad가 생기지 않는다.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapBasemapView(region: '대전', camera: camera),
        ),
      );
      expect(state.debugPendingLoads.containsKey(daejeonAsset), isFalse);
      expect(
        identical(state.debugPictureCache[daejeonAsset], daejeonPicture),
        isTrue,
      );

      final customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final painter = customPaint.painter as RouteMapBasemapPainter;
      expect(identical(painter.picture, daejeonPicture!.picture), isTrue);
    });

    testWidgets('유효한 권역 로드 후 매핑에 없는 권역으로 변경되면 _picture가 null로 초기화된다', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapBasemapView(region: '대전', camera: camera),
        ),
      );
      await tester.pumpAndSettle();

      var customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      var painter = customPaint.painter as RouteMapBasemapPainter;
      expect(painter.picture, isNotNull);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RouteMapBasemapView(region: '미지의권역', camera: camera),
        ),
      );
      await tester.pumpAndSettle();

      customPaint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      painter = customPaint.painter as RouteMapBasemapPainter;
      expect(painter.picture, isNull);
    });

    testWidgets('동일 권역을 그리는 두 위젯이 동시 마운트될 때 pendingLoad를 공유하여 로드한다', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              RouteMapBasemapView(region: '대구', camera: camera),
              RouteMapBasemapView(region: '대구', camera: camera),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .toList();
      expect(paints.length, 2);
      final p1 = paints[0].painter as RouteMapBasemapPainter;
      final p2 = paints[1].painter as RouteMapBasemapPainter;
      expect(p1.picture, isNotNull);
      expect(p2.picture, isNotNull);
      expect(identical(p1.picture, p2.picture), isTrue);
    });

    group('바탕을 읽지 못하면 그리지 않고 FlutterError를 보고한다', () {
      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler('flutter/assets', null);
      });

      Future<List<FlutterErrorDetails>> pumpBusan(WidgetTester tester) async {
        final errors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await tester.pumpWidget(
            const Directionality(
              textDirection: TextDirection.ltr,
              child: RouteMapBasemapView(region: '부산', camera: camera),
            ),
          );
          await tester.pumpAndSettle();
        } finally {
          FlutterError.onError = previousOnError;
        }
        return errors;
      }

      testWidgets('바탕 .vec를 읽지 못하면 pendingLoads를 정리한다', (tester) async {
        final busanAsset = _engineBase('busan');
        _serveAssets({busanAsset: null});

        final errors = await pumpBusan(tester);

        final state = tester.state<RouteMapBasemapViewState>(
          find.byType(RouteMapBasemapView),
        );
        expect(state.debugPendingLoads.containsKey(busanAsset), isFalse);
        expect(state.debugPictureCache.containsKey(busanAsset), isFalse);
        expect(_paintedPictures(tester), [null]);
        expect(errors, hasLength(1));
        expect(errors.single.library, 'network_map');
        expect(errors.single.context.toString(), contains(busanAsset));
      });

      testWidgets('바탕 색인을 읽지 못함', (tester) async {
        _serveAssets({kRouteMapLineOverlayIndexAssetPath: null});

        final errors = await pumpBusan(tester);

        expect(_paintedPictures(tester), [null]);
        expect(errors, hasLength(1));
        expect(errors.single.context.toString(), contains('busan 바탕 색인'));
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
        _serveAssets({
          kRouteMapLineOverlayIndexAssetPath: ByteData.sublistView(
            utf8.encode(jsonEncode(index)),
          ),
        });

        final errors = await pumpBusan(tester);

        expect(_paintedPictures(tester), [null]);
        expect(errors, hasLength(1));
        expect(
          errors.single.exception,
          isA<RouteMapBasemapRegionMissing>().having(
            (error) => error.regionId,
            'regionId',
            'busan',
          ),
        );
      });
    });
  });
}
