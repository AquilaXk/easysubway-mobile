import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../adaptive_layout.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../core/ui/line_mark.dart';
import '../../../core/ui/name_with_marks.dart';
import '../../../design_tokens.dart';
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

/// 전국 전역에 공통 적용되는 상용 지하철 서비스와 같은 역 상세 화면 본문.
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
    final stationInfoGroups = _StationInfoSection.groupsOf(
      station: detail,
      facilities: facilities,
      onOpenFacilityReport: onOpenFacilityReport,
    );

    // 상용 지하철 서비스처럼 역정보 다음에 출구정보를 둔다.
    final detailChildren = <Widget>[
      if (stationInfoGroups.isNotEmpty) ...[
        _StationInfoSection(groups: stationInfoGroups),
        const SizedBox(height: 16),
      ],
      if (hasExits) ...[
        _StationExitInfoSection(
          station: detail,
          exits: exits,
          mapLauncher: mapLauncher,
          mapPreviewBuilder: mapPreviewBuilder,
        ),
        const SizedBox(height: 16),
      ],
      if (hasFacilities) ...[
        const _StationDetailSectionTitle(title: '시설 상세 및 고장 신고'),
        const SizedBox(height: 8),
        for (final facility in facilities)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StationFacilityCard(
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
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        '마지막 확인',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        stationVerifiedRelativeLabel(detail.lastVerifiedAt),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: EasySubwayAccessibleColors.text,
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

  Widget _nameWithMark(BuildContext context) {
    final name = Text(
      '${detail.nameKo}역',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: EasySubwayAccessibleColors.text,
        fontWeight: EasySubwayFontWeight.emphasis,
        height: 1.2,
      ),
    );
    final mark = line;
    if (mark == null) {
      return name;
    }
    return NameWithMarks(
      name: name,
      marksFirst: true,
      marks: StationLineBadge(
        line: mark,
        size: 24,
        maxTextScale: lineMarkFixedChromeMaxTextScale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasNeighbors = previousStation != null || nextStation != null;
    return Column(
      key: const Key('stationDetailContextChrome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _nameWithMark(context)),
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
                    fontWeight: EasySubwayFontWeight.emphasis,
                    color: EasySubwayAccessibleColors.text,
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
            fontWeight: EasySubwayFontWeight.emphasis,
            color: EasySubwayAccessibleColors.text,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

/// 상용 지하철 서비스와 같은 역정보 섹션.
///
/// 1. 시설정보 2열 그리드 (플랫폼, 화장실, 내리는문, 반대편 연결)
/// 2. 편의시설 2열 그리드 (자전거보관소, 환승주차장, 유실물센터, 물품보관소)
/// 3. 교통약자 시설 2열 그리드 (장애인화장실, 엘리베이터, 수유실, 휠체어 리프트)
///
/// 모든 묶음은 원천이 확인한 칸만 그린다. 모르는 값은 `-`나 없음으로 그리지 않고
/// 칸을 빼며, 칸이 하나도 없는 묶음은 제목까지 뺀다.
class _StationInfoSection extends StatelessWidget {
  const _StationInfoSection({required this.groups});

  final List<_StationInfoGroup> groups;

  static const _insideGateKeywords = [
    '안',
    '내부',
    '운임구역 내',
    '승강장',
    '게이트 안',
    '개찰구 안',
  ];
  static const _outsideGateKeywords = [
    '밖',
    '외부',
    '운임구역 외',
    '대합실',
    '게이트 밖',
    '개찰구 밖',
    '출구',
  ];
  static const _doorRules = [
    _TagRule(['왼쪽'], '왼쪽'),
    _TagRule(['오른쪽'], '오른쪽'),
  ];
  static const _platformRules = [
    _TagRule(['단선'], '단선'),
    _TagRule(['섬식'], '섬식'),
    _TagRule(['상대식'], '양쪽'),
  ];
  static const _crossPlatformRules = [
    _TagRule(['이동불가', '횡단불가'], '이동 불가'),
    _TagRule(['횡단가능', '반대편연결', '반대편이동가능'], '연결됨'),
  ];
  static const _amenityKinds = [
    _FacilityKind(
      icon: Icons.directions_bike,
      label: '자전거보관소',
      types: ['BICYCLE'],
      keywords: ['자전거'],
      matchesDescription: true,
    ),
    _FacilityKind(
      icon: Icons.local_parking,
      label: '환승주차장',
      types: ['PARKING'],
      keywords: ['주차장'],
      matchesDescription: true,
    ),
    _FacilityKind(
      icon: Icons.find_in_page_outlined,
      label: '유실물센터',
      types: ['LOST_ITEM', 'LOST_AND_FOUND'],
      keywords: ['유실물'],
      matchesDescription: true,
    ),
    _FacilityKind(
      icon: Icons.inventory_2_outlined,
      label: '물품보관소',
      types: ['LOCKER', 'STORAGE'],
      keywords: ['물품보관', '보관함'],
      matchesDescription: true,
    ),
  ];
  static const _accessibleKinds = [
    _FacilityKind(
      icon: Icons.accessible,
      label: '장애인화장실',
      types: ['ACCESSIBLE_TOILET'],
      keywords: ['장애인'],
    ),
    _FacilityKind(
      icon: Icons.elevator_outlined,
      label: '엘리베이터',
      types: ['ELEVATOR'],
      keywords: ['엘리베이터'],
      absenceType: 'ELEVATOR',
    ),
    _FacilityKind(
      icon: Icons.baby_changing_station,
      label: '수유실',
      types: ['NURSING_ROOM'],
      keywords: ['수유실'],
    ),
    _FacilityKind(
      icon: Icons.accessible_forward,
      label: '휠체어 리프트',
      types: ['WHEELCHAIR_LIFT'],
      keywords: ['리프트'],
      absenceType: 'WHEELCHAIR_LIFT',
    ),
  ];

  /// 화면에 그릴 칸이 있는 묶음만 돌려준다. 구역을 그릴지는 이 목록이 정한다.
  static List<_StationInfoGroup> groupsOf({
    required StationDetail station,
    required List<StationFacilityInfo> facilities,
    required Future<void> Function(FacilityReportTarget target)
    onOpenFacilityReport,
  }) {
    final absentTypes = station.confirmedAbsentFacilityTypes;
    return [
      _facilityInfoGroup(facilities),
      _StationInfoGroup(
        title: '편의시설',
        items: _knownItems(
          _amenityKinds,
          facilities,
          absentTypes,
          (kind, _, isAvailable) => _AmenityGridItem(
            icon: kind.icon,
            label: kind.label,
            isAvailable: isAvailable,
          ),
        ),
      ),
      _StationInfoGroup(
        title: '교통약자 시설',
        items: _knownItems(
          _accessibleKinds,
          facilities,
          absentTypes,
          (kind, installed, isAvailable) => _AccessibleFacilityItem(
            key: installed == null
                ? null
                : Key('stationFacilityReportButton-${installed.id}'),
            icon: kind.icon,
            label: kind.label,
            isAvailable: isAvailable,
            onTap: installed == null
                ? null
                : () => onOpenFacilityReport(_reportTarget(station, installed)),
          ),
        ),
      ),
    ].where((group) => group.items.isNotEmpty).toList();
  }

  static FacilityReportTarget _reportTarget(
    StationDetail station,
    StationFacilityInfo facility,
  ) {
    return FacilityReportTarget(
      stationId: station.id,
      stationName: station.nameKo,
      facilityId: facility.id,
      facilityName: facility.name,
      facilityTypeLabel: facility.type,
      facilityStatusLabel: facility.status,
    );
  }

  /// 유형마다 시설이 있는지, 없다고 확인됐는지, 모르는지를 읽어
  /// 아는 유형만 [build]로 그린다.
  static List<Widget> _knownItems(
    List<_FacilityKind> kinds,
    List<StationFacilityInfo> facilities,
    Set<String> absentTypes,
    Widget Function(
      _FacilityKind kind,
      StationFacilityInfo? installed,
      bool isAvailable,
    )
    build,
  ) {
    final items = <Widget>[];
    for (final kind in kinds) {
      final installed = facilities.where(kind.matches).firstOrNull;
      final knowledge = kind.knowledgeOf(installed, absentTypes);
      if (knowledge != _FacilityKnowledge.unknown) {
        items.add(
          build(kind, installed, knowledge == _FacilityKnowledge.exists),
        );
      }
    }
    return items;
  }

  static _StationInfoGroup _facilityInfoGroup(
    List<StationFacilityInfo> facilities,
  ) {
    final texts = facilities
        .map((f) => '${f.name} ${f.description}'.toLowerCase())
        .toList();
    final tags = [
      (Icons.train_outlined, '플랫폼', _lastTag(texts, _platformRules)),
      (Icons.wc_outlined, '화장실', _toiletTag(facilities)),
      (Icons.meeting_room_outlined, '내리는문', _lastTag(texts, _doorRules)),
      (
        Icons.swap_horiz,
        '반대편',
        _lastTag(
          texts.map((text) => text.replaceAll(' ', '')),
          _crossPlatformRules,
        ),
      ),
    ];
    return _StationInfoGroup(
      title: '시설정보',
      items: [
        for (final (icon, label, tag) in tags)
          if (tag != null) _FacilityTagItem(icon: icon, label: label, tag: tag),
      ],
    );
  }

  /// 텍스트를 차례로 보며 마지막으로 맞은 규칙의 태그를 돌려준다.
  static String? _lastTag(Iterable<String> texts, List<_TagRule> rules) {
    String? tag;
    for (final text in texts) {
      for (final rule in rules) {
        if (rule.matches(text)) tag = rule.tag;
      }
    }
    return tag;
  }

  static String? _toiletTag(List<StationFacilityInfo> facilities) {
    final texts = facilities
        .where(_isToilet)
        .map((t) => '${t.name} ${t.description} ${t.floorFrom}'.toLowerCase())
        .toList();
    final insideGate = texts.any(
      (text) => _insideGateKeywords.any(text.contains),
    );
    final outsideGate = texts.any(
      (text) => _outsideGateKeywords.any(text.contains),
    );
    if (insideGate && outsideGate) return '개찰구 안/밖';
    if (insideGate) return '개찰구 안';
    if (outsideGate) return '개찰구 밖';
    return null;
  }

  static bool _isToilet(StationFacilityInfo f) =>
      f.type == 'TOILET' ||
      f.type == 'ACCESSIBLE_TOILET' ||
      f.name.contains('화장실');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '역정보',
          style: TextStyle(
            fontSize: 20,
            fontWeight: EasySubwayFontWeight.emphasis,
            color: EasySubwayAccessibleColors.text,
            letterSpacing: -0.3,
          ),
        ),
        for (final (index, group) in groups.indexed) ...[
          if (index == 0)
            const SizedBox(height: EasySubwaySpacing.md)
          else
            const Divider(
              height: EasySubwaySpacing.xl,
              color: EasySubwayAccessibleColors.borderSubtle,
            ),
          group,
        ],
      ],
    );
  }
}

/// 시설 유형 하나에 대해 이 역이 아는 상태.
/// 설치 기록이 있으면 항상 [exists]이고, 기록이 없을 때만 원천이 없다고
/// 확인한 유형이 [confirmedAbsent]가 된다. 그 밖에는 모르는 값이라 칸을 그리지 않는다.
enum _FacilityKnowledge { exists, confirmedAbsent, unknown }

/// 원천 시설 목록에서 한 유형을 찾는 규칙과 그 칸의 표시 정보.
class _FacilityKind {
  const _FacilityKind({
    required this.icon,
    required this.label,
    required this.types,
    required this.keywords,
    this.matchesDescription = false,
    this.absenceType,
  });

  final IconData icon;
  final String label;
  final List<String> types;
  final List<String> keywords;
  final bool matchesDescription;

  /// 원천이 NOT_EXISTS로 확인할 수 있는 유형 코드. 확인 수단이 없으면 null.
  final String? absenceType;

  bool matches(StationFacilityInfo facility) =>
      types.contains(facility.type) ||
      keywords.any(
        (keyword) =>
            facility.name.contains(keyword) ||
            (matchesDescription && facility.description.contains(keyword)),
      );

  _FacilityKnowledge knowledgeOf(
    StationFacilityInfo? installed,
    Set<String> absentTypes,
  ) {
    if (installed != null) return _FacilityKnowledge.exists;
    return absentTypes.contains(absenceType)
        ? _FacilityKnowledge.confirmedAbsent
        : _FacilityKnowledge.unknown;
  }
}

/// 소문자로 바꾼 설명에 [keywords] 중 하나가 있으면 [tag]를 붙이는 규칙.
class _TagRule {
  const _TagRule(this.keywords, this.tag);

  final List<String> keywords;
  final String tag;

  bool matches(String text) => keywords.any(text.contains);
}

class _FacilityTagItem extends StatelessWidget {
  const _FacilityTagItem({
    required this.icon,
    required this.label,
    required this.tag,
  });

  final IconData icon;
  final String label;
  final String tag;

  @override
  Widget build(BuildContext context) {
    // 상용 지하철 서비스처럼 `플랫폼 중앙` 한 줄 글자로 쓴다. 값을 상자로 감싸지 않는다.
    return Semantics(
      label: '$label $tag',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(icon, size: 20, color: EasySubwayAccessibleColors.secondaryText),
          const SizedBox(width: EasySubwaySpacing.sm),
          Flexible(
            child: Text(
              '$label $tag',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: EasySubwayFontWeight.regular,
                color: EasySubwayAccessibleColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmenityGridItem extends StatelessWidget {
  const _AmenityGridItem({
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
      child: _FacilityAvailabilityLabel(
        icon: icon,
        label: label,
        isAvailable: isAvailable,
      ),
    );
  }
}

class _AccessibleFacilityItem extends StatelessWidget {
  const _AccessibleFacilityItem({
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
    final content = _FacilityAvailabilityLabel(
      icon: icon,
      label: label,
      isAvailable: isAvailable,
    );

    return Semantics(
      container: true,
      label: '$label ${isAvailable ? '있음' : '없음'}',
      button: isAvailable && onTap != null,
      child: isAvailable && onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: content,
                  ),
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: content,
            ),
    );
  }
}

/// 역정보 한 묶음. 상자 없이 제목 아래 칸을 두 개씩 한 줄로 놓는다.
class _StationInfoGroup extends StatelessWidget {
  const _StationInfoGroup({required this.title, required this.items});

  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: EasySubwayFontWeight.emphasis,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        for (var index = 0; index < items.length; index += 2) ...[
          const SizedBox(height: EasySubwaySpacing.md),
          Row(
            children: [
              Expanded(child: items[index]),
              const SizedBox(width: EasySubwaySpacing.md),
              Expanded(
                child: index + 1 < items.length
                    ? items[index + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FacilityAvailabilityLabel extends StatelessWidget {
  const _FacilityAvailabilityLabel({
    required this.icon,
    required this.label,
    required this.isAvailable,
  });

  final IconData icon;
  final String label;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          child: ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: EasySubwayFontWeight.regular,
                color: isAvailable
                    ? EasySubwayAccessibleColors.text
                    : EasySubwayAccessibleColors.mutedText,
              ),
            ),
          ),
        ),
      ],
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

/// 상용 지하철 서비스와 같은 출구정보 래퍼 섹션.
class _StationExitInfoSection extends StatelessWidget {
  const _StationExitInfoSection({
    required this.station,
    required this.exits,
    required this.mapLauncher,
    this.mapPreviewBuilder,
  });

  final StationDetail station;
  final List<StationExitInfo> exits;
  final KakaoMapLauncher mapLauncher;
  final StationExitMapPreviewBuilder? mapPreviewBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '출구정보',
          style: TextStyle(
            fontSize: 20,
            fontWeight: EasySubwayFontWeight.emphasis,
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
          mapPreviewBuilder: mapPreviewBuilder,
        ),
      ],
    );
  }
}

/// 상용 지하철 서비스와 같은 하단 고정 액션바 (Sticky Bottom Bar).
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(
                    color: EasySubwayAccessibleColors.primary,
                    width: 1.5,
                  ),
                ),
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
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    child: const Text(
                      '출발',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: EasySubwayFontWeight.emphasis,
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
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.center,
                    child: const Text(
                      '도착',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: EasySubwayFontWeight.emphasis,
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
              child: _StationBottomBarOutlinedButton(
                buttonKey: const Key('stationTimetableButton'),
                icon: Icons.calendar_today,
                iconSize: 14,
                label: '전체 시간표',
                onTap: () => _openTimetable(context),
              ),
            ),
            const SizedBox(width: 8),
            // [🚆 첫차·막차]
            Expanded(
              flex: 9,
              child: _StationBottomBarOutlinedButton(
                buttonKey: const Key('stationDetailBottomFirstLastButton'),
                icon: Icons.train_outlined,
                iconSize: 15,
                label: '첫차·막차',
                onTap: () =>
                    _openTimetable(context, initialFilterFirstLast: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTimetable(
    BuildContext context, {
    bool initialFilterFirstLast = false,
  }) {
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
            initialFilterFirstLast: initialFilterFirstLast,
          ),
        ),
      ),
    );
  }
}

/// 하단 액션바의 흰색 아웃라인 버튼(아이콘 + 라벨).
///
/// 큰 글자에서 라벨이 버튼 폭을 넘으면 줄바꿈해 잘리지 않게 한다.
class _StationBottomBarOutlinedButton extends StatelessWidget {
  const _StationBottomBarOutlinedButton({
    required this.buttonKey,
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final double iconSize;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EasySubwayAccessibleColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: EasySubwayAccessibleColors.line),
      ),
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: EasySubwayAccessibleColors.text,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: EasySubwayFontWeight.regular,
                    color: EasySubwayAccessibleColors.text,
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
                      // 큰 글자에서 방면 이름과 첫차·막차가 한 줄에 들어가지 않으면 줄을 나눈다.
                      return Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            formatStationDirectionName(
                              direction.name,
                              previousStation: widget.previousStation,
                              nextStation: widget.nextStation,
                              directionIndex: i,
                            ),
                            style: TextStyle(
                              color: EasySubwayAccessibleColors.text,
                              fontSize: 14,
                              fontWeight: EasySubwayFontWeight.emphasis,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _StationDetailFirstLastBadge(
                                label: '첫차',
                                time: direction.firstDeparture.timeLabel,
                              ),
                              _StationDetailFirstLastBadge(
                                label: '막차',
                                time: direction.lastDeparture.timeLabel,
                              ),
                            ],
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
            fontWeight: EasySubwayFontWeight.regular,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          time,
          style: TextStyle(
            color: EasySubwayAccessibleColors.text,
            fontSize: 13,
            fontWeight: EasySubwayFontWeight.regular,
          ),
        ),
      ],
    );
  }
}
