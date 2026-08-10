import 'dart:ui' show Rect;

import 'network_map_models.dart';

abstract interface class NetworkMapRepository {
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId});
}

abstract interface class NetworkMapViewportRepository {
  Future<String?> loadSelectedRegion();

  Future<void> saveSelectedRegion(String region);

  Future<Rect?> loadViewport(String region);

  Future<void> saveViewport({required String region, required Rect viewport});
}
