import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/ui/line_mark.dart';
import '../../../design_tokens.dart';
import '../domain/route_map_line_choices.dart';

/// 노선 줄 칩 높이. 상용 지하철 서비스 노선도 캡처(2026-10-24)에서 칩은 약 24pt다.
const _chipMarkSize = 24.0;

/// 고른 칩을 감싸는 같은 노선색의 옅은 테두리 두께와 불투명도(캡처 실측).
const _selectedHaloWidth = 4.0;
const _selectedHaloAlpha = 0.3;

/// 노선 선택 시트를 여는 원형 단추의 보이는 지름. 누르는 영역은 48dp다.
const _sheetButtonVisualSize = 28.0;

const _revealDuration = Duration(milliseconds: 200);

/// 시트 격자의 가장 큰 열 수. 이름이 한 줄에 안 들어가면 2열, 1열로 줄인다.
const _maxSheetColumns = 3;
const _sheetTitleFontSize = 18.0;
const _sheetCellFontSize = 16.0;

/// 노선도 상단바 아래 가로로 넘기는 노선 칩 줄. 칩은 노선색 알약 위 흰 이름이고,
/// 고른 칩은 같은 노선색의 옅은 테두리를 두른다. 오른쪽 원형 단추가 노선 선택 시트를
/// 연다.
///
/// 칩 바탕은 노선색을 [lineInkOnWhite]로 어둡게 한 색이다. 노선색 그대로는 9호선·
/// 경의중앙·우이신설처럼 밝은 노선에서 흰 이름과의 대비가 4.5:1에 못 미친다.
class RouteMapLineStrip extends StatefulWidget {
  const RouteMapLineStrip({
    required this.choices,
    required this.selectedLineId,
    required this.onSelected,
    required this.onOpenSheet,
    super.key,
  });

  final List<RouteMapLineChoice> choices;
  final String? selectedLineId;
  final ValueChanged<String> onSelected;
  final VoidCallback onOpenSheet;

  @override
  State<RouteMapLineStrip> createState() => _RouteMapLineStripState();
}

class _RouteMapLineStripState extends State<RouteMapLineStrip> {
  final _chipKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _revealSelectedChip();
  }

  @override
  void didUpdateWidget(RouteMapLineStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedLineId != widget.selectedLineId) {
      _revealSelectedChip();
    }
  }

  /// 시트에서 고른 노선 칩이 줄 밖에 있으면 줄 가운데로 넘겨 보인다.
  void _revealSelectedChip() {
    final lineId = widget.selectedLineId;
    if (lineId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[lineId]?.currentContext;
      if (!mounted || chipContext == null) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          chipContext,
          alignment: 0.5,
          duration: _revealDuration,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('routeMapLineStrip'),
      color: EasySubwayAccessibleColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EasySubwaySpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: EasySubwaySpacing.md,
                    ),
                    child: Row(
                      children: [
                        for (final choice in widget.choices)
                          KeyedSubtree(
                            key: _chipKeys.putIfAbsent(
                              choice.lineId,
                              GlobalKey.new,
                            ),
                            child: _LineChip(
                              choice: choice,
                              selected: choice.lineId == widget.selectedLineId,
                              onTap: () => widget.onSelected(choice.lineId),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _SheetButton(onPressed: widget.onOpenSheet),
                const SizedBox(width: EasySubwaySpacing.sm),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: EasySubwayAccessibleColors.line,
          ),
        ],
      ),
    );
  }
}

class _LineChip extends StatelessWidget {
  const _LineChip({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final RouteMapLineChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final markSize = scaledLineMarkSize(
      context,
      _chipMarkSize,
      maxTextScale: lineMarkFixedChromeMaxTextScale,
    );
    return Semantics(
      key: Key('routeMapLineChip-${choice.lineId}'),
      container: true,
      button: true,
      selected: selected,
      label: choice.name,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: EasySubwayTouchTarget.iconOnly,
            minHeight: EasySubwayTouchTarget.iconOnly,
          ),
          child: Center(
            widthFactor: 1,
            child: ExcludeSemantics(
              child: Material(
                color: selected
                    ? choice.color.withValues(alpha: _selectedHaloAlpha)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(markSize / 2 + _selectedHaloWidth),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(_selectedHaloWidth),
                  child: LineMark(
                    label: choice.name,
                    color: lineInkOnWhite(choice.color),
                    size: _chipMarkSize,
                    maxTextScale: lineMarkFixedChromeMaxTextScale,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('routeMapLineSheetButton'),
      tooltip: '노선 선택',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        shape: const CircleBorder(
          side: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
        minimumSize: const Size.square(_sheetButtonVisualSize),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: EasySubwayAccessibleColors.secondaryText,
      ),
    );
  }
}

/// 상용 지하철 서비스의 `노선 선택` 시트. 맨 위 `전체 노선` 줄과 3열 노선 격자다.
/// 칸을 누르면 시트를 닫고 [onSelected]에 그 노선 id를, `전체 노선`은 null을 넘긴다.
/// 닫기는 아무것도 넘기지 않는다.
Future<void> showRouteMapLineSheet(
  BuildContext context, {
  required List<RouteMapLineChoice> choices,
  required String? selectedLineId,
  required ValueChanged<String?> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: EasySubwayAccessibleColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(EasySubwayRadius.sheet),
      ),
    ),
    builder: (sheetContext) => _RouteMapLineSheet(
      choices: choices,
      selectedLineId: selectedLineId,
      onSelected: (lineId) {
        Navigator.of(sheetContext).pop();
        onSelected(lineId);
      },
    ),
  );
}

class _RouteMapLineSheet extends StatelessWidget {
  const _RouteMapLineSheet({
    required this.choices,
    required this.selectedLineId,
    required this.onSelected,
  });

  final List<RouteMapLineChoice> choices;
  final String? selectedLineId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        key: const Key('routeMapLineSheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHeader(),
          const Divider(
            height: 1,
            thickness: 1,
            color: EasySubwayAccessibleColors.line,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(EasySubwaySpacing.lg),
              child: _LineTable(
                choices: choices,
                selectedLineId: selectedLineId,
                onSelected: onSelected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EasySubwaySpacing.xxl + EasySubwaySpacing.lg,
        EasySubwaySpacing.sm,
        EasySubwaySpacing.sm,
        EasySubwaySpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: const Text(
                '노선 선택',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _sheetTitleFontSize,
                  fontWeight: EasySubwayFontWeight.emphasis,
                  color: EasySubwayAccessibleColors.text,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close,
              color: EasySubwayAccessibleColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// 얇은 선으로 칸을 나눈 표. 열 수는 글자 배율에서도 가장 긴 이름이 한 줄에 들어가는
/// 가장 큰 값(3, 2, 1)이다. 노선 수가 열 수의 배수가 아니면 마지막 줄 남는 칸은 비운다.
class _LineTable extends StatelessWidget {
  const _LineTable({
    required this.choices,
    required this.selectedLineId,
    required this.onSelected,
  });

  final List<RouteMapLineChoice> choices;
  final String? selectedLineId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    const hairline = BorderSide(color: EasySubwayAccessibleColors.line);
    return Material(
      color: EasySubwayAccessibleColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        side: hairline,
        borderRadius: BorderRadius.all(Radius.circular(EasySubwayRadius.card)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetCell(
            key: const Key('routeMapLineSheetAll'),
            label: '전체 노선',
            selected: selectedLineId == null,
            centered: true,
            onTap: () => onSelected(null),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: EasySubwayAccessibleColors.line,
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _sheetColumnCount(
                context,
                choices,
                constraints.maxWidth,
              );
              return Table(
                border: const TableBorder.symmetric(inside: hairline),
                defaultVerticalAlignment:
                    TableCellVerticalAlignment.intrinsicHeight,
                children: [
                  for (var start = 0; start < choices.length; start += columns)
                    TableRow(
                      children: [
                        for (var column = 0; column < columns; column++)
                          start + column < choices.length
                              ? _lineCell(choices[start + column])
                              : const SizedBox.shrink(),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _lineCell(RouteMapLineChoice choice) => _SheetCell(
    key: Key('routeMapLineSheetCell-${choice.lineId}'),
    label: choice.name,
    selected: choice.lineId == selectedLineId,
    leading: LineMark(label: choice.markLabel, color: choice.color),
    onTap: () => onSelected(choice.lineId),
  );
}

TextStyle _cellTextStyle({required bool selected}) => TextStyle(
  fontSize: _sheetCellFontSize,
  fontWeight: selected
      ? EasySubwayFontWeight.emphasis
      : EasySubwayFontWeight.regular,
  color: selected
      ? EasySubwayAccessibleColors.text
      : EasySubwayAccessibleColors.secondaryText,
);

/// 가장 긴 이름이 사용자의 글자 배율 그대로 한 줄에 들어가는 가장 큰 열 수. 1열에서도
/// 모자라면 1열이고, 그때 이름은 칸 안에서 줄을 바꾼다. 칸 폭은 [tableWidth]를 열 수로
/// 나눈 값이고, 이름이 쓰는 폭은 칸 가로 여백, 노선 마크, 마크와 이름 사이 간격을 뺀 나머지다.
/// 고른 칸은 굵어 더 넓으므로 굵은 글씨로 재서 고른 노선이 바뀌어도 열 수가 그대로다.
int _sheetColumnCount(
  BuildContext context,
  List<RouteMapLineChoice> choices,
  double tableWidth,
) {
  final style = DefaultTextStyle.of(
    context,
  ).style.merge(_cellTextStyle(selected: true));
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var longestName = 0.0;
  for (final choice in choices) {
    final painter = TextPainter(
      text: TextSpan(text: choice.name, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    longestName = math.max(longestName, painter.width);
    painter.dispose();
  }
  final chrome =
      2 * EasySubwaySpacing.md +
      scaledLineMarkSize(context, lineMarkDefaultSize) +
      EasySubwaySpacing.sm;
  for (var columns = _maxSheetColumns; columns > 1; columns--) {
    if (tableWidth / columns - chrome >= longestName) {
      return columns;
    }
  }
  return 1;
}

class _SheetCell extends StatelessWidget {
  const _SheetCell({
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.centered = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ExcludeSemantics(
          child: ColoredBox(
            color: selected
                ? EasySubwayAccessibleColors.surfaceSubtle
                : EasySubwayAccessibleColors.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: EasySubwayTouchTarget.iconOnly,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: EasySubwaySpacing.md,
                  vertical: EasySubwaySpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: centered
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (leading != null) ...[
                      leading,
                      const SizedBox(width: EasySubwaySpacing.sm),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: _cellTextStyle(selected: selected),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
