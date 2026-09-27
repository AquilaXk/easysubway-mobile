import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../accessible_design.dart';
import '../../../adaptive_layout.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../mobile_error_reporter.dart';
import '../../facility_report/domain/facility_report_target.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/domain/route_draft.dart';
import '../data/server_station_timetable_repository.dart';
import '../application/station_detail_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'station_detail_route_actions.dart';
import 'station_exit_section.dart';
import 'station_facility_card.dart';
import 'station_facility_status_summary.dart';
import 'station_info_basis_disclosure.dart';
import 'station_layout_summary.dart';
import 'station_line_badges.dart';
import 'station_realtime_summary.dart';
import 'station_timetable_screen.dart';

const _stationDetailPagePadding = EdgeInsets.fromLTRB(20, 12, 20, 32);
const _stationDetailLargePagePadding = EdgeInsets.fromLTRB(24, 16, 24, 40);

/// 이전·다음 역 맥락(노선도 확장·시트 상단 chrome용).
class StationDetailNeighbor {
  const StationDetailNeighbor({required this.stationId, required this.nameKo});

  final String stationId;
  final String nameKo;

  String get displayName => nameKo.endsWith('역') ? nameKo : '$nameKo역';
}

/// 역 상세 공통 본문. 검색·즐겨찾기 시트와 노선도 확장(PR-B)이 공유한다.
///
/// IA(#2436): 맥락 → 지금 열차 → 이용하기 → 출구 → 시설 → 주소·연락처(있을 때)
/// → 안내·출처 → 광고. 카카오버스류 배너는 넣지 않는다.
class StationDetailBody extends StatelessWidget {
  const StationDetailBody({
    required this.state,
    required this.onRetryRealtime,
    required this.onOpenFacilityReport,
    this.favoriteController,
    this.bottomAdBuilder,
    this.routeDraftController,
    this.locationProvider,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    this.timetableRepository,
    this.showContextChrome = false,
    this.showRealtimeSection = true,
    this.onClose,
    this.previousStation,
    this.nextStation,
    this.onSelectNeighbor,
    this.lineForChrome,
    super.key,
  });

  final StationDetailState state;
  final VoidCallback onRetryRealtime;
  final Future<void> Function(FacilityReportTarget target) onOpenFacilityReport;
  final StationFavoriteToggleController? favoriteController;
  final WidgetBuilder? bottomAdBuilder;
  final RouteDraftPort? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final StationTimetableRepository? timetableRepository;
  final bool showContextChrome;

  /// false면 「지금 열차」블록을 생략한다. 노선도 확장처럼 상단에
  /// 실시간/시간표 패널을 이미 붙인 셸에서 중복·실패 카드 교체를 막는다.
  final bool showRealtimeSection;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchLine? lineForChrome;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationDetailStatus.loading => Semantics(
        label: '역 안내 불러오는 중',
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      StationDetailStatus.failure => Padding(
        padding: const EdgeInsets.all(20),
        child: _StationDetailMessage(message: state.message, liveRegion: true),
      ),
      StationDetailStatus.success => _StationDetailContent(
        detail: state.detail!,
        exits: state.exits,
        facilities: state.prioritizedFacilities,
        facilityAttentionSummary: state.facilityAttentionSummary,
        facilityAttentionSemanticLabel: state.facilityAttentionSemanticLabel,
        layoutSummaryItems: state.layoutSummaryItems,
        layoutSummarySemanticLabel: state.layoutSummarySemanticLabel,
        realtimeSnapshot: state.realtimeSnapshot,
        onRetryRealtime: onRetryRealtime,
        onOpenFacilityReport: onOpenFacilityReport,
        favoriteController: favoriteController,
        bottomAdBuilder: bottomAdBuilder,
        routeDraftController: routeDraftController,
        locationProvider: locationProvider,
        mapLauncher: mapLauncher,
        timetableRepository: timetableRepository,
        showContextChrome: showContextChrome,
        showRealtimeSection: showRealtimeSection,
        onClose: onClose,
        previousStation: previousStation,
        nextStation: nextStation,
        onSelectNeighbor: onSelectNeighbor,
        lineForChrome: lineForChrome,
      ),
    };
  }
}

class _StationDetailMessage extends StatelessWidget {
  const _StationDetailMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: EasySubwayAccessibleColors.secondaryText,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StationDetailContent extends StatelessWidget {
  const _StationDetailContent({
    required this.detail,
    required this.exits,
    required this.facilities,
    required this.facilityAttentionSummary,
    required this.facilityAttentionSemanticLabel,
    required this.layoutSummaryItems,
    required this.layoutSummarySemanticLabel,
    required this.realtimeSnapshot,
    required this.onRetryRealtime,
    required this.onOpenFacilityReport,
    required this.favoriteController,
    required this.bottomAdBuilder,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.timetableRepository,
    required this.showContextChrome,
    required this.showRealtimeSection,
    required this.onClose,
    required this.previousStation,
    required this.nextStation,
    required this.onSelectNeighbor,
    required this.lineForChrome,
  });

  final StationDetail detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String facilityAttentionSummary;
  final String facilityAttentionSemanticLabel;
  final List<StationLayoutSummaryItem> layoutSummaryItems;
  final String layoutSummarySemanticLabel;
  final RealtimeSnapshot realtimeSnapshot;
  final VoidCallback onRetryRealtime;
  final Future<void> Function(FacilityReportTarget target) onOpenFacilityReport;
  final StationFavoriteToggleController? favoriteController;
  final WidgetBuilder? bottomAdBuilder;
  final RouteDraftPort? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final StationTimetableRepository? timetableRepository;
  final bool showContextChrome;
  final bool showRealtimeSection;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchLine? lineForChrome;

  @override
  Widget build(BuildContext context) {
    // 카카오식 IA(#2436): 지금 열차 → 이용하기 → 출구 → 시설 → 안내·출처 → 광고.
    final primaryChildren = <Widget>[
      if (showContextChrome) ...[
        _StationDetailContextChrome(
          detail: detail,
          line: lineForChrome ?? _primaryStationLine(detail),
          onClose: onClose,
          previousStation: previousStation,
          nextStation: nextStation,
          onSelectNeighbor: onSelectNeighbor,
        ),
        const SizedBox(height: 16),
      ],
      if (showRealtimeSection) ...[
        const _StationDetailSectionTitle(title: '지금 열차'),
        const SizedBox(height: 12),
        StationRealtimeSummary(
          snapshot: realtimeSnapshot,
          onRetry: onRetryRealtime,
          previousStation: previousStation?.nameKo,
          nextStation: nextStation?.nameKo,
        ),
        const SizedBox(height: 20),
      ],
      const _StationDetailSectionTitle(title: '이용하기'),
      const SizedBox(height: 12),
      StationDetailRouteActions(
        detail: detail,
        routeDraftController: routeDraftController,
        favoriteController: favoriteController,
      ),
      const SizedBox(height: 12),
      _StationTimetableEntry(
        detail: detail,
        repository: timetableRepository,
        previousStation: previousStation?.nameKo,
        nextStation: nextStation?.nameKo,
      ),
    ];

    final hasExits = exits.isNotEmpty;
    final hasFacilities =
        facilities.isNotEmpty || facilityAttentionSummary.isNotEmpty;

    final detailChildren = <Widget>[
      if (hasExits) ...[
        const _StationDetailSectionTitle(title: '출구 정보'),
        const SizedBox(height: 8),
        StationExitSection(
          key: ValueKey('stationExitSection-${detail.id}'),
          station: detail,
          exits: exits,
          mapLauncher: mapLauncher,
          locationProvider: locationProvider,
        ),
        const SizedBox(height: 12),
      ],
      if (hasFacilities) ...[
        const _StationDetailSectionTitle(title: '시설 정보'),
        const SizedBox(height: 8),
        if (facilities.length >= 2 || exits.isNotEmpty) ...[
          _StationBarrierFreeRouteCard(
            station: detail,
            exits: exits,
            facilities: facilities,
          ),
          const SizedBox(height: 12),
        ],
        if (facilities.length >= 2) ...[
          _StationFacilityMatrixCard(station: detail, facilities: facilities),
          const SizedBox(height: 12),
        ],
        if (facilityAttentionSummary.isNotEmpty) ...[
          StationFacilityStatusSummary(
            text: facilityAttentionSummary,
            semanticLabel: facilityAttentionSemanticLabel,
          ),
          const SizedBox(height: 12),
        ],
        for (final facility in facilities)
          StationFacilityCard(
            facility: facility,
            station: detail,
            onReportTap: () => _openFacilityReport(facility),
          ),
        if (facilities.length >= 2 || exits.isNotEmpty) ...[
          const _StationDetailSectionTitle(title: '고객안전실, 역무실'),
          const SizedBox(height: 8),
          _StationSafetyOfficeCard(detail: detail, facilities: facilities),
          const SizedBox(height: 12),
        ],
      ],
      const _StationDetailSectionTitle(title: '안내'),
      const SizedBox(height: 12),
      if (detail.nameSub.isNotEmpty) ...[
        Text(
          detail.nameSub,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: EasySubwayAccessibleColors.secondaryText,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        '마지막 확인',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        stationVerifiedRelativeLabel(detail.lastVerifiedAt),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      if (layoutSummaryItems.isNotEmpty) ...[
        const SizedBox(height: 16),
        const _StationDetailSectionTitle(title: '역 안 이동'),
        const SizedBox(height: 12),
        if (layoutSummaryItems.isNotEmpty) ...[
          StationLayoutSummary(
            items: layoutSummaryItems,
            semanticLabel: layoutSummarySemanticLabel,
          ),
        ],
      ],
      const SizedBox(height: 16),
      StationInfoBasisDisclosure(
        labels: [
          detail.dataSourceLabel,
          '마지막 확인 ${stationVerifiedRelativeLabel(detail.lastVerifiedAt)}',
        ],
      ),
      if (bottomAdBuilder case final builder?) ...[
        const SizedBox(height: 24),
        builder(context),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
          constraints,
          textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        );
        return ListView(
          key: const Key('stationDetailList'),
          padding: isLargeScreen
              ? _stationDetailLargePagePadding
              : _stationDetailPagePadding,
          children: isLargeScreen
              ? [
                  _StationDetailAdaptiveContent(
                    primaryChildren: primaryChildren,
                    detailChildren: detailChildren,
                  ),
                ]
              : [
                  ...primaryChildren,
                  const SizedBox(height: 24),
                  ...detailChildren,
                ],
        );
      },
    );
  }

  void _openFacilityReport(StationFacilityInfo facility) {
    unawaited(
      onOpenFacilityReport(
        FacilityReportTarget(
          stationId: detail.id,
          stationName: detail.nameKo,
          facilityId: facility.id,
          facilityName: facility.displayName,
          facilityTypeLabel: facility.typeLabel,
          facilityStatusLabel: facility.statusLabel,
        ),
      ),
    );
  }
}

StationSearchLine? _primaryStationLine(StationDetail detail) {
  if (detail.lines.isEmpty) {
    return null;
  }
  return detail.lines.first;
}

class _StationDetailContextChrome extends StatelessWidget {
  const _StationDetailContextChrome({
    required this.detail,
    required this.line,
    required this.onClose,
    required this.previousStation,
    required this.nextStation,
    required this.onSelectNeighbor,
  });

  final StationDetail detail;
  final StationSearchLine? line;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    final hasNeighbors = previousStation != null || nextStation != null;
    return Column(
      key: const Key('stationDetailContextChrome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (line != null) ...[
              StationLineBadge(line: line!, size: 28),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                '${detail.nameKo}역',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                key: const Key('stationDetailChromeCloseButton'),
                tooltip: '닫기',
                onPressed: onClose,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.close,
                  size: 26,
                  color: EasySubwayAccessibleColors.contentPrimary,
                ),
              ),
          ],
        ),
        if (hasNeighbors) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NeighborStationButton(
                  key: const Key('stationDetailPreviousStation'),
                  neighbor: previousStation,
                  alignment: Alignment.centerLeft,
                  onSelectNeighbor: onSelectNeighbor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${detail.nameKo}역',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    // #1915: 섹션/컨텍스트 헤더는 w800 금지. 화면 타이틀 전용 ratchet.
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              Expanded(
                child: _NeighborStationButton(
                  key: const Key('stationDetailNextStation'),
                  neighbor: nextStation,
                  alignment: Alignment.centerRight,
                  onSelectNeighbor: onSelectNeighbor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NeighborStationButton extends StatelessWidget {
  const _NeighborStationButton({
    required this.neighbor,
    required this.alignment,
    required this.onSelectNeighbor,
    super.key,
  });

  final StationDetailNeighbor? neighbor;
  final Alignment alignment;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    final value = neighbor;
    if (value == null) {
      return const SizedBox.shrink();
    }
    final enabled = onSelectNeighbor != null;
    return Align(
      alignment: alignment,
      child: TextButton(
        onPressed: enabled ? () => onSelectNeighbor!(value) : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, EasySubwayTouchTarget.general),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: EasySubwayAccessibleColors.secondaryText,
        ),
        child: Text(
          alignment == Alignment.centerRight
              ? '${value.displayName} >'
              : '< ${value.displayName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment == Alignment.centerRight
              ? TextAlign.right
              : TextAlign.left,
        ),
      ),
    );
  }
}

class _StationTimetableEntry extends StatefulWidget {
  const _StationTimetableEntry({
    required this.detail,
    this.repository,
    this.previousStation,
    this.nextStation,
  });

  final StationDetail detail;
  final StationTimetableRepository? repository;
  final String? previousStation;
  final String? nextStation;

  @override
  State<_StationTimetableEntry> createState() => _StationTimetableEntryState();
}

class _StationTimetableEntryState extends State<_StationTimetableEntry> {
  StationTimetable? _timetable;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository != null && widget.detail.lines.isNotEmpty) {
      unawaited(_load(repository, widget.detail.lines));
    }
  }

  Future<void> _load(
    StationTimetableRepository repository,
    List<StationSearchLine> lines,
  ) async {
    try {
      final date = debugStationVerifiedClock();
      StationTimetable? unavailable;
      for (final line in lines) {
        final timetable = await repository.loadStationTimetableForDate(
          stationId: widget.detail.id,
          date: date,
          lineId: line.id,
        );
        if (timetable.isAvailable) {
          if (mounted) {
            setState(() {
              _timetable = timetable;
              _unavailable = false;
            });
          }
          return;
        }
        unavailable ??= timetable;
      }
      if (mounted) {
        setState(() {
          _timetable = unavailable;
          _unavailable = true;
        });
      }
    } on StationTimetableUnavailable {
      if (mounted) {
        setState(() {
          _timetable = null;
          _unavailable = true;
        });
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _timetable = null;
          _unavailable = true;
        });
      }
      reportMobileError(
        error,
        stackTrace,
        context: '역 상세 시간표 요약 조회 중 예외가 발생했습니다.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 서버가 시간표를 제공하지 않으면 요약 줄을 그리지 않는다.
        // '시간표 보기' 버튼은 남겨 전체 시간표 화면으로 진입할 수 있게 한다.
        if (timetable != null && timetable.isAvailable) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.surfaceDefault,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: EasySubwayAccessibleColors.borderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < timetable.directions.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height: 1,
                        color: EasySubwayAccessibleColors.line,
                      ),
                    ),
                  Builder(
                    builder: (context) {
                      final direction = timetable.directions[i];
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatStationDirectionName(
                                direction.name,
                                previousStation: widget.previousStation,
                                nextStation: widget.nextStation,
                              ),
                              style: const TextStyle(
                                color: EasySubwayAccessibleColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StationDetailFirstLastBadge(
                            label: '첫차',
                            time: direction.firstDeparture.timeLabel,
                          ),
                          const SizedBox(width: 8),
                          _StationDetailFirstLastBadge(
                            label: '막차',
                            time: direction.lastDeparture.timeLabel,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (_unavailable)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('시간표 정보를 불러오지 못했습니다.'),
          ),
        OutlinedButton.icon(
          key: const Key('stationTimetableButton'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StationTimetableScreen(
                stationId: widget.detail.id,
                stationName: widget.detail.nameKo,
                lines: widget.detail.lines,
                repository: widget.repository,
                previousStation: widget.previousStation,
                nextStation: widget.nextStation,
              ),
            ),
          ),
          icon: const Icon(Icons.schedule, size: 18),
          label: const Text('시간표 보기'),
          style: OutlinedButton.styleFrom(
            foregroundColor: EasySubwayAccessibleColors.primary,
            side: const BorderSide(color: EasySubwayAccessibleColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _StationDetailFirstLastBadge extends StatelessWidget {
  const _StationDetailFirstLastBadge({required this.label, required this.time});

  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: EasySubwayAccessibleColors.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          time,
          style: const TextStyle(
            color: EasySubwayAccessibleColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StationDetailAdaptiveContent extends StatelessWidget {
  const _StationDetailAdaptiveContent({
    required this.primaryChildren,
    required this.detailChildren,
  });

  final List<Widget> primaryChildren;
  final List<Widget> detailChildren;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('stationDetailLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                key: const Key('stationDetailPrimaryColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: primaryChildren,
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 5,
              child: Column(
                key: const Key('stationDetailDetailColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: detailChildren,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationDetailSectionTitle extends StatelessWidget {
  const _StationDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _StationBarrierFreeRouteCard extends StatelessWidget {
  const _StationBarrierFreeRouteCard({
    required this.station,
    required this.exits,
    required this.facilities,
  });

  final StationDetail station;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accessibleExits = exits
        .where((e) => e.hasElevatorConnection)
        .toList();
    final elevators = facilities
        .where((f) => f.type == 'ELEVATOR' || f.name.contains('엘리베이터'))
        .toList();
    final brokenElevators = elevators
        .where((f) => f.status == 'BROKEN' || f.status == 'CLOSED')
        .toList();
    final lifts = facilities
        .where((f) => f.type == 'WHEELCHAIR_LIFT' || f.name.contains('리프트'))
        .toList();

    final bool isFullBarrierFree =
        (accessibleExits.isNotEmpty || elevators.length >= 2) &&
        elevators.isNotEmpty &&
        brokenElevators.isEmpty;
    final bool hasCaution = brokenElevators.isNotEmpty;

    final String statusBadgeText;
    final Color badgeBgColor;
    final Color badgeTextColor;
    final Color badgeBorderColor;
    final String routeDescription;

    if (hasCaution) {
      statusBadgeText = '일부 점검 중';
      badgeBgColor = EasySubwayColorPrimitives.statusWarningSoft;
      badgeTextColor = EasySubwayAccessibleColors.amber;
      badgeBorderColor = EasySubwayAccessibleColors.amber;
      routeDescription =
          '${brokenElevators.map((e) => e.displayName).join(', ')} 점검 중입니다. 역무실 문의가 필요합니다.';
    } else if (isFullBarrierFree) {
      statusBadgeText = '전 구간 무단차 이동 가능';
      badgeBgColor = EasySubwayColorPrimitives.statusSuccessSoft;
      badgeTextColor = EasySubwayAccessibleColors.mint;
      badgeBorderColor = EasySubwayAccessibleColors.mint;
      routeDescription = accessibleExits.isNotEmpty
          ? '지상에서 승강장까지 계단 없이 엘리베이터로 이동 가능합니다 (EV 연결 출구: ${accessibleExits.map((e) => e.name).join(', ')}).'
          : '지상에서 대합실, 승강장까지 전 구간 엘리베이터를 이용하여 계단 없이 편리하게 이동할 수 있습니다.';
    } else if (lifts.isNotEmpty) {
      statusBadgeText = '휠체어 리프트 이용 가능';
      badgeBgColor = EasySubwayAccessibleColors.surfaceSubtle;
      badgeTextColor = EasySubwayAccessibleColors.primary;
      badgeBorderColor = EasySubwayAccessibleColors.line;
      routeDescription = '일부 구간은 계단 대신 휠체어 리프트를 이용하여 이동할 수 있습니다.';
    } else {
      statusBadgeText = '무단차 동선 안내';
      badgeBgColor = EasySubwayAccessibleColors.surfaceSubtle;
      badgeTextColor = EasySubwayAccessibleColors.secondaryText;
      badgeBorderColor = EasySubwayAccessibleColors.line;
      routeDescription = '역사 내 승강기 이동 및 무단차 동선 이용 시 고객안전실로 문의 바랍니다.';
    }

    final evExitLabel = accessibleExits.isNotEmpty
        ? 'EV 연결: ${accessibleExits.map((e) => e.name).join(', ')}'
        : '역사 출구 EV 이용';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: EasySubwayAccessibleColors.surfaceBrandChrome,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.accessible_forward,
                  color: EasySubwayAccessibleColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '지상 ↔ 대합실 ↔ 승강장 동선',
                  style: textTheme.titleMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBgColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeBorderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFullBarrierFree) ...[
                      const Icon(
                        Icons.check_circle,
                        size: 13,
                        color: EasySubwayAccessibleColors.mint,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      statusBadgeText,
                      style: textTheme.bodySmall?.copyWith(
                        color: badgeTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _VerticalStepRow(
                  stepNum: '1',
                  stepTitle: '지상 (출구)',
                  stepDetail: evExitLabel,
                  icon: Icons.elevator,
                  iconColor: EasySubwayAccessibleColors.mint,
                  isLast: false,
                ),
                _VerticalStepRow(
                  stepNum: '2',
                  stepTitle: '대합실 (개찰구)',
                  stepDetail: '교통약자 전용 넓은 개찰구 (게이트 안, 밖 이동)',
                  icon: Icons.confirmation_number_outlined,
                  iconColor: EasySubwayAccessibleColors.primary,
                  isLast: false,
                ),
                _VerticalStepRow(
                  stepNum: '3',
                  stepTitle: '승강장 (탑승)',
                  stepDetail: '승강장 연결 내부 엘리베이터 (방면별 탑승)',
                  icon: Icons.train_outlined,
                  iconColor: EasySubwayAccessibleColors.mint,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            routeDescription,
            style: textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalStepRow extends StatelessWidget {
  const _VerticalStepRow({
    required this.stepNum,
    required this.stepTitle,
    required this.stepDetail,
    required this.icon,
    required this.iconColor,
    required this.isLast,
  });

  final String stepNum;
  final String stepTitle;
  final String stepDetail;
  final IconData icon;
  final Color iconColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: 0.12),
                  border: Border.all(color: iconColor, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: iconColor),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: EasySubwayAccessibleColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: EasySubwayAccessibleColors.surfaceBrandChrome,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$stepNum단계',
                          style: textTheme.labelSmall?.copyWith(
                            color: EasySubwayAccessibleColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        stepTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stepDetail,
                    style: textTheme.bodySmall?.copyWith(
                      color: EasySubwayAccessibleColors.secondaryText,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationFacilityMatrixCard extends StatelessWidget {
  const _StationFacilityMatrixCard({
    required this.station,
    required this.facilities,
  });

  final StationDetail station;
  final List<StationFacilityInfo> facilities;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final toilets = facilities
        .where(
          (f) =>
              f.type == 'TOILET' ||
              f.type == 'ACCESSIBLE_TOILET' ||
              f.name.contains('화장실'),
        )
        .toList();
    bool insideGate = false;
    bool outsideGate = false;
    for (final t in toilets) {
      final text = '${t.name} ${t.description} ${t.floorFrom}'.toLowerCase();
      if (text.contains('안') ||
          text.contains('내부') ||
          text.contains('운임구역 내') ||
          text.contains('승강장') ||
          text.contains('게이트 안')) {
        insideGate = true;
      }
      if (text.contains('밖') ||
          text.contains('외부') ||
          text.contains('운임구역 외') ||
          text.contains('대합실') ||
          text.contains('게이트 밖') ||
          text.contains('출구')) {
        outsideGate = true;
      }
    }
    final String toiletStatus;
    if (toilets.isEmpty) {
      toiletStatus = '개찰구 밖 (대합실)';
    } else if (insideGate && outsideGate) {
      toiletStatus = '개찰구 안, 밖 모두';
    } else if (insideGate) {
      toiletStatus = '개찰구 안 (운임구역 내)';
    } else if (outsideGate) {
      toiletStatus = '개찰구 밖 (운임구역 외)';
    } else {
      toiletStatus = '개찰구 밖 (대합실)';
    }

    final hasAccessibleToilet = facilities.any(
      (f) => f.type == 'ACCESSIBLE_TOILET' || f.name.contains('장애인 화장실'),
    );
    final hasNursingRoom = facilities.any(
      (f) => f.type == 'NURSING_ROOM' || f.name.contains('수유실'),
    );
    final elevators = facilities
        .where((f) => f.type == 'ELEVATOR' || f.name.contains('엘리베이터'))
        .toList();
    final elevatorBroken = elevators.any(
      (f) => f.status == 'BROKEN' || f.status == 'CLOSED',
    );
    final lifts = facilities
        .where((f) => f.type == 'WHEELCHAIR_LIFT' || f.name.contains('리프트'))
        .toList();
    final liftBroken = lifts.any(
      (f) => f.status == 'BROKEN' || f.status == 'CLOSED',
    );

    final primaryItems = [
      (
        icon: Icons.wc_outlined,
        title: '화장실 위치',
        status: toiletStatus,
        isHighlight: true,
        color: EasySubwayAccessibleColors.primary,
      ),
      (
        icon: Icons.accessible,
        title: '장애인 화장실',
        status: hasAccessibleToilet ? '남녀 구분 설치' : '대합실 설치 (역무실 문의)',
        isHighlight: hasAccessibleToilet,
        color: EasySubwayAccessibleColors.mint,
      ),
      (
        icon: Icons.elevator,
        title: '승강기(EV)',
        status: elevators.isEmpty
            ? '미설치'
            : (elevatorBroken ? '일부 점검 중' : '${elevators.length}대 정상 운행'),
        isHighlight: elevators.isNotEmpty && !elevatorBroken,
        color: EasySubwayAccessibleColors.mint,
      ),
      (
        icon: Icons.accessible_forward,
        title: '휠체어 리프트',
        status: lifts.isEmpty
            ? '미설치'
            : (liftBroken ? '점검 중' : '${lifts.length}대 운행 중'),
        isHighlight: lifts.isNotEmpty && !liftBroken,
        color: EasySubwayAccessibleColors.primary,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 20,
                color: EasySubwayAccessibleColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '주요 편의시설 한눈에 보기',
                style: textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final item in primaryItems)
                    SizedBox(
                      width: itemWidth,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: item.isHighlight
                                  ? item.color.withValues(alpha: 0.12)
                                  : EasySubwayAccessibleColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              item.icon,
                              size: 18,
                              color: item.isHighlight
                                  ? item.color
                                  : EasySubwayAccessibleColors.mutedText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: EasySubwayAccessibleColors
                                        .secondaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: item.isHighlight
                                        ? EasySubwayAccessibleColors.text
                                        : EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FacilityTag(
                icon: Icons.baby_changing_station,
                label: '수유실',
                status: hasNursingRoom ? '이용 가능' : '미설치',
                active: hasNursingRoom,
              ),
              const _FacilityTag(
                icon: Icons.battery_charging_full,
                label: '휠체어 급속충전기',
                status: '고객안전실 문의',
                active: false,
              ),
              const _FacilityTag(
                icon: Icons.medical_services_outlined,
                label: '자동제세동기(AED)',
                status: '역사 내 비치',
                active: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FacilityTag extends StatelessWidget {
  const _FacilityTag({
    required this.icon,
    required this.label,
    required this.status,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String status;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: active
                ? EasySubwayAccessibleColors.primary
                : EasySubwayAccessibleColors.mutedText,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: active
                  ? EasySubwayAccessibleColors.text
                  : EasySubwayAccessibleColors.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: active
                  ? EasySubwayAccessibleColors.mint
                  : EasySubwayAccessibleColors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationSafetyOfficeCard extends StatelessWidget {
  const _StationSafetyOfficeCard({
    required this.detail,
    required this.facilities,
  });

  final StationDetail detail;
  final List<StationFacilityInfo> facilities;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final phone = _resolveStationPhone(detail: detail, facilities: facilities);
    final operatorName = _resolveOperatorName(detail);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: EasySubwayAccessibleColors.surfaceBrandChrome,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.support_agent,
                  color: EasySubwayAccessibleColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '고객안전실 (역무실)',
                      style: textTheme.titleMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$operatorName · 직통 전화: $phone',
                      style: textTheme.bodySmall?.copyWith(
                        color: EasySubwayAccessibleColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: EasySubwayAccessibleColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: EasySubwayAccessibleColors.line),
                ),
                child: Text(
                  '24시간 운영',
                  style: textTheme.labelSmall?.copyWith(
                    color: EasySubwayAccessibleColors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '휠체어 승하차 도우미(리프트, 안전발판) 신청, 분실물 문의 및 역사 내 긴급 상황 발생 시 바로 연결됩니다.',
            style: textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              key: Key('stationSafetyOfficeCallButton-${detail.id}'),
              icon: const Icon(Icons.phone_in_talk, size: 20),
              label: Text('고객안전실 전화 걸기 ($phone)'),
              onPressed: () => _callPhone(context, phone),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callPhone(BuildContext context, String phone) async {
    final cleanDigits = phone.replaceAll(RegExp(r'[^\d]'), '');
    final uri = Uri(scheme: 'tel', path: cleanDigits);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('전화 앱을 실행할 수 없습니다: $phone')));
        }
      }
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '고객안전실 전화 걸기 실행 중 오류 발생');
    }
  }
}

String _resolveOperatorName(StationDetail detail) {
  final lineNames = detail.lines.map((l) => '${l.id} ${l.name}').join(' ');
  final region = detail.region;

  if (region.contains('부산') || lineNames.contains('부산')) return '부산교통공사';
  if (region.contains('대구') || lineNames.contains('대구')) return '대구교통공사';
  if (region.contains('대전') || lineNames.contains('대전')) return '대전교통공사';
  if (region.contains('광주') || lineNames.contains('광주')) return '광주교통공사';

  if (lineNames.contains('신분당')) return '네오트랜스 (신분당선)';
  if (lineNames.contains('공항')) return '공항철도 (AREX)';
  if (lineNames.contains('9호선')) return '서울시메트로9호선';
  if (lineNames.contains('인천')) return '인천교통공사';
  if (lineNames.contains('우이신설')) return '우이신설경전철';
  if (lineNames.contains('신림')) return '남서울경전철';
  if (lineNames.contains('김포')) return '김포골드라인운영';
  if (lineNames.contains('의정부')) return '의정부경량전철';
  if (lineNames.contains('에버라인') || lineNames.contains('용인')) return '용인경량전철';
  if (lineNames.contains('경의중앙') ||
      lineNames.contains('수인분당') ||
      lineNames.contains('경춘') ||
      lineNames.contains('서해') ||
      lineNames.contains('경강') ||
      lineNames.contains('동해')) {
    return '한국철도공사 (코레일)';
  }

  return '서울교통공사';
}

String _resolveStationPhone({
  required StationDetail detail,
  List<StationFacilityInfo> facilities = const [],
}) {
  final phoneRegex = RegExp(r'0\d{1,2}-\d{3,4}-\d{4}|1\d{3}-\d{4}');
  for (final facility in facilities) {
    if (facility.type == 'CUSTOMER_CENTER' ||
        facility.type == 'STATION_OFFICE') {
      final match = phoneRegex.firstMatch(
        '${facility.description} ${facility.name}',
      );
      if (match != null) {
        return match.group(0)!;
      }
    }
  }

  final lineNames = detail.lines.map((l) => '${l.id} ${l.name}').join(' ');
  final region = detail.region;

  if (region.contains('부산') || lineNames.contains('부산')) {
    if (lineNames.contains('김해')) return '055-310-9800';
    return '1544-5005';
  }
  if (region.contains('대구') || lineNames.contains('대구')) {
    return '053-643-2114';
  }
  if (region.contains('대전') || lineNames.contains('대전')) {
    return '042-539-3114';
  }
  if (region.contains('광주') || lineNames.contains('광주')) {
    return '062-604-8000';
  }

  if (lineNames.contains('신분당')) return '031-8018-7777';
  if (lineNames.contains('공항')) return '1599-7788';
  if (lineNames.contains('9호선')) return '02-2656-0009';
  if (lineNames.contains('인천')) return '032-451-2114';
  if (lineNames.contains('우이신설')) return '02-3499-5561';
  if (lineNames.contains('신림')) return '02-2081-8181';
  if (lineNames.contains('김포')) return '031-988-7123';
  if (lineNames.contains('의정부')) return '031-828-3114';
  if (lineNames.contains('에버라인') || lineNames.contains('용인')) {
    return '031-329-3500';
  }
  if (lineNames.contains('경의중앙') ||
      lineNames.contains('수인분당') ||
      lineNames.contains('경춘') ||
      lineNames.contains('서해') ||
      lineNames.contains('경강') ||
      lineNames.contains('동해')) {
    return '1544-7788';
  }

  return '1577-1234';
}
