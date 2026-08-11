import 'dart:ui';

import 'package:easysubway_mobile/features/network_map/infrastructure/cached_route_map_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached route map path는 path reference와 bounds를 verbatim 보존한다', () {
    final path = Path()
      ..moveTo(10, 20)
      ..lineTo(30, 40);
    const bounds = Rect.fromLTRB(10, 20, 30, 40);

    final cached = CachedRouteMapPath(path, bounds);

    expect(cached.path, same(path));
    expect(cached.bounds, bounds);
  });
}
