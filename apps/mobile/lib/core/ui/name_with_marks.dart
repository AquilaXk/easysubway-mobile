import 'package:flutter/material.dart';

/// 이름 한 줄과 노선 마크 묶음을 한 줄에 놓는다. 이름이 우선이라 마크 묶음은 줄
/// 폭의 [maxMarksFraction]까지만 쓴다. 마크가 그보다 많으면 [marks]의 Wrap이
/// 다음 줄로 접히고, 이름은 나머지 폭을 모두 가진다.
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
        final budgetedMarks = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * maxMarksFraction,
          ),
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
