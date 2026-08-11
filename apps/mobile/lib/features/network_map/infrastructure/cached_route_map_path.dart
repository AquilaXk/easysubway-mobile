import 'dart:ui';

/// Parsed route-map path와 이미 계산한 source bounds를 함께 보관한다.
class CachedRouteMapPath {
  const CachedRouteMapPath(this.path, this.bounds);

  final Path path;
  final Rect bounds;
}
