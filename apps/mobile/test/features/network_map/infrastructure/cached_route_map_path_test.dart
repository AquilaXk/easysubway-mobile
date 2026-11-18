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

  test('route map path cache는 동일 key를 재사용하고 origin을 bounds에 반영한다', () {
    final first = cachedRouteMapPath('M 10 20 L 30 40', const Offset(5, 10));
    final sameKey = cachedRouteMapPath('M 10 20 L 30 40', const Offset(5, 10));
    final zeroOrigin = cachedRouteMapPath('M 10 20 L 30 40', Offset.zero);

    expect(sameKey, same(first));
    expect(first.bounds, const Rect.fromLTRB(5, 10, 25, 30));
    expect(zeroOrigin.bounds, const Rect.fromLTRB(10, 20, 30, 40));
  });

  test('route map SVG parser는 기존 absolute와 relative command를 보존한다', () {
    final cached = cachedRouteMapPath(
      'M 0 0 m 1 1 L 2 1 l 1 0 H 4 h 1 V 2 v 1 '
      'C 5 4 6 5 7 5 c 1 0 2 1 3 1 '
      'S 12 7 13 8 s 1 1 2 1 '
      'Q 16 10 17 11 q 1 1 2 1 X',
      Offset.zero,
    );

    expect(cached.bounds.isEmpty, isFalse);
    expect(cached.bounds.right, 19);
    expect(cached.bounds.bottom, 12);
  });
}
