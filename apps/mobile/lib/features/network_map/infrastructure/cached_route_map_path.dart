import 'dart:collection';
import 'dart:ui';

/// Parsed route-map path와 이미 계산한 source bounds를 함께 보관한다.
class CachedRouteMapPath {
  const CachedRouteMapPath(this.path, this.bounds);

  final Path path;
  final Rect bounds;
}

const int _maxRouteMapPathCacheEntries = 1024;
final LinkedHashMap<String, CachedRouteMapPath> _routeMapPathCache =
    LinkedHashMap<String, CachedRouteMapPath>();
final RegExp _svgPathTokenPattern = RegExp(r'[A-Za-z]|-?\d+(?:\.\d+)?');

bool _isAsciiLetter(String token) {
  if (token.length != 1) {
    return false;
  }
  final code = token.codeUnitAt(0) & 0xDF;
  return code >= 0x41 && code <= 0x5A;
}

CachedRouteMapPath cachedRouteMapPath(String pathData, Offset origin) {
  final key = '${origin.dx}:${origin.dy}:$pathData';
  final existing = _routeMapPathCache.remove(key);
  if (existing != null) {
    _routeMapPathCache[key] = existing;
    return existing;
  }
  final path = _pathFromSvg(pathData).shift(-origin);
  final created = CachedRouteMapPath(path, path.getBounds());
  if (_routeMapPathCache.length >= _maxRouteMapPathCacheEntries) {
    _routeMapPathCache.remove(_routeMapPathCache.keys.first);
  }
  _routeMapPathCache[key] = created;
  return created;
}

Path _pathFromSvg(String data) {
  final tokens = [
    for (final match in _svgPathTokenPattern.allMatches(data)) match.group(0)!,
  ];
  final path = Path();
  var index = 0;
  var command = '';
  var current = Offset.zero;
  var lastControl = Offset.zero;
  while (index < tokens.length) {
    if (_isAsciiLetter(tokens[index])) {
      command = tokens[index++];
    }
    double number() => double.parse(tokens[index++]);
    switch (command) {
      case 'M':
        current = Offset(number(), number());
        path.moveTo(current.dx, current.dy);
        break;
      case 'm':
        current += Offset(number(), number());
        path.moveTo(current.dx, current.dy);
        break;
      case 'L':
        current = Offset(number(), number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'l':
        current += Offset(number(), number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'H':
        current = Offset(number(), current.dy);
        path.lineTo(current.dx, current.dy);
        break;
      case 'h':
        current = Offset(current.dx + number(), current.dy);
        path.lineTo(current.dx, current.dy);
        break;
      case 'V':
        current = Offset(current.dx, number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'v':
        current = Offset(current.dx, current.dy + number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'C':
        final c1 = Offset(number(), number());
        final c2 = Offset(number(), number());
        current = Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 'c':
        final c1 = current + Offset(number(), number());
        final c2 = current + Offset(number(), number());
        current += Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 'S':
        final c1 = current * 2 - lastControl;
        final c2 = Offset(number(), number());
        current = Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 's':
        final c1 = current * 2 - lastControl;
        final c2 = current + Offset(number(), number());
        current += Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 'Q':
        final c = Offset(number(), number());
        current = Offset(number(), number());
        lastControl = c;
        path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
        break;
      case 'q':
        final c = current + Offset(number(), number());
        current += Offset(number(), number());
        lastControl = c;
        path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
        break;
      default:
        return path;
    }
  }
  return path;
}
