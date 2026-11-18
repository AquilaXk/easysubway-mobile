import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';
import 'package:easysubway_mobile/features/network_map/domain/structured_route_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_assets.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_popover_menu.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_index.dart';
import '../../../support/basemap_waits.dart';

class _MappedVecBundle extends CachingAssetBundle {
  _MappedVecBundle(this._vecBytesByKey);

  final Map<String, ByteData> _vecBytesByKey;

  @override
  Future<ByteData> load(String key) {
    final data = _vecBytesByKey[key];
    if (data == null) {
      throw FlutterError('Missing test asset: $key');
    }
    return Future.value(data);
  }
}

MapCameraState _camera(Size viewport) => MapCameraState(
  sourceBounds: const Rect.fromLTWH(0, 0, 500, 500),
  viewportSize: viewport,
  center: const Offset(250, 250),
  scale: 1,
  minScale: 0.5,
  maxScale: 4,
  revision: 0,
);

void main() {
  group('RouteMapBasemapAssets LRU eviction & pin safety', () {
    late ByteData sampleVecBytes;

    setUpAll(() {
      final anyVec = bundledBasemapIndexFiles(
        RouteMapBasemapVariant.text,
      ).keys.first;
      sampleVecBytes = bundledAsset(anyVec);
    });

    test('LRU 상한을 넘기면 가장 오래 미사용된 PictureInfo를 제거하고 dispose한다', () async {
      final bundle = _MappedVecBundle({
        'a.vec': sampleVecBytes,
        'b.vec': sampleVecBytes,
        'c.vec': sampleVecBytes,
      });
      final assets = RouteMapBasemapAssets(
        variant: RouteMapBasemapVariant.text,
        bundle: bundle,
        maxCachedPictures: 2,
      );

      final infoA = await assets.decode('a.vec');
      final infoB = await assets.decode('b.vec');
      expect(infoA, isNotNull);
      expect(infoB, isNotNull);
      expect(assets.cachedPictureCount, 2);

      // c를 추가하면 미사용 a가 제거·dispose 된다.
      final infoC = await assets.decode('c.vec');
      expect(infoC, isNotNull);
      expect(assets.cachedPictureCount, 2);
      expect(assets.picture('a.vec'), isNull);
      expect(infoA!.picture.debugDisposed, isTrue);
      expect(assets.picture('b.vec'), isNotNull);
      expect(assets.picture('c.vec'), isNotNull);
      expect(infoB!.picture.debugDisposed, isFalse);

      assets.resetForTest();
    });

    test('picture() 캐시 적중 시 LRU 순위가 갱신되어 다음 제거 대상에서 제외된다', () async {
      final bundle = _MappedVecBundle({
        'a.vec': sampleVecBytes,
        'b.vec': sampleVecBytes,
        'c.vec': sampleVecBytes,
      });
      final assets = RouteMapBasemapAssets(
        variant: RouteMapBasemapVariant.text,
        bundle: bundle,
        maxCachedPictures: 2,
      );

      final infoA = await assets.decode('a.vec');
      final infoB = await assets.decode('b.vec');
      expect(assets.picture('a.vec'), same(infoA));

      await assets.decode('c.vec');
      expect(assets.picture('a.vec'), same(infoA));
      expect(infoA!.picture.debugDisposed, isFalse);
      expect(assets.picture('b.vec'), isNull);
      expect(infoB!.picture.debugDisposed, isTrue);

      assets.resetForTest();
    });

    test('retain으로 고정된 사용 중 Picture는 LRU 초과 시에도 즉시 dispose되지 않는다', () async {
      final bundle = _MappedVecBundle({
        'a.vec': sampleVecBytes,
        'b.vec': sampleVecBytes,
        'c.vec': sampleVecBytes,
      });
      final assets = RouteMapBasemapAssets(
        variant: RouteMapBasemapVariant.text,
        bundle: bundle,
        maxCachedPictures: 2,
      );

      final infoA = await assets.decode('a.vec');
      assets.retain('a.vec');
      final infoB = await assets.decode('b.vec');
      final infoC = await assets.decode('c.vec');

      expect(infoA!.picture.debugDisposed, isFalse);
      expect(assets.picture('a.vec'), same(infoA));
      expect(infoB!.picture.debugDisposed, isTrue);
      expect(infoC!.picture.debugDisposed, isFalse);

      // c가 가장 최근이므로 release 후 d를 넣거나 이미 초과면 a가 정리될 수 있게 확인.
      assets.release('a.vec');
      expect(infoA.picture.debugDisposed, isFalse);
      bundle.clear();
      assets.resetForTest();
    });

    test('maxCachedPictures가 0 이하이면 ArgumentError를 던진다', () {
      expect(
        () => RouteMapBasemapAssets(
          variant: RouteMapBasemapVariant.text,
          maxCachedPictures: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Empty viewport & empty map SizedBox.shrink', () {
    testWidgets('StructuredRouteMapView는 빈 뷰포트나 빈 지도에서 CustomPaint를 만들지 않는다', (
      tester,
    ) async {
      const emptyMap = StructuredRouteMap(
        lines: [],
        stations: [],
        transferGroups: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: StructuredRouteMapView(
            map: emptyMap,
            camera: _camera(Size.zero),
            lineColors: const {},
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(StructuredRouteMapView),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(StructuredRouteMapView),
          matching: find.byType(SizedBox),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: StructuredRouteMapView(
            map: emptyMap,
            camera: _camera(const Size(300, 300)),
            lineColors: const {},
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(StructuredRouteMapView),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'RouteMapBasemapView는 빈 뷰포트에서 CustomPaint를 생략하고 비어있지 않은 미매핑 권역은 유지한다',
      (tester) async {
        final assets = RouteMapBasemapAssets(
          variant: RouteMapBasemapVariant.text,
        );
        final errors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: RouteMapBasemapView(
                region: '없는지역',
                camera: _camera(Size.zero),
                assets: assets,
              ),
            ),
          );
          expect(
            find.descendant(
              of: find.byType(RouteMapBasemapView),
              matching: find.byType(CustomPaint),
            ),
            findsNothing,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: RouteMapBasemapView(
                region: '없는지역',
                camera: _camera(const Size(320, 240)),
                assets: assets,
              ),
            ),
          );
          expect(paintedBasemapPictures(tester), [null]);
          expect(errors, hasLength(1));
          expect(errors.single.exception, isArgumentError);
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );

    testWidgets(
      'StationPopoverMenu 꼬리 페인터와 attribution 페인터가 재사용 Paint로 정상 렌더링된다',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  StationPopoverMenu(
                    width: 220,
                    stationName: '시청역',
                    selectedSlots: const {RouteDraftSlot.origin},
                    disabledSlots: const {},
                    onAction: (_) {},
                    onClose: () {},
                  ),
                  SizedBox(
                    width: 300,
                    height: 120,
                    child: StructuredRouteMapView(
                      map: const StructuredRouteMap(
                        lines: [
                          RouteMapLineGeometry(
                            lineId: 'line-1',
                            polylines: [
                              [Offset(10, 10), Offset(100, 10)],
                            ],
                          ),
                        ],
                        stations: [],
                        transferGroups: [],
                      ),
                      camera: _camera(const Size(300, 120)),
                      lineColors: const {'line-1': Color(0xFF0052A4)},
                      attributionText: '출처 표기',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(CustomPaint), findsWidgets);
      },
    );
  });
}
