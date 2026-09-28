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

/// 네이버 지도 1:1 표준 출구정보 섹션.
///
/// 미니 지도 타일(카카오맵 SDK 뷰 + 우측 상단 ⤢ 확대 버튼),
/// 가로 스크롤 출구 알약 탭 (Horizontal Pill Tabs),
/// 선택된 출구의 상세 정보(장소 정보 + 가까운 하차문)를 통합 제공한다.
class StationExitSection extends StatefulWidget {
  const StationExitSection({
    required this.station,
    required this.exits,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    this.locationProvider,
    this.mapPreviewBuilder,
    this.previousStation,
    this.nextStation,
    super.key,
  }) : assert(exits.length > 0);

  final StationDetail station;
  final List<StationExitInfo> exits;
  final KakaoMapLauncher mapLauncher;
  final CurrentLocationProvider? locationProvider;
  final StationExitMapPreviewBuilder? mapPreviewBuilder;
  final String? previousStation;
  final String? nextStation;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 180,
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
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: EasySubwayAccessibleColors.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    key: const Key('stationExitMapExpandButton'),
                    customBorder: const CircleBorder(),
                    onTap: () => _openSelectedExit(context),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
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
        SingleChildScrollView(
          key: const Key('stationExitPillTabs'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < widget.exits.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _ExitPillTab(
                  key: Key('stationExitPill-${widget.exits[i].id}'),
                  exit: widget.exits[i],
                  isSelected: i == _selectedIndex,
                  onTap: () => _select(i),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        StationExitCard(
          key: ValueKey(selectedExit.id),
          station: widget.station,
          exit: selectedExit,
          mapLauncher: widget.mapLauncher,
          locationProvider: widget.locationProvider,
          previousStation: widget.previousStation,
          nextStation: widget.nextStation,
        ),
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

class _ExitPillTab extends StatelessWidget {
  const _ExitPillTab({
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
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${exit.exitNumber}번 출구',
      child: Material(
        color: isSelected
            ? EasySubwayAccessibleColors.surface
            : EasySubwayAccessibleColors.surfaceScaffold,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSelected
              ? BorderSide(color: EasySubwayAccessibleColors.text, width: 1.5)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? EasySubwayAccessibleColors.amber
                        : EasySubwayAccessibleColors.line,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    exit.exitNumber,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w700,
                      color: isSelected
                          ? EasySubwayAccessibleColors.text
                          : EasySubwayAccessibleColors.mutedText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '번',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? EasySubwayAccessibleColors.text
                        : EasySubwayAccessibleColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
