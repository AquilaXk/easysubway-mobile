import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android 최소 탭 영역 48dp(Android 접근성 가이드, large-controls 항목)다.
/// https://developer.android.com/guide/topics/ui/accessibility/apps#large-controls
const androidMinTapTarget = Size(48, 48);

/// iOS 최소 탭 영역 44pt(Apple HIG Accessibility의 Controls 항목)다.
/// https://developer.apple.com/design/human-interface-guidelines/accessibility
const iosMinTapTarget = Size(44, 44);

/// 탭·길게 누르기 요소의 최소 크기 가이드라인으로, 스크롤 목록 안의 요소도 검사한다.
///
/// Flutter(3.44.0)의 `MinimumTapTargetGuideline._traverse`는 조상 스크롤러에 대해
/// `_isAtBoundary`를 호출해(`flutter_test/lib/src/accessibility.dart` 165~166행) 노드가
/// 스크롤러 영역의 **네 변 중 하나라도** 닿으면 건너뛴다. 스크롤 방향을 보지 않으므로
/// 가로 폭을 꽉 채운 목록 행은 좌우 경계에 닿아 스크롤과 무관하게 건너뛰어지고,
/// 스크롤 시작이나 끝에 붙은 요소도 건너뛰어진다. 건너뛰는 의도는 스크롤로 잘린 요소의
/// 오탐 방지다(`_kMinimumGapToBoundary` 131행 주석). 그래서 꽉 찬 행의 30dp 버튼도
/// 통과한다(#490).
///
/// 이 가이드라인은 같은 의도를 지키되 스크롤 방향을 반영한다. 스크롤러 안에서 위·왼쪽
/// 변은 `scrollDown`·`scrollRight` 액션이 있을 때만, 아래·오른쪽 변은 `scrollUp`·
/// `scrollLeft` 액션이 있을 때만 잘림 후보로 본다. 따라서 스크롤 시작이나 끝에 붙은
/// 완전히 보이는 요소도 검사하고, 일부만 보이는 요소는 건너뛴다. 병합된 노드, 숨겨진
/// 노드, 링크, 탭 액션이 없는 노드도 Flutter 기본 가이드라인과 같이 건너뛴다. 끝까지
/// 스크롤하며 검사하지는 않으므로 화면에 보이는 부분만 검사한다.
///
/// 근거: 화면의 모든 탭 요소에 스크롤 여부와 무관하게 최소 터치 영역을 요구한다
/// ([androidMinTapTarget], [iosMinTapTarget]).
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

  /// [node]의 화면 좌표 영역을 돌려준다. 스크롤러 뷰포트나 화면 가장자리에서 일부가
  /// 잘렸을 수 있으면 null이다.
  ///
  /// 시맨틱스 트리는 잘린 요소의 영역을 보이는 부분으로 줄여 담으므로, 일부만 보이는
  /// 요소는 항상 자르는 경계에 닿는다. 각 조상 좌표계에서 영역이 경계에 닿는지 본다.
  /// 스크롤러 안에서는 스크롤할 수 있는 방향의 경계만 보고, 스크롤러 밖에서는 Flutter
  /// 기본 가이드라인처럼 화면의 네 경계를 모두 본다.
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
        if (_mayBeClippedByScroller(bounds, current)) {
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

  /// 스크롤러가 [bounds]를 자를 수 있는 변에 [bounds]가 닿으면 true다. 위·왼쪽 변은
  /// 그쪽에 더 있는 내용을 불러오는 `scrollDown`·`scrollRight`가, 아래·오른쪽 변은
  /// `scrollUp`·`scrollLeft`가 있을 때만 자른다.
  static bool _mayBeClippedByScroller(Rect bounds, SemanticsNode scroller) {
    final data = scroller.getSemanticsData();
    final viewport = scroller.rect;
    return (data.hasAction(ui.SemanticsAction.scrollDown) &&
            _atEdge(bounds.top - viewport.top)) ||
        (data.hasAction(ui.SemanticsAction.scrollUp) &&
            _atEdge(viewport.bottom - bounds.bottom)) ||
        (data.hasAction(ui.SemanticsAction.scrollRight) &&
            _atEdge(bounds.left - viewport.left)) ||
        (data.hasAction(ui.SemanticsAction.scrollLeft) &&
            _atEdge(viewport.right - bounds.right));
  }

  static bool _touchesEdge(Rect inner, Rect outer) =>
      _atEdge(inner.left - outer.left) ||
      _atEdge(outer.right - inner.right) ||
      _atEdge(inner.top - outer.top) ||
      _atEdge(outer.bottom - inner.bottom);

  static bool _atEdge(double gap) => gap <= _edgeGap;
}
