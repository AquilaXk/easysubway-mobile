import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../domain/route_map_owner_nodes.dart';

Future<Map<String, RouteMapOwnerNodesLookup>>? _sharedOwnerNodesByRegionFuture;

Map<String, RouteMapOwnerNodesLookup>? _sharedOwnerNodesByRegionValue;

Object? _sharedOwnerNodesByRegionError;

StackTrace? _sharedOwnerNodesByRegionStackTrace;

Map<String, RouteMapOwnerNodesLookup>? get cachedNetworkMapOwnerNodesByRegion =>
    _sharedOwnerNodesByRegionValue;

Map<String, RouteMapOwnerNodesLookup> _decodeNetworkMapOwnerNodesSidecar(
  Uint8List bytes,
) {
  return routeMapOwnerNodesByRegionFrom(utf8.decode(bytes));
}

Future<Map<String, RouteMapOwnerNodesLookup>>
loadNetworkMapOwnerNodesByRegion() {
  if (_sharedOwnerNodesByRegionError != null) {
    return Future<Map<String, RouteMapOwnerNodesLookup>>.error(
      _sharedOwnerNodesByRegionError!,
      _sharedOwnerNodesByRegionStackTrace,
    );
  }
  return _sharedOwnerNodesByRegionFuture ??= rootBundle
      .load(kRouteMapOwnerNodesAssetPath)
      .then(
        (data) => compute(
          _decodeNetworkMapOwnerNodesSidecar,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      )
      .then((byRegion) {
        _sharedOwnerNodesByRegionValue = byRegion;
        return byRegion;
      });
}

void invalidateNetworkMapOwnerNodesLoad() {
  _sharedOwnerNodesByRegionFuture = null;
  _sharedOwnerNodesByRegionError = null;
  _sharedOwnerNodesByRegionStackTrace = null;
}

@visibleForTesting
void resetNetworkMapOwnerNodesCacheForTest() {
  _sharedOwnerNodesByRegionFuture = null;
  _sharedOwnerNodesByRegionValue = null;
  _sharedOwnerNodesByRegionError = null;
  _sharedOwnerNodesByRegionStackTrace = null;
}

@visibleForTesting
void primeNetworkMapOwnerNodesCacheForTest(
  Map<String, RouteMapOwnerNodesLookup> byRegion,
) {
  _sharedOwnerNodesByRegionFuture = Future.value(byRegion);
  _sharedOwnerNodesByRegionValue = byRegion;
  _sharedOwnerNodesByRegionError = null;
  _sharedOwnerNodesByRegionStackTrace = null;
}

@visibleForTesting
void primeNetworkMapOwnerNodesCacheErrorForTest(
  Object error, [
  StackTrace? stackTrace,
]) {
  _sharedOwnerNodesByRegionFuture = null;
  _sharedOwnerNodesByRegionValue = null;
  _sharedOwnerNodesByRegionError = error;
  _sharedOwnerNodesByRegionStackTrace = stackTrace;
}
