// Ported from mourner/flatbush (v4.4.0) under the ISC License.
// Copyright (c) 2018 Vladimir Agafonkin
// Bitset scan pattern adapted from RoaringBitmap under the Apache-2.0 License.
// Copyright 2016 By the RoaringBitmap authors.
// See THIRD_PARTY_NOTICES.md in the repository root for full license texts.

import 'dart:math' as math;
import 'dart:typed_data';

/// 2D AABB 정적 공간 R-tree 색인 (Flatbush 이식).
///
/// 16-bit Fast Hilbert 곡선 정렬을 통한 고밀도 패킹과
/// 연속 `TypedData` 배열 기반의 무할당 스택 탐색을 제공한다.
class FlatbushSpatialIndex {
  FlatbushSpatialIndex(this.numItems, {int nodeSize = 16})
    : assert(numItems >= 0),
      assert(nodeSize >= 2),
      _nodeSize = nodeSize {
    var n = numItems;
    var total = n;
    final levelBounds = <int>[n];
    while (n > 1) {
      n = (n + nodeSize - 1) ~/ nodeSize;
      total += n;
      levelBounds.add(total);
    }
    _totalNodes = total;
    _levelBounds = List<int>.unmodifiable(levelBounds);
    _boxes = Float32List(total * 4);
    _indices = Uint32List(total);
    _searchStack = Uint32List(math.max(64, levelBounds.length * nodeSize));
  }

  static final FlatbushSpatialIndex empty = FlatbushSpatialIndex(0)..finish();

  final int numItems;
  final int _nodeSize;
  late final int _totalNodes;
  late final List<int> _levelBounds;
  late final Float32List _boxes;
  late final Uint32List _indices;
  late final Uint32List _searchStack;

  int _pos = 0;
  bool _built = false;

  bool get isBuilt => _built;

  /// AABB 항목을 추가한다. [numItems]개를 모두 채운 후 [finish]를 호출해야 한다.
  void add(double minX, double minY, double maxX, double maxY) {
    if (_pos >= numItems) {
      throw StateError('Cannot add more items than numItems ($numItems)');
    }
    final offset = _pos << 2;
    _boxes[offset] = minX.isFinite ? minX : 0.0;
    _boxes[offset + 1] = minY.isFinite ? minY : 0.0;
    _boxes[offset + 2] = maxX.isFinite ? maxX : 0.0;
    _boxes[offset + 3] = maxY.isFinite ? maxY : 0.0;
    _indices[_pos] = _pos;
    _pos++;
  }

  /// 트리를 Hilbert 곡선 기준으로 정렬하고 상위 레벨을 패킹한다.
  void finish() {
    if (_built) return;
    if (_pos != numItems) {
      throw StateError('Added $_pos items, expected $numItems');
    }

    if (numItems == 0) {
      _built = true;
      return;
    }

    // 1. 전체 바운딩 박스 계산
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    for (var i = 0; i < numItems; i++) {
      final o = i << 2;
      final x1 = _boxes[o];
      final y1 = _boxes[o + 1];
      final x2 = _boxes[o + 2];
      final y2 = _boxes[o + 3];
      if (x1 < minX) minX = x1;
      if (y1 < minY) minY = y1;
      if (x2 > maxX) maxX = x2;
      if (y2 > maxY) maxY = y2;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final maxExtent = math.max(width, height);

    // 2. 16-bit 힐베르트 값 계산 및 정렬
    final hilbertValues = Uint32List(numItems);
    final scale = maxExtent > 0 ? 65535.0 / maxExtent : 0.0;

    for (var i = 0; i < numItems; i++) {
      final o = i << 2;
      final cx = (_boxes[o] + _boxes[o + 2]) * 0.5;
      final cy = (_boxes[o + 1] + _boxes[o + 3]) * 0.5;
      final hx = ((cx - minX) * scale).floor().clamp(0, 65535);
      final hy = ((cy - minY) * scale).floor().clamp(0, 65535);
      hilbertValues[i] = _hilbert(hx, hy);
    }

    _sort(hilbertValues, _boxes, _indices, 0, numItems - 1);

    // 3. 상위 레벨 트리 빌드
    var offset = 0;
    for (var i = 0; i < _levelBounds.length - 1; i++) {
      final top = _levelBounds[i];
      final levelNodeCount = (top - offset + _nodeSize - 1) ~/ _nodeSize;
      for (var j = 0; j < levelNodeCount; j++) {
        final childStart = offset + j * _nodeSize;
        final childEnd = math.min(childStart + _nodeSize, top);

        var cMinX = double.infinity;
        var cMinY = double.infinity;
        var cMaxX = -double.infinity;
        var cMaxY = -double.infinity;

        for (var c = childStart; c < childEnd; c++) {
          final c4 = c << 2;
          if (_boxes[c4] < cMinX) cMinX = _boxes[c4];
          if (_boxes[c4 + 1] < cMinY) cMinY = _boxes[c4 + 1];
          if (_boxes[c4 + 2] > cMaxX) cMaxX = _boxes[c4 + 2];
          if (_boxes[c4 + 3] > cMaxY) cMaxY = _boxes[c4 + 3];
        }

        final p = top + j;
        final p4 = p << 2;
        _boxes[p4] = cMinX;
        _boxes[p4 + 1] = cMinY;
        _boxes[p4 + 2] = cMaxX;
        _boxes[p4 + 3] = cMaxY;
        _indices[p] = childStart;
      }
      offset = top;
    }

    _built = true;
  }

  /// 사각형 [minX, minY, maxX, maxY] 영역과 교차하는 항목을 무재귀 스택으로 탐색한다.
  void search(
    double minX,
    double minY,
    double maxX,
    double maxY,
    void Function(int originalIndex) onHit,
  ) {
    if (!_built || numItems == 0) return;

    final stack = _searchStack;
    var stackSize = 0;
    stack[stackSize++] = _totalNodes - 1;

    while (stackSize > 0) {
      final nodeIndex = stack[--stackSize];
      final node4 = nodeIndex << 2;

      // AABB 교차 검사
      if (minX > _boxes[node4 + 2] ||
          minY > _boxes[node4 + 3] ||
          maxX < _boxes[node4] ||
          maxY < _boxes[node4 + 1]) {
        continue;
      }

      if (nodeIndex < numItems) {
        // 리프 노드
        onHit(_indices[nodeIndex]);
      } else {
        // 내부 노드: 자식 노드 범위
        final childStart = _indices[nodeIndex];
        final childEnd = math.min(
          childStart + _nodeSize,
          _childLevelLimit(nodeIndex),
        );
        for (var c = childStart; c < childEnd; c++) {
          stack[stackSize++] = c;
        }
      }
    }
  }

  /// 사각형 [minX, minY, maxX, maxY]와 교차하는 항목들을 [bitset]에 마킹한다.
  void searchWithBitset(
    double minX,
    double minY,
    double maxX,
    double maxY,
    Uint64List bitset,
  ) {
    search(minX, minY, maxX, maxY, (originalIndex) {
      bitset[originalIndex >> 6] |= 1 << (originalIndex & 63);
    });
  }

  /// 부호 없는 64-bit 이진 CTZ(trailing zeros) 계산.
  /// Dart VM에서 `1 << 63`은 음수(`int.bitLength == 63`)가 되므로 논리 우시프트(`>>>`)로 정확히 `0..63`을 얻는다.
  static int ctz64(int word) {
    var y = word & -word;
    var n = 0;
    if ((y & 0xFFFFFFFF) == 0) {
      n += 32;
      y >>>= 32;
    }
    if ((y & 0xFFFF) == 0) {
      n += 16;
      y >>>= 16;
    }
    if ((y & 0xFF) == 0) {
      n += 8;
      y >>>= 8;
    }
    if ((y & 0xF) == 0) {
      n += 4;
      y >>>= 4;
    }
    if ((y & 0x3) == 0) {
      n += 2;
      y >>>= 2;
    }
    if ((y & 0x1) == 0) {
      n += 1;
    }
    return n;
  }

  /// RoaringBitmap 스타일의 CTZ 기반 단일 패스 비트셋 순회.
  /// 원래 입력 순서(`0..numItems-1`)를 `O(words)`로 복원한다.
  static void scanBits(Uint64List bitset, void Function(int index) onIndex) {
    for (var w = 0; w < bitset.length; w++) {
      var word = bitset[w];
      if (word == 0) continue;
      final base = w << 6;
      while (word != 0) {
        onIndex(base + ctz64(word));
        word &= word - 1;
      }
    }
  }

  int _childLevelLimit(int nodeIndex) {
    var i = 1;
    while (i < _levelBounds.length - 1 && nodeIndex >= _levelBounds[i]) {
      i++;
    }
    return _levelBounds[i - 1];
  }

  static int _hilbert(int x, int y) {
    var a = x ^ y;
    var b = 0xFFFF ^ a;
    var c = 0xFFFF ^ (x | y);
    var d = x & (y ^ 0xFFFF);

    var da = d | (a >> 1);
    var db = (a >> 1) ^ a;
    var dc = ((c >> 1) ^ (b & (d >> 1))) ^ c;
    var dd = ((d >> 1) ^ (a & (c >> 1))) ^ d;

    a ^= da;
    b ^= db;
    c ^= dc;
    d ^= dd;

    da = d | (a >> 2);
    db = (a >> 2) ^ a;
    dc = ((c >> 2) ^ (b & (d >> 2))) ^ c;
    dd = ((d >> 2) ^ (a & (c >> 2))) ^ d;

    a ^= da;
    b ^= db;
    c ^= dc;
    d ^= dd;

    da = d | (a >> 4);
    db = (a >> 4) ^ a;
    dc = ((c >> 4) ^ (b & (d >> 4))) ^ c;
    dd = ((d >> 4) ^ (a & (c >> 4))) ^ d;

    a ^= da;
    b ^= db;
    c ^= dc;
    d ^= dd;

    da = d | (a >> 8);
    db = (a >> 8) ^ a;
    dc = ((c >> 8) ^ (b & (d >> 8))) ^ c;
    dd = ((d >> 8) ^ (a & (c >> 8))) ^ d;

    a ^= da;
    b ^= db;
    c ^= dc;
    d ^= dd;

    a = ((a & 0x5555) | ((a & 0xAAAA) << 15));
    b = ((b & 0x5555) | ((b & 0xAAAA) << 15));
    c = ((c & 0x5555) | ((c & 0xAAAA) << 15));
    d = ((d & 0x5555) | ((d & 0xAAAA) << 15));

    return a | (b << 1) | (c << 2) | (d << 3);
  }

  static void _sort(
    Uint32List values,
    Float32List boxes,
    Uint32List indices,
    int left,
    int right,
  ) {
    if (left >= right) return;
    final pivot = values[(left + right) >> 1];
    var i = left - 1;
    var j = right + 1;
    while (true) {
      do {
        i++;
      } while (values[i] < pivot);
      do {
        j--;
      } while (values[j] > pivot);
      if (i >= j) break;
      _swap(values, boxes, indices, i, j);
    }
    _sort(values, boxes, indices, left, j);
    _sort(values, boxes, indices, j + 1, right);
  }

  static void _swap(
    Uint32List values,
    Float32List boxes,
    Uint32List indices,
    int i,
    int j,
  ) {
    final tempVal = values[i];
    values[i] = values[j];
    values[j] = tempVal;

    final tempIdx = indices[i];
    indices[i] = indices[j];
    indices[j] = tempIdx;

    final i4 = i << 2;
    final j4 = j << 2;
    for (var k = 0; k < 4; k++) {
      final tempBox = boxes[i4 + k];
      boxes[i4 + k] = boxes[j4 + k];
      boxes[j4 + k] = tempBox;
    }
  }
}
