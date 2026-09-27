import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
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

class StationExitSection extends StatefulWidget {
  const StationExitSection({
    required this.station,
    required this.exits,
    required this.mapLauncher,
    required this.locationProvider,
    this.mapPreviewBuilder,
    super.key,
  }) : assert(exits.length > 0);

  final StationDetail station;
  final List<StationExitInfo> exits;
  final KakaoMapLauncher mapLauncher;
  final CurrentLocationProvider? locationProvider;
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
          if (previewBuilder != null)
            previewBuilder(
              station: widget.station,
              exits: widget.exits,
              selectedExitId: selectedExit.id,
              onOpenSelected: () => _openSelectedExit(context),
            )
          else
            StationExitMapPreview(
              station: widget.station,
              exits: widget.exits,
              selectedExitId: selectedExit.id,
              onOpenSelected: () => _openSelectedExit(context),
            ),
          const SizedBox(height: 8),
        ],
        if (widget.exits.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.exits.length; i++)
                _ExitChip(
                  key: Key('stationExitChip-${widget.exits[i].id}'),
                  exit: widget.exits[i],
                  isSelected: i == _selectedIndex,
                  onTap: () => _select(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            _navigationButton(
              key: const Key('stationExitPreviousButton'),
              icon: Icons.chevron_left,
              semanticLabel: _selectedIndex == 0
                  ? '이전 출구 없음'
                  : '${widget.exits[_selectedIndex - 1].name} 보기',
              onPressed: _selectedIndex == 0
                  ? null
                  : () => _select(_selectedIndex - 1),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label:
                    '출구 선택, 전체 ${widget.exits.length}개 중 ${_selectedIndex + 1}번째',
                value: selectedExit.name,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('stationExitSelector'),
                      isExpanded: true,
                      value: selectedExit.id,
                      items: [
                        for (final exit in widget.exits)
                          DropdownMenuItem(
                            value: exit.id,
                            child: Text(exit.name),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) {
                          return;
                        }
                        _select(
                          widget.exits.indexWhere((exit) => exit.id == id),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _navigationButton(
              key: const Key('stationExitNextButton'),
              icon: Icons.chevron_right,
              semanticLabel: _selectedIndex == widget.exits.length - 1
                  ? '다음 출구 없음'
                  : '${widget.exits[_selectedIndex + 1].name} 보기',
              onPressed: _selectedIndex == widget.exits.length - 1
                  ? null
                  : () => _select(_selectedIndex + 1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StationExitCard(
          key: ValueKey(selectedExit.id),
          station: widget.station,
          exit: selectedExit,
          mapLauncher: widget.mapLauncher,
          locationProvider: widget.locationProvider,
        ),
      ],
    );
  }

  Widget _navigationButton({
    required Key key,
    required IconData icon,
    required String semanticLabel,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: IconButton(
          key: key,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
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

class _ExitChip extends StatelessWidget {
  const _ExitChip({
    required this.exit,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final StationExitInfo exit;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isElevator = exit.hasElevatorConnection;
    final match = RegExp(r'(\d+(?:-\d+)?)').firstMatch(exit.name);
    final exitNum = match != null ? match.group(1)! : '';

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${exit.name}${isElevator ? ', 엘리베이터 이용 가능' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40, minWidth: 54),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? EasySubwayAccessibleColors.interactionPrimary
                : EasySubwayAccessibleColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? EasySubwayAccessibleColors.interactionPrimary
                  : EasySubwayAccessibleColors.borderSubtle,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (exitNum.isNotEmpty) ...[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? EasySubwayColorPrimitives.neutralWhite.withValues(alpha: 0.25)
                        : EasySubwayAccessibleColors.surfaceBrandChrome,
                    border: Border.all(
                      color: isSelected
                          ? EasySubwayColorPrimitives.neutralWhite.withValues(alpha: 0.7)
                          : EasySubwayAccessibleColors.borderSubtle,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    exitNum,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? EasySubwayColorPrimitives.neutralWhite
                          : EasySubwayAccessibleColors.contentPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                exit.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isSelected
                      ? EasySubwayColorPrimitives.neutralWhite
                      : EasySubwayAccessibleColors.contentPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (isElevator) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? EasySubwayColorPrimitives.neutralWhite.withValues(alpha: 0.2)
                        : EasySubwayAccessibleColors.surfaceBrandChrome,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? EasySubwayColorPrimitives.neutralWhite.withValues(alpha: 0.8)
                          : EasySubwayAccessibleColors.mint,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.elevator,
                        size: 12,
                        color: isSelected
                            ? EasySubwayColorPrimitives.neutralWhite
                            : EasySubwayAccessibleColors.mint,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'EV',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? EasySubwayColorPrimitives.neutralWhite
                              : EasySubwayAccessibleColors.mint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

