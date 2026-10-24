import 'dart:io';

import 'package:easysubway_mobile/features/network_map/domain/route_map_line_overlay_index.dart';

/// 번들 바탕 색인(`line-overlays.json`). flutter test cwd(apps/mobile) 기준으로 연다.
final RouteMapLineOverlayIndex bundledBasemapIndex =
    RouteMapLineOverlayIndex.parse(
      File(kRouteMapLineOverlayIndexAssetPath).readAsStringSync(),
    );
