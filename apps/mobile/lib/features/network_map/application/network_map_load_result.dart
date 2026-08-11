import 'package:flutter/widgets.dart';

import '../domain/network_map_models.dart';

/// Network Map data와 초기 persisted viewport를 함께 전달하는 load outcome.
class NetworkMapLoadResult {
  const NetworkMapLoadResult({
    required this.data,
    required this.initialViewport,
  });

  final NetworkMapData data;
  final Rect? initialViewport;
}
