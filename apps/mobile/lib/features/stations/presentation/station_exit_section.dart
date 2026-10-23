import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../core/ui/line_mark.dart';
import '../domain/station_models.dart';
import 'station_exit_card.dart';
import 'station_exit_map_preview.dart';
import 'station_exit_map_target.dart';

typedef StationExitMapPreviewBuilder =
    Widget Function({
      required StationDetail station,
      required List<StationExitInfo> exits,
      required String selectedExitId,
      required VoidCallback onOpenSelected,
    });

/// 상용 지하철 서비스와 같은 출구정보 섹션.
///
/// 미니 지도(우측 상단 확대 버튼), 지도 아래 `◀ ① 번 출구 ▾ ▶` 선택기, 선택한
/// 출구의 정보(주변 시설 문장, 가까운 하차문)를 차례로 둔다.
class StationExitSection extends StatefulWidget {
  const StationExitSection({
    required this.station,
    required this.exits,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    this.mapPreviewBuilder,
    super.key,
  }) : assert(exits.length > 0);

  final StationDetail station;
  final List<StationExitInfo> exits;
  final KakaoMapLauncher mapLauncher;
  final StationExitMapPreviewBuilder? mapPreviewBuilder;

  @override
  State<StationExitSection> createState() => _StationExitSectionState();
}

class _StationExitSectionState extends State<StationExitSection> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant StationExitSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != widget.station.id ||
        !listEquals(
          oldWidget.exits.map((exit) => exit.id).toList(),
          widget.exits.map((exit) => exit.id).toList(),
        )) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedExit = widget.exits[_selectedIndex];
    final previewBuilder = widget.mapPreviewBuilder;
    final showPreview = canShowStationExitMapPreview(
      station: widget.station,
      exits: widget.exits,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPreview) ...[
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  // 지도 미리보기를 못 여는 안내 패널은 큰 글자에서 내용만큼 자라도록
                  // 높이를 고정하지 않고 최소 높이만 둔다.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: double.infinity,
                      minHeight: 180,
                    ),
                    child: Builder(
                      builder: (context) {
                        void openSelected() => _openSelectedExit(context);
                        return previewBuilder != null
                            ? previewBuilder(
                                station: widget.station,
                                exits: widget.exits,
                                selectedExitId: selectedExit.id,
                                onOpenSelected: openSelected,
                              )
                            : StationExitMapPreview(
                                station: widget.station,
                                exits: widget.exits,
                                selectedExitId: selectedExit.id,
                                onOpenSelected: openSelected,
                              );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: EasySubwayAccessibleColors.surface,
                  shape: const CircleBorder(
                    side: BorderSide(color: EasySubwayAccessibleColors.line),
                  ),
                  elevation: 1,
                  child: InkWell(
                    key: const Key('stationExitMapExpandButton'),
                    customBorder: const CircleBorder(),
                    onTap: () => _openSelectedExit(context),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.open_in_full,
                        size: 16,
                        color: EasySubwayAccessibleColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _ExitSelector(
          exits: widget.exits,
          selectedIndex: _selectedIndex,
          onSelect: _select,
        ),
        const SizedBox(height: EasySubwaySpacing.md),
        StationExitCard(key: ValueKey(selectedExit.id), exit: selectedExit),
      ],
    );
  }

  void _select(int index) {
    if (index < 0 || index >= widget.exits.length || index == _selectedIndex) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _openSelectedExit(BuildContext context) async {
    final mapTarget = stationExitMapTarget(
      station: widget.station,
      exit: widget.exits[_selectedIndex],
    );
    if (mapTarget == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.mapLauncher.openLook(mapTarget.target);
    if (!context.mounted) {
      return;
    }
    final message = switch (result) {
      KakaoMapLaunchResult.app || KakaoMapLaunchResult.web => '카카오맵을 열었습니다.',
      KakaoMapLaunchResult.copied => '좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.',
      KakaoMapLaunchResult.failed => '지도 앱을 열지 못했어요. 잠시 후 다시 시도해 주세요.',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 상용 지하철 서비스의 `◀ ① 번 출구 ▾ ▶` 선택기. 가운데를 누르면 출구 목록을
/// 열고, 양쪽 버튼은 이전·다음 출구로 옮긴다. 처음과 끝에서는 그쪽 버튼이 꺼진다.
class _ExitSelector extends StatelessWidget {
  const _ExitSelector({
    required this.exits,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<StationExitInfo> exits;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _shape = RoundedRectangleBorder(
    side: BorderSide(color: EasySubwayAccessibleColors.borderSubtle),
    borderRadius: BorderRadius.all(Radius.circular(EasySubwayRadius.control)),
  );

  @override
  Widget build(BuildContext context) {
    final exit = exits[selectedIndex];
    final hasPrevious = selectedIndex > 0;
    final hasNext = selectedIndex < exits.length - 1;
    return Material(
      key: const Key('stationExitSelector'),
      color: EasySubwayAccessibleColors.surfaceDefault,
      shape: _shape,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IconButton(
              tooltip: '이전 출구',
              onPressed: hasPrevious ? () => onSelect(selectedIndex - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            const VerticalDivider(
              width: 1,
              color: EasySubwayAccessibleColors.borderSubtle,
            ),
            Expanded(
              child: MenuAnchor(
                menuChildren: [
                  for (final (index, item) in exits.indexed)
                    MenuItemButton(
                      onPressed: () => onSelect(index),
                      child: Text(item.name),
                    ),
                ],
                builder: (context, controller, _) => Semantics(
                  container: true,
                  button: true,
                  label: '${exit.name}, 출구 목록 열기',
                  excludeSemantics: true,
                  onTap: controller.open,
                  child: InkWell(
                    key: const Key('stationExitSelectorCurrent'),
                    onTap: controller.open,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: EasySubwayTouchTarget.iconOnly,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        vertical: EasySubwaySpacing.sm,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: EasySubwaySpacing.xs,
                        children: [
                          _ExitNumberBadge(number: exit.exitNumber),
                          const Text('번 출구', style: _labelStyle),
                          const Icon(
                            Icons.arrow_drop_down,
                            color: EasySubwayAccessibleColors.secondaryText,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(
              width: 1,
              color: EasySubwayAccessibleColors.borderSubtle,
            ),
            IconButton(
              tooltip: '다음 출구',
              onPressed: hasNext ? () => onSelect(selectedIndex + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  static const _labelStyle = TextStyle(
    fontSize: 16,
    fontWeight: EasySubwayFontWeight.regular,
    color: EasySubwayAccessibleColors.text,
  );
}

/// 출구 번호 원. 지도 미리보기의 선택 출구 표시와 같은 색이다. 원 안 숫자는 노선
/// 마크처럼 정해진 배율까지만 키우고, 원 크기도 같은 배율로 맞춰 숫자가 원을
/// 벗어나지 않게 한다. 옆의 `번 출구`는 기기 배율을 그대로 따른다.
class _ExitNumberBadge extends StatelessWidget {
  const _ExitNumberBadge({required this.number});

  final String number;

  static const _diameter = 24.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: lineMarkFixedChromeMaxTextScale);
    return Container(
      width: scaler.scale(_diameter),
      height: scaler.scale(_diameter),
      decoration: const ShapeDecoration(
        color: EasySubwayAccessibleColors.primary,
        shape: CircleBorder(),
      ),
      alignment: Alignment.center,
      child: Text(
        number,
        maxLines: 1,
        textScaler: scaler,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: EasySubwayFontWeight.emphasis,
          color: EasySubwayAccessibleColors.onPrimary,
        ),
      ),
    );
  }
}
