import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 탭·길게 누르기 요소의 최소 크기 가이드라인으로, 스크롤 목록 안의 요소도 검사한다.
///
/// Flutter의 `MinimumTapTargetGuideline`은 스크롤러 안의 요소를 사실상 건너뛴다.
/// 요소의 화면 좌표 영역을 스크롤러 자체의 좌표계 영역과 견주기 때문에 스크롤러 안의
/// 요소는 경계에 닿은 것으로 판정되고, 의도는 스크롤로 잘린 요소의 오탐 방지다
/// (`flutter_test/lib/src/accessibility.dart`의 `_kMinimumGapToBoundary` 주석).
/// 그래서 목록 안의 30dp 버튼도 통과한다(#490).
///
/// 이 가이드라인은 같은 의도를 지키되 판정을 정확히 한다. 요소가 모든 스크롤러
/// 뷰포트와 화면에 **완전히 들어올 때만** 크기를 검사하고, 일부만 보이거나 화면 밖이면
/// 건너뛴다. 병합된 노드, 숨겨진 노드, 링크, 탭 액션이 없는 노드는 Flutter 기본
/// 가이드라인과 같이 건너뛴다. 끝까지 스크롤하며 검사하지는 않으므로 화면에 보이는
/// 부분만 검사한다.
///
/// 근거: 화면의 모든 탭 요소에 스크롤 여부와 무관하게 최소 터치 영역을 요구한다
/// (Android 48dp https://developer.android.com/guide/topics/ui/accessibility/apps#large-controls ,
/// Apple HIG 44pt).
class FullTapTargetGuideline extends AccessibilityGuideline {
  const FullTapTargetGuideline(this.size);

  final Size size;

  /// 이 간격 이하로 경계에 붙은 요소는 잘렸을 수 있어 건너뛴다. Flutter 기본값과 같다.
  static const double _edgeGap = 0.001;

  @override
  String get description =>
      'Tappable objects, including those inside '
      'scrollables, should be at least $size';

  @override
  Evaluation evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(
        view.flutterView,
        view.owner!.semanticsOwner!.rootSemanticsNode!,
      );
    }
    return result;
  }

  Evaluation _traverse(ui.FlutterView view, SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(view, child);
      return true;
    });
    if (node.isMergedIntoParent || _isNotTapTarget(node)) {
      return result;
    }
    final bounds = _boundsIfFullyVisible(view, node);
    if (bounds == null) {
      return result;
    }
    final found = bounds.size / view.devicePixelRatio;
    if (found.width < size.width - precisionErrorTolerance ||
        found.height < size.height - precisionErrorTolerance) {
      result += Evaluation.fail(
        '$node: expected tap target size of at least $size, '
        'but found $found',
      );
    }
    return result;
  }

  static bool _isNotTapTarget(SemanticsNode node) {
    final data = node.getSemanticsData();
    final hasTapAction =
        data.hasAction(ui.SemanticsAction.tap) ||
        data.hasAction(ui.SemanticsAction.longPress);
    return !hasTapAction ||
        data.flagsCollection.isHidden ||
        data.flagsCollection.isLink;
  }

  /// [node]의 화면 좌표 영역을 돌려준다. 스크롤러 뷰포트나 화면 가장자리에 닿아 일부가
  /// 잘렸을 수 있으면 null이다.
  ///
  /// 시맨틱스 트리는 잘린 요소의 영역을 보이는 부분으로 줄여 담으므로, 일부만 보이는
  /// 요소는 항상 자르는 경계에 닿는다. 각 조상 좌표계에서 영역이 경계에 닿는지 본다.
  /// 스크롤러 안에서는 스크롤 축의 경계만 본다. 가로로 꽉 찬 목록 행은 스크롤과 무관하게
  /// 좌우 경계에 붙기 때문이다. 스크롤러 밖에서는 Flutter 기본 가이드라인처럼 화면의
  /// 네 경계를 모두 본다.
  static Rect? _boundsIfFullyVisible(ui.FlutterView view, SemanticsNode node) {
    var bounds = node.rect;
    var current = node;
    var insideScroller = false;
    while (current.parent != null) {
      final transform = current.transform;
      if (transform != null) {
        bounds = MatrixUtils.transformRect(transform, bounds);
      }
      current = current.parent!;
      if (current.flagsCollection.hasImplicitScrolling) {
        insideScroller = true;
        if (_touchesScrollEdge(bounds, current)) {
          return null;
        }
      }
    }
    if (!insideScroller &&
        _touchesEdge(bounds, Offset.zero & view.physicalSize)) {
      return null;
    }
    return bounds;
  }

  static bool _touchesScrollEdge(Rect bounds, SemanticsNode scroller) {
    final data = scroller.getSemanticsData();
    final scrollsVertically =
        data.hasAction(ui.SemanticsAction.scrollUp) ||
        data.hasAction(ui.SemanticsAction.scrollDown);
    final scrollsHorizontally =
        data.hasAction(ui.SemanticsAction.scrollLeft) ||
        data.hasAction(ui.SemanticsAction.scrollRight);
    final viewport = scroller.rect;
    return (scrollsVertically &&
            (bounds.top - viewport.top <= _edgeGap ||
                viewport.bottom - bounds.bottom <= _edgeGap)) ||
        (scrollsHorizontally &&
            (bounds.left - viewport.left <= _edgeGap ||
                viewport.right - bounds.right <= _edgeGap));
  }

  static bool _touchesEdge(Rect inner, Rect outer) =>
      inner.left - outer.left <= _edgeGap ||
      outer.right - inner.right <= _edgeGap ||
      inner.top - outer.top <= _edgeGap ||
      outer.bottom - inner.bottom <= _edgeGap;
}
