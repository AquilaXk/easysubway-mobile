import 'dart:async';
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
  RouteMapBasemapAssets({
    required this.variant,
    AssetBundle? bundle,
    this.maxCachedPictures = defaultMaxCachedPictures,
  }) : _bundle = bundle ?? rootBundle {
    if (maxCachedPictures <= 0) {
      throw ArgumentError.value(
        maxCachedPictures,
        'maxCachedPictures',
        'must be greater than 0',
      );
    }
  }

  /// LRU 그림 캐시 기본 상한(모든 권역 바탕 + 강조 노선 레이어를 여유 있게 수용).
  static const int defaultMaxCachedPictures = 64;

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

  /// 캐시에 동시에 보관할 최대 [PictureInfo] 수.
  final int maxCachedPictures;

  final AssetBundle _bundle;

  final Map<String, PictureInfo> _pictures = {};
  final Map<String, int> _pinCounts = {};
  final Map<String, Future<PictureInfo?>> _decodes = {};
  RouteMapBasemapVariantFiles? _files;
  Future<RouteMapBasemapVariantFiles?>? _filesLoad;
  // [resetForTest]마다 올린다. 그 전에 시작한 로드는 끝나도 아무것도 남기거나 보고하지 않는다.
  int _generation = 0;

  @visibleForTesting
  int get cachedPictureCount => _pictures.length;

  /// 현재 화면이 사용 중인 [asset]이 LRU 제거로 조기 `dispose()` 되지 않도록 고정한다.
  void retain(String asset) {
    _pinCounts[asset] = (_pinCounts[asset] ?? 0) + 1;
    _touch(asset);
  }

  /// [retain]으로 고정한 [asset]의 사용 참조를 해제하고, 상한 초과 미사용 캐시가 있으면 정리한다.
  void release(String asset) {
    final current = _pinCounts[asset];
    if (current == null) {
      return;
    }
    if (current <= 1) {
      _pinCounts.remove(asset);
      _evictIfNeeded();
      return;
    }
    _pinCounts[asset] = current - 1;
  }

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

  /// 끝나지 않은 색인 로드나 .vec 디코드가 있는지. 읽는 일이 모두 끝났다는 확인에 시험이 쓴다.
  @visibleForTesting
  bool get hasPendingReads =>
      _decodes.isNotEmpty || (_filesLoad != null && _files == null);

  /// 디코드한 [asset] 그림. 아직 디코드하지 않았으면 null.
  PictureInfo? picture(String asset) {
    final info = _pictures[asset];
    if (info != null) {
      _touch(asset);
    }
    return info;
  }

  /// [asset]을 디코드해 [picture]에 둔다. 디코드했으면 그 그림을 그대로 주고, 디코드하는
  /// 중이면 그 디코드를 함께 기다린다. 실패하면 보고하고 null로 끝나며, 다음 호출이 다시
  /// 디코드한다.
  Future<PictureInfo?> decode(String asset) {
    final decoded = _pictures[asset];
    if (decoded != null) {
      _touch(asset);
      return Future.value(decoded);
    }
    final generation = _generation;
    return _decodes[asset] ??= _decodePicture(asset, generation).whenComplete(
      () {
        if (generation == _generation) {
          unawaited(_decodes.remove(asset));
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
    _pinCounts.clear();
    _decodes.clear();
    _files = null;
    _filesLoad = null;
  }

  void _touch(String asset) {
    final existing = _pictures.remove(asset);
    if (existing != null) {
      _pictures[asset] = existing;
    }
  }

  void _putPicture(String asset, PictureInfo info) {
    _pictures[asset] = info;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    while (_pictures.length > maxCachedPictures) {
      String? evictKey;
      for (final key in _pictures.keys) {
        if ((_pinCounts[key] ?? 0) == 0) {
          evictKey = key;
          break;
        }
      }
      if (evictKey == null) {
        break;
      }
      final evicted = _pictures.remove(evictKey);
      evicted?.picture.dispose();
    }
  }

  Future<RouteMapBasemapVariantFiles?> _readFiles(int generation) async {
    try {
      final json = await _bundle.loadString(
        kRouteMapLineOverlayIndexAssetPath,
        cache: false,
      );
      final files = RouteMapLineOverlayIndex.parse(json).variant(variant);
      if (generation != _generation) {
        return null;
      }
      _files = files;
      return files;
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
      _putPicture(asset, info);
      return info;
    } catch (error, stack) {
      if (generation == _generation) {
        reportRouteMapBasemapFailure(error, stack, '노선도 .vec 로드 실패($asset)');
      }
      return null;
    }
  }
}
