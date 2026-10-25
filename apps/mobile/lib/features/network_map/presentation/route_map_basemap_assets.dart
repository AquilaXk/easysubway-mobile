import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../domain/route_map_line_overlay_index.dart';

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
  RouteMapBasemapAssets({required this.variant, AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

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

  final AssetBundle _bundle;

  final Map<String, PictureInfo> _pictures = {};
  final Map<String, Future<PictureInfo?>> _decodes = {};
  RouteMapBasemapVariantFiles? _files;
  Future<RouteMapBasemapVariantFiles?>? _filesLoad;
  // [resetForTest]마다 올린다. 그 전에 시작한 로드는 끝나도 아무것도 남기거나 보고하지 않는다.
  int _generation = 0;

  /// 읽고 검증한 색인의 [variant] 바탕·노선 레이어. 아직 읽지 않았으면 null.
  RouteMapBasemapVariantFiles? get files => _files;

  /// 색인을 읽어 [files]를 채운다. 읽는 중이면 그 로드를 함께 기다리고, 읽었으면 그 색인을
  /// 준다. 실패하면 보고하고 null로 끝나며, 로드를 남기지 않아 다음 호출이 다시 읽는다.
  Future<RouteMapBasemapVariantFiles?> loadFiles() {
    final generation = _generation;
    return _filesLoad ??= _readFiles(generation).whenComplete(() {
      if (generation == _generation && _files == null) {
        _filesLoad = null;
      }
    });
  }

  /// 디코드한 [asset] 그림. 아직 디코드하지 않았으면 null.
  PictureInfo? picture(String asset) => _pictures[asset];

  /// [asset]을 디코드해 [picture]에 둔다. 디코드했으면 그 그림을 그대로 주고, 디코드하는
  /// 중이면 그 디코드를 함께 기다린다. 실패하면 보고하고 null로 끝나며, 다음 호출이 다시
  /// 디코드한다.
  Future<PictureInfo?> decode(String asset) {
    final decoded = _pictures[asset];
    if (decoded != null) {
      return Future.value(decoded);
    }
    final generation = _generation;
    return _decodes[asset] ??= _decodePicture(asset, generation).whenComplete(
      () {
        if (generation == _generation) {
          _decodes.removeWhere((key, _) => key == asset);
        }
      },
    );
  }

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
      final json = await _bundle.loadString(
        kRouteMapLineOverlayIndexAssetPath,
        cache: false,
      );
      final files = RouteMapLineOverlayIndex.parse(json).variant(variant);
      return generation == _generation ? _files = files : null;
    } catch (error, stack) {
      if (generation == _generation) {
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
      final info = await vg.loadPicture(
        AssetBytesLoader(asset, assetBundle: _bundle),
        null,
      );
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
    }
  }
}
