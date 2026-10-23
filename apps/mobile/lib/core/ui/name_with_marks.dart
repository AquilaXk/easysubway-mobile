import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 이름 한 줄과 노선 마크 묶음을 한 줄에 놓는다. 이름이 우선이라 마크 묶음은 줄
/// 폭의 [maxMarksFraction]까지만 쓴다. 마크가 그보다 많으면 [marks]의 Wrap이
/// 다음 줄로 접히고, 이름은 나머지 폭을 모두 가진다. 큰 글자에서 마크 하나가 그
/// 폭보다 넓어져도 마크는 자기 폭 아래로 눌리지 않고, 이름이 나머지 폭을 쓴다.
class NameWithMarks extends StatelessWidget {
  const NameWithMarks({
    required this.name,
    required this.marks,
    this.marksFirst = false,
    this.gap = 8,
    this.maxMarksFraction = 0.4,
    super.key,
  });

  final Widget name;
  final Widget marks;
  final bool marksFirst;
  final double gap;
  final double maxMarksFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final budgetedMarks = _MarksBudget(
          maxWidth: constraints.maxWidth * maxMarksFraction,
          child: marks,
        );
        final children = [
          if (marksFirst) budgetedMarks else Expanded(child: name),
          SizedBox(width: gap),
          if (marksFirst) Expanded(child: name) else budgetedMarks,
        ];
        return Row(children: children);
      },
    );
  }
}

/// 자식에게 [maxWidth]를 주되, 자식 안 가장 넓은 마크 하나의 최소 폭보다는 좁히지
/// 않는다. 알약 마크가 예산보다 좁게 눌리면 마크 안 글자가 잘린다.
class _MarksBudget extends SingleChildRenderObjectWidget {
  const _MarksBudget({required this.maxWidth, required Widget super.child});

  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMarksBudget(maxWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMarksBudget renderObject,
  ) {
    renderObject.maxWidth = maxWidth;
  }
}

class _RenderMarksBudget extends RenderProxyBox {
  _RenderMarksBudget(this._maxWidth);

  double _maxWidth;

  set maxWidth(double value) {
    if (value == _maxWidth) {
      return;
    }
    _maxWidth = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final widestMark = child!.getMinIntrinsicWidth(double.infinity);
    return constraints.copyWith(
      maxWidth: math.min(constraints.maxWidth, math.max(_maxWidth, widestMark)),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child!.getDryLayout(_childConstraints(constraints));

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => child!.getDryBaseline(_childConstraints(constraints), baseline);

  @override
  void performLayout() {
    child!.layout(_childConstraints(constraints), parentUsesSize: true);
    size = child!.size;
  }
}
