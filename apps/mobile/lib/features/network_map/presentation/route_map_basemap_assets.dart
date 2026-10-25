import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../domain/route_map_line_overlay_index.dart';

/// `widget.data.selectedRegion`(한글) → 바탕 색인 권역 id.
/// 매핑에 없는 region은 basemap 미표시(빈 화면)로 안전 폴백한다(크래시 금지).
const Map<String, String> kRouteMapBasemapRegionToId = {
  '수도권': 'seoul',
  '부산': 'busan',
  '광주': 'gwangju',
  '대구': 'daegu',
  '대전': 'daejeon',
};

/// 바탕 자산을 읽거나 찾지 못한 오류를 Flutter 오류로 드러낸다.
void reportRouteMapBasemapFailure(
  Object error,
  StackTrace stack,
  String context,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'network_map',
      context: ErrorDescription(context),
    ),
  );
}

/// 바탕 색인과 디코드한 바탕·노선 레이어 그림. 앱의 바탕 뷰는 모두 [shared]를 함께 써서
/// 같은 .vec를 한 번만 디코드한다. 색인 읽기와 디코드 실패는 그 그림을 기다리는 뷰가 있든
/// 없든 시도마다 한 번 보고한다.
class RouteMapBasemapAssets {
  RouteMapBasemapAssets({required this.variant});

  /// 앱의 바탕 자산. dart:ui는 엔진의 Impeller 설정을 [ui.ImageFilter.isShaderFilterSupported]로
  /// 그대로 돌려주고(sky_engine painting.dart `isShaderFilterSupported => _impellerEnabled`),
  /// 렌더러는 프로세스 안에서 바뀌지 않는다.
  static final RouteMapBasemapAssets shared = RouteMapBasemapAssets(
    variant: RouteMapBasemapVariant.forRenderer(
      impeller: ui.ImageFilter.isShaderFilterSupported,
    ),
  );

  /// 바탕과 노선 레이어를 고르는 변형.
  final RouteMapBasemapVariant variant;

  final Map<String, PictureInfo> _pictures = {};
  final Map<String, Future<PictureInfo?>> _decodes = {};
  RouteMapBasemapVariantFiles? _files;
  Future<RouteMapBasemapVariantFiles?>? _filesLoad;
  // [resetForTest]마다 올린다. 그 전에 시작한 로드는 끝나도 아무것도 남기거나 보고하지 않는다.
  int _generation = 0;

  // loadString과 loadPicture는 async 함수라 첫 await에서 멈춘다. 그래서 아래 로드의 실패
  // 정리는 `??=`가 그 로드를 기억한 뒤에 돈다.

  /// 읽고 검증한 색인의 [variant] 바탕·노선 레이어. 아직 읽지 않았으면 null.
  RouteMapBasemapVariantFiles? get files => _files;

  /// 색인을 읽어 [files]를 채운다. 읽는 중이면 그 로드를 함께 기다린다. 실패하면 보고하고
  /// null로 끝나며, 로드를 남기지 않아 다음 호출이 다시 읽는다.
  Future<RouteMapBasemapVariantFiles?> loadFiles() =>
      _filesLoad ??= _readFiles(_generation);

  /// 디코드한 [asset] 그림. 아직 디코드하지 않았으면 null.
  PictureInfo? picture(String asset) => _pictures[asset];

  /// [asset]을 디코드해 [picture]에 둔다. 디코드하는 중이면 그 디코드를 함께 기다린다. 실패하면
  /// 보고하고 null로 끝나며, 다음 호출이 다시 디코드한다.
  Future<PictureInfo?> decode(String asset) =>
      _decodes[asset] ??= _decodePicture(asset, _generation);

  /// 디코드한 그림과 읽은 색인을 버린다. 진행 중인 로드는 끝나도 아무것도 남기지 않는다.
  @visibleForTesting
  void resetForTest() {
    _generation++;
    for (final info in _pictures.values) {
      info.picture.dispose();
    }
    _pictures.clear();
    _decodes.clear();
    _files = null;
    _filesLoad = null;
  }

  Future<RouteMapBasemapVariantFiles?> _readFiles(int generation) async {
    try {
      final json = await rootBundle.loadString(
        kRouteMapLineOverlayIndexAssetPath,
        cache: false,
      );
      final files = RouteMapLineOverlayIndex.parse(
        json,
        regionIds: kRouteMapBasemapRegionToId.values.toSet(),
      ).variant(variant);
      return generation == _generation ? _files = files : null;
    } catch (error, stack) {
      if (generation == _generation) {
        _filesLoad = null;
        reportRouteMapBasemapFailure(
          error,
          stack,
          '노선도 바탕 색인 로드 실패($kRouteMapLineOverlayIndexAssetPath)',
        );
      }
      return null;
    }
  }

  Future<PictureInfo?> _decodePicture(String asset, int generation) async {
    try {
      final info = await vg.loadPicture(AssetBytesLoader(asset), null);
      if (generation != _generation) {
        info.picture.dispose();
        return null;
      }
      return _pictures[asset] = info;
    } catch (error, stack) {
      if (generation == _generation) {
        reportRouteMapBasemapFailure(error, stack, '노선도 .vec 로드 실패($asset)');
      }
      return null;
    } finally {
      if (generation == _generation) {
        unawaited(_decodes.remove(asset));
      }
    }
  }
}
