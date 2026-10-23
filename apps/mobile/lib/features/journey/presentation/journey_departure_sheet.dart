import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import 'journey_departure_choice.dart';

/// 상용 지하철 서비스의 `출발 시각 설정` 시트. 모드 칩은 서버가 받는 출발 시각과
/// 막차만 두고, 휠은 날짜·오전오후·시·분이다. 막차는 운행일 하나만 보내므로
/// 날짜 휠만 남긴다. 닫으면 null, `지금 출발`은 [JourneyDepartNow]를 돌려준다.
Future<JourneyDepartureChoice?> showJourneyDepartureSheet(
  BuildContext context, {
  required JourneyDepartureChoice initial,
  required DateTime now,
}) {
  return showModalBottomSheet<JourneyDepartureChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: EasySubwayAccessibleColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(EasySubwayRadius.sheet),
      ),
    ),
    builder: (_) => _JourneyDepartureSheet(initial: initial, now: now),
  );
}

enum _SheetMode { departAt, lastTrain }

/// 날짜 휠의 범위. 어제(새벽에는 아직 전날 운행일이다)부터 엿새 뒤까지.
const _firstDayOffset = -1;
const _dayCount = 8;
const _minutesPerHour = 60;
const _hoursPerHalfDay = 12;

/// 휠이 한 번에 보이는 칸 수. 가운데 칸이 고른 값이다.
const _visibleWheelItems = 5;

class _JourneyDepartureSheet extends StatefulWidget {
  const _JourneyDepartureSheet({required this.initial, required this.now});

  final JourneyDepartureChoice initial;
  final DateTime now;

  @override
  State<_JourneyDepartureSheet> createState() => _JourneyDepartureSheetState();
}

class _JourneyDepartureSheetState extends State<_JourneyDepartureSheet> {
  late final DateTime _today = DateTime.utc(
    _nowWall.year,
    _nowWall.month,
    _nowWall.day,
  );
  late final DateTime _nowWall = journeySeoulWallTime(widget.now);
  late _SheetMode _mode;
  late int _dayIndex;
  late int _halfDay;
  late int _hourIndex;
  late int _minute;
  late final FixedExtentScrollController _dayWheel;
  late final FixedExtentScrollController _halfDayWheel;
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _minuteWheel;

  @override
  void initState() {
    super.initState();
    final (mode, wall) = switch (widget.initial) {
      JourneyDepartNow() => (_SheetMode.departAt, _nowWall),
      JourneyDepartAt(:final requestedAt) => (
        _SheetMode.departAt,
        journeySeoulWallTime(requestedAt),
      ),
      JourneyLastTrain(:final serviceDay) => (
        _SheetMode.lastTrain,
        DateTime.utc(
          serviceDay.year,
          serviceDay.month,
          serviceDay.day,
          _nowWall.hour,
          _nowWall.minute,
        ),
      ),
    };
    _mode = mode;
    _setFromWall(wall);
    _dayWheel = FixedExtentScrollController(initialItem: _dayIndex);
    _halfDayWheel = FixedExtentScrollController(initialItem: _halfDay);
    _hourWheel = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteWheel = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _dayWheel.dispose();
    _halfDayWheel.dispose();
    _hourWheel.dispose();
    _minuteWheel.dispose();
    super.dispose();
  }

  int _indexOfDay(DateTime day) =>
      (DateTime.utc(day.year, day.month, day.day).difference(_today).inDays -
              _firstDayOffset)
          .clamp(0, _dayCount - 1);

  void _setFromWall(DateTime wall) {
    _dayIndex = _indexOfDay(wall);
    _halfDay = wall.hour ~/ _hoursPerHalfDay;
    _hourIndex = (wall.hour + _hoursPerHalfDay - 1) % _hoursPerHalfDay;
    _minute = wall.minute;
  }

  DateTime _day(int index) =>
      _today.add(Duration(days: index + _firstDayOffset));

  void _selectMode(_SheetMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode == _SheetMode.lastTrain) {
        _dayIndex = _indexOfDay(journeyCurrentServiceDay(widget.now));
        _dayWheel.jumpToItem(_dayIndex);
      }
    });
    if (mode == _SheetMode.departAt) {
      // 다시 붙는 휠은 처음 위치에서 시작하므로 고른 값으로 되돌린다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _halfDayWheel.jumpToItem(_halfDay);
        _hourWheel.jumpToItem(_hourIndex);
        _minuteWheel.jumpToItem(_minute);
      });
    }
  }

  JourneyDepartureChoice _confirmedChoice() {
    final day = _day(_dayIndex);
    if (_mode == _SheetMode.lastTrain) return JourneyLastTrain(day);
    final hour =
        (_hourIndex + 1) % _hoursPerHalfDay + _halfDay * _hoursPerHalfDay;
    return JourneyDepartAt(
      journeyInstantFromSeoul(
        DateTime.utc(day.year, day.month, day.day, hour, _minute),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemExtent = MediaQuery.textScalerOf(context).scale(40);
    return SafeArea(
      child: Column(
        key: const Key('journey-departure-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EasySubwaySpacing.lg,
              vertical: EasySubwaySpacing.md,
            ),
            child: Wrap(
              spacing: EasySubwaySpacing.sm,
              runSpacing: EasySubwaySpacing.sm,
              children: [
                _modeChip(_SheetMode.departAt, '출발 시각'),
                _modeChip(_SheetMode.lastTrain, '막차'),
              ],
            ),
          ),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
          SizedBox(
            height: itemExtent * _visibleWheelItems,
            child: Stack(
              children: [
                // 고른 값 줄의 회색 띠. 상용 지하철 서비스처럼 모든 열을 가로지른다.
                Positioned(
                  left: EasySubwaySpacing.lg,
                  right: EasySubwaySpacing.lg,
                  top: itemExtent * (_visibleWheelItems ~/ 2),
                  height: itemExtent,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: EasySubwayAccessibleColors.surfaceSubtle,
                      borderRadius: BorderRadius.all(
                        Radius.circular(EasySubwayRadius.card),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: EasySubwaySpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _wheel(
                          key: 'journey-departure-sheet-date',
                          controller: _dayWheel,
                          semanticsLabel: '날짜',
                          itemExtent: itemExtent,
                          selected: _dayIndex,
                          labels: [
                            for (var index = 0; index < _dayCount; index++)
                              journeyDayLabel(_day(index), _today),
                          ],
                          onChanged: (index) => _dayIndex = index,
                        ),
                      ),
                      if (_mode == _SheetMode.departAt) ...[
                        Expanded(
                          child: _wheel(
                            key: 'journey-departure-sheet-ampm',
                            controller: _halfDayWheel,
                            semanticsLabel: '오전 오후',
                            itemExtent: itemExtent,
                            selected: _halfDay,
                            labels: const ['오전', '오후'],
                            onChanged: (index) => _halfDay = index,
                          ),
                        ),
                        Expanded(
                          child: _wheel(
                            key: 'journey-departure-sheet-hour',
                            controller: _hourWheel,
                            semanticsLabel: '시',
                            itemExtent: itemExtent,
                            selected: _hourIndex,
                            labels: [
                              for (
                                var hour = 1;
                                hour <= _hoursPerHalfDay;
                                hour++
                              )
                                '$hour',
                            ],
                            onChanged: (index) => _hourIndex = index,
                          ),
                        ),
                        const ExcludeSemantics(
                          child: Text(':', style: _wheelStyle),
                        ),
                        Expanded(
                          child: _wheel(
                            key: 'journey-departure-sheet-minute',
                            controller: _minuteWheel,
                            semanticsLabel: '분',
                            itemExtent: itemExtent,
                            selected: _minute,
                            labels: [
                              for (
                                var minute = 0;
                                minute < _minutesPerHour;
                                minute++
                              )
                                minute.toString().padLeft(2, '0'),
                            ],
                            onChanged: (index) => _minute = index,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(EasySubwaySpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: _sheetButton(
                    key: 'journey-departure-sheet-now',
                    label: '지금 출발',
                    background: EasySubwayAccessibleColors.contentMuted,
                    onPressed: () =>
                        Navigator.of(context).pop(const JourneyDepartNow()),
                  ),
                ),
                const SizedBox(width: EasySubwaySpacing.md),
                Expanded(
                  child: _sheetButton(
                    key: 'journey-departure-sheet-confirm',
                    label: '확인',
                    background: EasySubwayAccessibleColors.primary,
                    onPressed: () =>
                        Navigator.of(context).pop(_confirmedChoice()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
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
                '출발 시각 설정',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
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

  Widget _modeChip(_SheetMode mode, String label) {
    final selected = _mode == mode;
    return ChoiceChip(
      key: Key('journey-departure-sheet-mode-${mode.name}'),
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => _selectMode(mode),
      backgroundColor: EasySubwayAccessibleColors.surface,
      selectedColor: EasySubwayAccessibleColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EasySubwayRadius.card),
        side: BorderSide(
          color: selected
              ? EasySubwayAccessibleColors.primary
              : EasySubwayAccessibleColors.line,
          width: selected ? 1.5 : 1,
        ),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: selected
              ? EasySubwayFontWeight.emphasis
              : EasySubwayFontWeight.regular,
          color: selected
              ? EasySubwayAccessibleColors.primary
              : EasySubwayAccessibleColors.secondaryText,
        ),
      ),
    );
  }

  static const _wheelStyle = TextStyle(
    fontSize: 20,
    color: EasySubwayAccessibleColors.text,
  );

  Widget _wheel({
    required String key,
    required FixedExtentScrollController controller,
    required String semanticsLabel,
    required double itemExtent,
    required int selected,
    required List<String> labels,
    required ValueChanged<int> onChanged,
  }) {
    return _Wheel(
      key: Key(key),
      controller: controller,
      semanticsLabel: semanticsLabel,
      itemExtent: itemExtent,
      selected: selected,
      labels: labels,
      onChanged: (index) => setState(() => onChanged(index)),
    );
  }

  Widget _sheetButton({
    required String key,
    required String label,
    required Color background,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      key: Key(key),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
        backgroundColor: background,
        foregroundColor: EasySubwayAccessibleColors.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EasySubwayRadius.card),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: EasySubwayFontWeight.emphasis,
        ),
      ),
    );
  }
}

/// 날짜·시·분 휠 한 열. 휠 모양(지름 비율 1.07, 눌림 1.45, 한 칸씩 멈춤)과 스크린리더
/// 조정 동작(현재 값을 읽고 올리기·내리기로 한 칸씩 옮긴다)은 Flutter SDK
/// `packages/flutter/lib/src/cupertino/picker.dart`(BSD-3)의 `CupertinoPicker`·
/// `_RenderCupertinoPickerSemantics`를 따른다. 다른 점은 가운데 밖 값의 불투명도다.
/// `CupertinoPicker`는 0.447로 고정해 글자 대비가 4.5:1에 못 미치므로, 불투명도는
/// 1로 두고 가운데 밖 값을 보조 글자색(흰 바탕 6.2:1)으로 그린다.
class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.controller,
    required this.semanticsLabel,
    required this.itemExtent,
    required this.selected,
    required this.labels,
    required this.onChanged,
    super.key,
  });

  final FixedExtentScrollController controller;
  final String semanticsLabel;
  final double itemExtent;
  final int selected;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  static const _diameterRatio = 1.07;
  static const _squeeze = 1.45;

  void _jumpTo(int index) => controller.jumpToItem(index);

  @override
  Widget build(BuildContext context) {
    final hasNext = selected + 1 < labels.length;
    final hasPrevious = selected > 0;
    return Semantics(
      container: true,
      label: semanticsLabel,
      value: labels[selected],
      increasedValue: hasNext ? labels[selected + 1] : null,
      decreasedValue: hasPrevious ? labels[selected - 1] : null,
      onIncrease: hasNext ? () => _jumpTo(selected + 1) : null,
      onDecrease: hasPrevious ? () => _jumpTo(selected - 1) : null,
      child: ExcludeSemantics(
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          physics: const FixedExtentScrollPhysics(),
          diameterRatio: _diameterRatio,
          squeeze: _squeeze,
          itemExtent: itemExtent,
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildListDelegate(
            children: [
              for (var index = 0; index < labels.length; index++)
                Center(
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: index == selected
                          ? EasySubwayFontWeight.emphasis
                          : EasySubwayFontWeight.regular,
                      color: index == selected
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.mutedText,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
