import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../adaptive_layout.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../mobile_error_reporter.dart';
import '../../facility_report/domain/facility_report_target.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/domain/route_draft.dart';
import '../application/station_detail_controller.dart';
import '../data/server_station_timetable_repository.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'station_detail_route_actions.dart';
import 'station_exit_section.dart';
import 'station_facility_card.dart';
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

/// 전국 전역에 공통 적용되는 네이버 지도 1:1 표준 역 상세 화면 본문.
///
/// 특정 역에 하드코딩되지 않고 [StationDetail], [StationFacilityInfo], [StationExitInfo]
/// 도메인 데이터에 기반하여 역정보(시설정보·편의시설·교통약자 시설), 출구정보,
/// 하단 고정 액션바([출발], [도착], [전체 시간표], [첫차·막차])를 표준 규격으로 렌더링한다.
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
    this.mapPreviewBuilder,
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
  final StationExitMapPreviewBuilder? mapPreviewBuilder;
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
        mapPreviewBuilder: mapPreviewBuilder,
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
    this.mapPreviewBuilder,
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
  final StationExitMapPreviewBuilder? mapPreviewBuilder;
  final bool showContextChrome;
  final bool showRealtimeSection;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchLine? lineForChrome;

  @override
  Widget build(BuildContext context) {
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
      if (favoriteController != null) ...[
        StationDetailRouteActions(
          detail: detail,
          routeDraftController: null,
          favoriteController: favoriteController,
        ),
        const SizedBox(height: 16),
      ],
      if (timetableRepository != null) ...[
        _StationTimetableEntry(
          detail: detail,
          repository: timetableRepository,
          previousStation: previousStation?.nameKo,
          nextStation: nextStation?.nameKo,
        ),
        const SizedBox(height: 16),
      ],
    ];

    final hasExits = exits.isNotEmpty;
    final hasFacilities = facilities.isNotEmpty;

    final detailChildren = <Widget>[
      if (hasExits) ...[
        _StationNaverExitSection(
          station: detail,
          exits: exits,
          mapLauncher: mapLauncher,
          locationProvider: locationProvider,
          mapPreviewBuilder: mapPreviewBuilder,
          previousStation: previousStation?.nameKo,
          nextStation: nextStation?.nameKo,
        ),
        const SizedBox(height: 16),
      ],
      if (hasFacilities) ...[
        _StationNaverStationInfoSection(
          station: detail,
          facilities: facilities,
          onOpenFacilityReport: onOpenFacilityReport,
        ),
        const SizedBox(height: 16),
        for (final facility in facilities)
          StationFacilityCard(
            facility: facility,
            station: detail,
            onReportTap: () => onOpenFacilityReport(
              FacilityReportTarget(
                stationId: detail.id,
                stationName: detail.nameKo,
                facilityId: facility.id,
                facilityName: facility.name,
                facilityTypeLabel: facility.type,
                facilityStatusLabel: facility.status,
              ),
            ),
          ),
        const SizedBox(height: 16),
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
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      if (layoutSummaryItems.isNotEmpty) ...[
        const SizedBox(height: 16),
        const _StationDetailSectionTitle(title: '역 안 이동'),
        const SizedBox(height: 12),
        StationLayoutSummary(
          items: layoutSummaryItems,
          semanticLabel: layoutSummarySemanticLabel,
        ),
      ],
      const SizedBox(height: 16),
      if (bottomAdBuilder case final builder?) ...[
        const SizedBox(height: 24),
        builder(context),
      ],
    ];

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
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
                        const SizedBox(height: 16),
                        Container(
                          height: 8,
                          color: EasySubwayAccessibleColors.surfaceSubtle,
                        ),
                        const SizedBox(height: 16),
                        ...detailChildren,
                      ],
              );
            },
          ),
        ),
        _StationDetailStickyBottomBar(
          detail: detail,
          routeDraftController: routeDraftController,
          timetableRepository: timetableRepository,
          previousStation: previousStation,
          nextStation: nextStation,
        ),
      ],
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
                icon: Icon(
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

/// 네이버 지도 1:1 표준 역정보 섹션.
///
/// 1. 시설정보 2열 2행 4구 그리드 (플랫폼, 화장실, 내리는문, 반대편 연결)
/// 2. 편의시설 2열 2행 4구 그리드 (자전거보관소, 환승주차장, 유실물센터, 물품보관소)
/// 3. 교통약자 시설 2열 2행 4구 그리드 (장애인화장실, 엘리베이터, 수유실, 휠체어 리프트)
class _StationNaverStationInfoSection extends StatelessWidget {
  const _StationNaverStationInfoSection({
    required this.station,
    required this.facilities,
    this.onOpenFacilityReport,
  });

  final StationDetail station;
  final List<StationFacilityInfo> facilities;
  final Future<void> Function(FacilityReportTarget target)?
  onOpenFacilityReport;

  @override
  Widget build(BuildContext context) {
    // 1. 시설정보 계산
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
          text.contains('게이트 안') ||
          text.contains('개찰구 안')) {
        insideGate = true;
      }
      if (text.contains('밖') ||
          text.contains('외부') ||
          text.contains('운임구역 외') ||
          text.contains('대합실') ||
          text.contains('게이트 밖') ||
          text.contains('개찰구 밖') ||
          text.contains('출구')) {
        outsideGate = true;
      }
    }
    final String toiletTag;
    if (toilets.isEmpty) {
      toiletTag = '-';
    } else if (insideGate && outsideGate) {
      toiletTag = '개찰구 안/밖';
    } else if (insideGate) {
      toiletTag = '개찰구 안';
    } else if (outsideGate) {
      toiletTag = '개찰구 밖';
    } else {
      toiletTag = '-';
    }

    String? foundDoorTag;
    String? foundPlatformTag;
    String? foundCrossPlatformTag;
    for (final f in facilities) {
      final text = '${f.name} ${f.description}'.toLowerCase();
      if (text.contains('왼쪽')) foundDoorTag = '왼쪽';
      if (text.contains('오른쪽')) foundDoorTag = '오른쪽';
      if (text.contains('단선') || text.contains('단선승강장')) {
        foundPlatformTag = '단선';
      }
      if (text.contains('섬식')) foundPlatformTag = '섬식';
      if (text.contains('상대식')) foundPlatformTag = '양쪽';
      final noSpaces = text.replaceAll(' ', '');
      if (noSpaces.contains('이동불가') || noSpaces.contains('횡단불가')) {
        foundCrossPlatformTag = '이동 불가';
      }
      if (noSpaces.contains('횡단가능') ||
          noSpaces.contains('반대편연결') ||
          noSpaces.contains('반대편이동가능')) {
        foundCrossPlatformTag = '연결됨';
      }
    }

    final doorTag = foundDoorTag ?? '-';
    final platformTag = foundPlatformTag ?? '-';
    final crossPlatformTag = foundCrossPlatformTag ?? '-';

    // 2. 편의시설 설치 여부 확인
    final hasBicycle = facilities.any(
      (f) =>
          f.type == 'BICYCLE' ||
          f.name.contains('자전거') ||
          f.description.contains('자전거'),
    );
    final hasParking = facilities.any(
      (f) =>
          f.type == 'PARKING' ||
          f.name.contains('주차장') ||
          f.description.contains('주차장'),
    );
    final hasLostItem = facilities.any(
      (f) =>
          f.type == 'LOST_ITEM' ||
          f.type == 'LOST_AND_FOUND' ||
          f.name.contains('유실물') ||
          f.description.contains('유실물'),
    );
    final hasStorage = facilities.any(
      (f) =>
          f.type == 'LOCKER' ||
          f.type == 'STORAGE' ||
          f.name.contains('물품보관') ||
          f.name.contains('보관함') ||
          f.description.contains('물품보관') ||
          f.description.contains('보관함'),
    );

    // 3. 교통약자 시설 매핑 및 설치 여부 확인
    final disabledToiletFacility = facilities
        .cast<StationFacilityInfo?>()
        .firstWhere(
          (f) =>
              f != null &&
              (f.type == 'ACCESSIBLE_TOILET' || f.name.contains('장애인')),
          orElse: () => null,
        );
    final elevatorFacility = facilities.cast<StationFacilityInfo?>().firstWhere(
      (f) => f != null && (f.type == 'ELEVATOR' || f.name.contains('엘리베이터')),
      orElse: () => null,
    );
    final nursingFacility = facilities.cast<StationFacilityInfo?>().firstWhere(
      (f) => f != null && (f.type == 'NURSING_ROOM' || f.name.contains('수유실')),
      orElse: () => null,
    );
    final wheelchairLiftFacility = facilities
        .cast<StationFacilityInfo?>()
        .firstWhere(
          (f) =>
              f != null &&
              (f.type == 'WHEELCHAIR_LIFT' || f.name.contains('리프트')),
          orElse: () => null,
        );

    final hasDisabledToilet = disabledToiletFacility != null;
    final hasElevator = elevatorFacility != null;
    final hasNursingRoom = nursingFacility != null;
    final hasWheelchairLift = wheelchairLiftFacility != null;

    VoidCallback? reportCallback(StationFacilityInfo? facility) {
      if (facility == null || onOpenFacilityReport == null) return null;
      return () => onOpenFacilityReport!(
        FacilityReportTarget(
          stationId: station.id,
          stationName: station.nameKo,
          facilityId: facility.id,
          facilityName: facility.name,
          facilityTypeLabel: facility.type,
          facilityStatusLabel: facility.status,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '역정보',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        // 시설정보
        const Text(
          '시설정보',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NaverFacilityTagItem(
                icon: Icons.train_outlined,
                label: '플랫폼',
                tag: platformTag,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NaverFacilityTagItem(
                icon: Icons.wc_outlined,
                label: '화장실',
                tag: toiletTag,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NaverFacilityTagItem(
                icon: Icons.meeting_room_outlined,
                label: '내리는문',
                tag: doorTag,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NaverFacilityTagItem(
                icon: Icons.swap_horiz,
                label: '반대편',
                tag: crossPlatformTag,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(
          height: 1,
          thickness: 1,
          color: EasySubwayAccessibleColors.line,
        ),
        const SizedBox(height: 16),

        // 편의시설
        const Text(
          '편의시설',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NaverAmenityGridItem(
                icon: Icons.directions_bike,
                label: '자전거보관소',
                isAvailable: hasBicycle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NaverAmenityGridItem(
                icon: Icons.local_parking,
                label: '환승주차장',
                isAvailable: hasParking,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NaverAmenityGridItem(
                icon: Icons.find_in_page_outlined,
                label: '유실물센터',
                isAvailable: hasLostItem,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NaverAmenityGridItem(
                icon: Icons.inventory_2_outlined,
                label: '물품보관소',
                isAvailable: hasStorage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(
          height: 1,
          thickness: 1,
          color: EasySubwayAccessibleColors.line,
        ),
        const SizedBox(height: 16),

        // 교통약자 시설
        const Text(
          '교통약자 시설',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NaverAccessibleFacilityItem(
                key: disabledToiletFacility != null
                    ? Key(
                        'naverFacilityReportButton-${disabledToiletFacility.id}',
                      )
                    : null,
                icon: Icons.accessible,
                label: '장애인화장실',
                isAvailable: hasDisabledToilet,
                onTap: reportCallback(disabledToiletFacility),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NaverAccessibleFacilityItem(
                key: elevatorFacility != null
                    ? Key('naverFacilityReportButton-${elevatorFacility.id}')
                    : null,
                icon: Icons.elevator_outlined,
                label: '엘리베이터',
                isAvailable: hasElevator,
                onTap: reportCallback(elevatorFacility),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _NaverAccessibleFacilityItem(
                key: nursingFacility != null
                    ? Key('naverFacilityReportButton-${nursingFacility.id}')
                    : null,
                icon: Icons.baby_changing_station,
                label: '수유실',
                isAvailable: hasNursingRoom,
                onTap: reportCallback(nursingFacility),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NaverAccessibleFacilityItem(
                key: wheelchairLiftFacility != null
                    ? Key(
                        'naverFacilityReportButton-${wheelchairLiftFacility.id}',
                      )
                    : null,
                icon: Icons.accessible_forward,
                label: '휠체어 리프트',
                isAvailable: hasWheelchairLift,
                onTap: reportCallback(wheelchairLiftFacility),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NaverFacilityTagItem extends StatelessWidget {
  const _NaverFacilityTagItem({
    required this.icon,
    required this.label,
    required this.tag,
  });

  final IconData icon;
  final String label;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $tag',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: EasySubwayAccessibleColors.secondaryText),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: EasySubwayAccessibleColors.text,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: EasySubwayAccessibleColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NaverAmenityGridItem extends StatelessWidget {
  const _NaverAmenityGridItem({
    required this.icon,
    required this.label,
    required this.isAvailable,
  });

  final IconData icon;
  final String label;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label ${isAvailable ? '있음' : '없음'}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAvailable)
            Icon(icon, size: 20, color: EasySubwayAccessibleColors.text)
          else
            _DisabledIconWithSlash(
              child: Icon(
                icon,
                size: 20,
                color: EasySubwayAccessibleColors.mutedText,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isAvailable ? FontWeight.w600 : FontWeight.w400,
                color: isAvailable
                    ? EasySubwayAccessibleColors.text
                    : EasySubwayAccessibleColors.mutedText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NaverAccessibleFacilityItem extends StatelessWidget {
  const _NaverAccessibleFacilityItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isAvailable,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isAvailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isAvailable)
          Icon(icon, size: 20, color: EasySubwayAccessibleColors.text)
        else
          _DisabledIconWithSlash(
            child: Icon(
              icon,
              size: 20,
              color: EasySubwayAccessibleColors.mutedText,
            ),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isAvailable ? FontWeight.w600 : FontWeight.w400,
              color: isAvailable
                  ? EasySubwayAccessibleColors.text
                  : EasySubwayAccessibleColors.mutedText,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      label: '$label ${isAvailable ? '있음' : '없음'}',
      button: isAvailable && onTap != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: isAvailable && onTap != null
            ? InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 2,
                  ),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}

class _DisabledIconWithSlash extends StatelessWidget {
  const _DisabledIconWithSlash({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(foregroundPainter: const _SlashPainter(), child: child);
  }
}

class _SlashPainter extends CustomPainter {
  const _SlashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EasySubwayAccessibleColors.mutedText
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.15),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 네이버 지도 1:1 표준 출구정보 래퍼 섹션.
class _StationNaverExitSection extends StatelessWidget {
  const _StationNaverExitSection({
    required this.station,
    required this.exits,
    required this.mapLauncher,
    required this.locationProvider,
    this.mapPreviewBuilder,
    this.previousStation,
    this.nextStation,
  });

  final StationDetail station;
  final List<StationExitInfo> exits;
  final KakaoMapLauncher mapLauncher;
  final CurrentLocationProvider? locationProvider;
  final StationExitMapPreviewBuilder? mapPreviewBuilder;
  final String? previousStation;
  final String? nextStation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '출구정보',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        StationExitSection(
          key: ValueKey('stationExitSection-${station.id}'),
          station: station,
          exits: exits,
          mapLauncher: mapLauncher,
          locationProvider: locationProvider,
          mapPreviewBuilder: mapPreviewBuilder,
          previousStation: previousStation,
          nextStation: nextStation,
        ),
      ],
    );
  }
}

/// 네이버 지도 1:1 표준 하단 고정 액션바 (Sticky Bottom Bar).
///
/// [출발] (연한 블루 둥근 버튼), [도착] (진한 블루 채움 둥근 버튼),
/// [📅 전체 시간표] (화이트 아웃라인 둥근 버튼), [🚆 첫차·막차] (화이트 아웃라인 둥근 버튼).
class _StationDetailStickyBottomBar extends StatelessWidget {
  const _StationDetailStickyBottomBar({
    required this.detail,
    required this.routeDraftController,
    required this.timetableRepository,
    required this.previousStation,
    required this.nextStation,
  });

  final StationDetail detail;
  final RouteDraftPort? routeDraftController;
  final StationTimetableRepository? timetableRepository;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border(
          top: BorderSide(color: EasySubwayAccessibleColors.line, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // [출발]
            Expanded(
              flex: 5,
              child: Material(
                color: EasySubwayAccessibleColors.surfaceBrandChrome,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  key: const Key('stationDetailSetOriginButton'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    final station = RouteDraftStation(
                      id: detail.id,
                      nameKo: detail.nameKo,
                    );
                    routeDraftController?.setOrigin(station);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${station.displayName}을 출발역으로 설정했습니다'),
                      ),
                    );
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: const Text(
                      '출발',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // [도착]
            Expanded(
              flex: 5,
              child: Material(
                color: EasySubwayAccessibleColors.primary,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  key: const Key('stationDetailSetDestinationButton'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    final station = RouteDraftStation(
                      id: detail.id,
                      nameKo: detail.nameKo,
                    );
                    routeDraftController?.setDestination(station);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${station.displayName}을 도착역으로 설정했습니다'),
                      ),
                    );
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: const Text(
                      '도착',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // [📅 전체 시간표]
            Expanded(
              flex: 9,
              child: Material(
                color: EasySubwayAccessibleColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: EasySubwayAccessibleColors.line),
                ),
                child: InkWell(
                  key: const Key('stationTimetableButton'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openTimetable(context),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: EasySubwayAccessibleColors.text,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '전체 시간표',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: EasySubwayAccessibleColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // [🚆 첫차·막차]
            Expanded(
              flex: 9,
              child: Material(
                color: EasySubwayAccessibleColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: EasySubwayAccessibleColors.line),
                ),
                child: InkWell(
                  key: const Key('stationDetailBottomFirstLastButton'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openTimetable(context),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.train_outlined,
                          size: 15,
                          color: EasySubwayAccessibleColors.text,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '첫차·막차',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: EasySubwayAccessibleColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTimetable(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StationTimetableScreen(
            stationId: detail.id,
            stationName: detail.nameKo,
            lines: detail.lines,
            repository: timetableRepository,
            previousStation: previousStation?.nameKo,
            nextStation: nextStation?.nameKo,
          ),
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
      final date = clock.now();
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
    } on ServerConnectionException {
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
    if (timetable == null && !_unavailable) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                                directionIndex: i,
                              ),
                              style: TextStyle(
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
          style: TextStyle(
            color: EasySubwayAccessibleColors.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          time,
          style: TextStyle(
            color: EasySubwayAccessibleColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
