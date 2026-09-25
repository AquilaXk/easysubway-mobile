import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('routeMapBasemapAssetForRegion', () {
    test('5개 전 권역을 올바른 .vec 자산 경로로 매핑한다', () {
      expect(
        routeMapBasemapAssetForRegion('수도권'),
        'assets/datapacks/metro_map_pack/basemap/seoul.vec',
      );
      expect(
        routeMapBasemapAssetForRegion('부산'),
        'assets/datapacks/metro_map_pack/basemap/busan.vec',
      );
      expect(
        routeMapBasemapAssetForRegion('광주'),
        'assets/datapacks/metro_map_pack/basemap/gwangju.vec',
      );
      expect(
        routeMapBasemapAssetForRegion('대구'),
        'assets/datapacks/metro_map_pack/basemap/daegu.vec',
      );
      expect(
        routeMapBasemapAssetForRegion('대전'),
        'assets/datapacks/metro_map_pack/basemap/daejeon.vec',
      );
      expect(routeMapBasemapAssetForRegion('제주'), isNull);
      expect(routeMapBasemapAssetForRegion(''), isNull);
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
      final daejeonAsset = routeMapBasemapAssetForRegion('대전')!;
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

      final gwangjuAsset = routeMapBasemapAssetForRegion('광주')!;
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
      expect(identical(painter.picture, daejeonPicture), isTrue);
    });
  });
}
