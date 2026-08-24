import 'package:flutter/material.dart';

import '../../accessible_design.dart';
import '../../design_tokens.dart';

/// 기능별 선택지를 같은 접근성·선택 표시로 렌더링하는 중립 행.
class AccessibleSelectableOptionRow extends StatelessWidget {
  const AccessibleSelectableOptionRow({
    required this.controlKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.showDescription = false,
    this.showBrandRadio = false,
    this.radioKey,
    this.checkKey,
    super.key,
  });

  final Key controlKey;
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final bool showDescription;
  final bool showBrandRadio;
  final Key? radioKey;
  final Key? checkKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$title, $description',
      selected: selected,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: controlKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: selected
                        ? EasySubwayAccessibleColors.text
                        : EasySubwayAccessibleColors.mutedText,
                  ),
                  const SizedBox(width: EasySubwaySpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: textTheme.bodyLarge?.copyWith(
                            color: EasySubwayAccessibleColors.text,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 18,
                            height: 1.25,
                          ),
                        ),
                        if (showDescription) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: textTheme.bodyMedium?.copyWith(
                              color: EasySubwayAccessibleColors.mutedText,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: showBrandRadio
                        ? EasySubwaySpacing.xs
                        : EasySubwaySpacing.md,
                  ),
                  if (showBrandRadio)
                    Container(
                      key: radioKey,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? EasySubwayAccessibleColors.brandSignature
                                  .withValues(alpha: 0.12)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? EasySubwayAccessibleColors.brandSignature
                              : EasySubwayAccessibleColors.mutedText,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: selected
                          ? CustomPaint(
                              key: checkKey,
                              size: const Size.square(12),
                              painter: const _BrandCheckPainter(),
                            )
                          : null,
                    )
                  else if (selected)
                    const Icon(
                      Icons.check,
                      size: 22,
                      color: EasySubwayAccessibleColors.primary,
                    )
                  else
                    const SizedBox(width: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandCheckPainter extends CustomPainter {
  const _BrandCheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EasySubwayAccessibleColors.brandSignature
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.5)
      ..lineTo(size.width * 0.4, size.height * 0.8)
      ..lineTo(size.width * 0.9, size.height * 0.2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BrandCheckPainter oldDelegate) => false;
}
