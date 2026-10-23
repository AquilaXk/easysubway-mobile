import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 이름 한 줄과 노선 마크 묶음을 한 줄에 놓는다. 이름이 우선이라 마크 묶음은 줄
/// 폭의 [maxMarksFraction]까지만 쓴다. 마크가 그보다 많으면 [marks]의 Wrap이
/// 다음 줄로 접히고, 이름은 나머지 폭을 모두 가진다. 큰 글자에서 마크 하나가 그
/// 폭보다 넓어져도 마크는 자기 폭 아래로 눌리지 않고, 이름이 나머지 폭을 쓴다.
///
/// 이름이 줄을 바꿀 수 없는 칸(입력 칸처럼 한 줄 말줄임)은 [hideMarksOverBudget]을
/// 켠다. 마크 하나가 예산보다 넓으면 마크를 눌러 이름을 깎는 대신 마크 묶음과
/// 사이 간격을 통째로 감추고 이름이 줄 전체를 쓴다.
class NameWithMarks extends StatelessWidget {
  const NameWithMarks({
    required this.name,
    required this.marks,
    this.marksFirst = false,
    this.gap = 8,
    this.maxMarksFraction = 0.4,
    this.hideMarksOverBudget = false,
    super.key,
  });

  final Widget name;
  final Widget marks;
  final bool marksFirst;
  final double gap;
  final double maxMarksFraction;
  final bool hideMarksOverBudget;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final budgetedMarks = _MarksBudget(
          maxWidth: constraints.maxWidth * maxMarksFraction,
          gap: gap,
          gapAfterMarks: marksFirst,
          hideOverBudget: hideMarksOverBudget,
          child: marks,
        );
        return Row(
          children: [
            if (marksFirst) budgetedMarks else Expanded(child: name),
            if (marksFirst) Expanded(child: name) else budgetedMarks,
          ],
        );
      },
    );
  }
}

/// 자식에게 [maxWidth]를 주되, 자식 안 가장 넓은 마크 하나의 최소 폭보다는 좁히지
/// 않는다. 알약 마크가 예산보다 좁게 눌리면 마크 안 글자가 잘린다. 이름과의 간격
/// [gap]도 이 상자가 가져서, [hideOverBudget]이 켜진 칸에서 마크 하나가 예산보다
/// 넓으면 자식과 간격이 함께 사라진다.
class _MarksBudget extends SingleChildRenderObjectWidget {
  const _MarksBudget({
    required this.maxWidth,
    required this.gap,
    required this.gapAfterMarks,
    required this.hideOverBudget,
    required Widget super.child,
  });

  final double maxWidth;
  final double gap;
  final bool gapAfterMarks;
  final bool hideOverBudget;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMarksBudget(maxWidth, gap, gapAfterMarks, hideOverBudget);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMarksBudget renderObject,
  ) {
    renderObject
      ..maxWidth = maxWidth
      ..gap = gap
      ..gapAfterMarks = gapAfterMarks
      ..hideOverBudget = hideOverBudget;
  }
}

class _RenderMarksBudget extends RenderShiftedBox {
  _RenderMarksBudget(
    this._maxWidth,
    this._gap,
    this._gapAfterMarks,
    this._hideOverBudget,
  ) : super(null);

  double _maxWidth;
  double _gap;
  bool _gapAfterMarks;
  bool _hideOverBudget;

  set maxWidth(double value) {
    if (value != _maxWidth) {
      _maxWidth = value;
      markNeedsLayout();
    }
  }

  set gap(double value) {
    if (value != _gap) {
      _gap = value;
      markNeedsLayout();
    }
  }

  set gapAfterMarks(bool value) {
    if (value != _gapAfterMarks) {
      _gapAfterMarks = value;
      markNeedsLayout();
    }
  }

  set hideOverBudget(bool value) {
    if (value != _hideOverBudget) {
      _hideOverBudget = value;
      markNeedsLayout();
    }
  }

  bool _hidden = false;

  bool _overBudget() =>
      _hideOverBudget &&
      child!.getMinIntrinsicWidth(double.infinity) > _maxWidth;

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final widestMark = child!.getMinIntrinsicWidth(double.infinity);
    return constraints.copyWith(
      maxWidth: math.min(
        math.max(0.0, constraints.maxWidth - _gap),
        math.max(_maxWidth, widestMark),
      ),
    );
  }

  Size _boxSize(Size childSize) =>
      Size(childSize.width + _gap, childSize.height);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (_overBudget()) {
      return constraints.constrain(Size.zero);
    }
    return _boxSize(child!.getDryLayout(_childConstraints(constraints)));
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    if (_overBudget()) {
      return null;
    }
    return child!.getDryBaseline(_childConstraints(constraints), baseline);
  }

  @override
  void performLayout() {
    final child = this.child!;
    _hidden = _overBudget();
    final parentData = child.parentData! as BoxParentData;
    if (_hidden) {
      child.layout(BoxConstraints.tight(Size.zero));
      parentData.offset = Offset.zero;
      size = constraints.constrain(Size.zero);
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    parentData.offset = Offset(_gapAfterMarks ? 0 : _gap, 0);
    size = constraints.constrain(_boxSize(child.size));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidden) {
      super.paint(context, offset);
    }
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_hidden) {
      super.visitChildrenForSemantics(visitor);
    }
  }
}
