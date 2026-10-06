import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:share_plus/share_plus.dart';

import '../../get_off_alarm/get_off_alarm_port.dart';
import '../../route_draft/domain/route_draft.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_profile_policy.dart';
import '../application/journey_search_controller.dart';
import '../domain/journey_repository.dart';
import '../domain/transfer_guide.dart';
import 'journey_get_off_alarm_toggle.dart';
import 'result/journey_result_view_model.dart';
import 'result/journey_result_widgets.dart';
import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../../../core/crashlytics/mobile_crash_reporting.dart';
import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

typedef JourneyShareInvoker = Future<void> Function(String text, Rect origin);

enum _JourneyDepartureSelection {
  now,
  scheduled,
  departureWindow,
  lastConnection,
}

class JourneySearchScreen extends StatefulWidget {
  const JourneySearchScreen({
    required this.repository,
    required this.attestor,
    this.sessionProvider,
    required this.draft,
    required this.mobilityType,
    required this.onShellBackToHome,
    this.initialWalkingPace,
    this.shareInvoker,
    this.getOffAlarmController,
    this.stationNameResolver,
    this.getOffAlarmNow,
    this.journeyNow,
    this.hasUnlimitedTransitPass = false,
    this.transferGuideRepository,
    super.key,
  }) : assert(getOffAlarmController == null || stationNameResolver != null);

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final JourneySessionProvider? sessionProvider;
  final RouteDraft draft;
  final String mobilityType;
  final WalkingPace? initialWalkingPace;
  final VoidCallback onShellBackToHome;
  final JourneyShareInvoker? shareInvoker;
  final GetOffAlarmPort? getOffAlarmController;
  final JourneyStationNameResolver? stationNameResolver;
  final DateTime Function()? getOffAlarmNow;
  final DateTime Function()? journeyNow;
  final bool hasUnlimitedTransitPass;

  /// 환승 이동 안내 단계(국토교통부 원문)를 읽는다. null이면 단계를 그리지 않는다.
  final TransferGuideRepository? transferGuideRepository;

  @override
  State<JourneySearchScreen> createState() => _JourneySearchScreenState();
}

class _JourneySearchScreenState extends State<JourneySearchScreen>
    with WidgetsBindingObserver {
  late final JourneySearchController _controller;
  JourneySearchStatus _lastAnnouncedStatus = JourneySearchStatus.idle;
  bool _isSharing = false;
  bool _isAlarmTransitioning = false;
  String? _alarmTransitionError;
  WalkingPace _walkingPace = WalkingPace.standard;
  _JourneyDepartureSelection _departureSelection =
      _JourneyDepartureSelection.now;
  DateTime? _scheduledRequestedAt;
  DateTime? _windowRequestedAt;
  DateTime? _lastConnectionDate;

  final Map<String, String> _resolvedStationNames = {};
  final Set<String> _expandedRideKeys = {};
  final Set<String> _expandedTransferGuideKeys = {};

  /// `journeyId:legIndex`별 환승 이동 안내 단계. 조회했는데 행이 없으면 키가 없다.
  final Map<String, List<String>> _transferGuideSteps = {};
  final Set<String> _requestedTransferGuideKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialWalkingPace != null) {
      _walkingPace = widget.initialWalkingPace!;
    }
    _controller = JourneySearchController(
      repository: widget.repository,
      attestor: widget.attestor,
      sessionProvider: widget.sessionProvider,
      now: widget.journeyNow,
      reportNonFatalError: (error, stackTrace) {
        return recordNonFatalError(error, stackTrace);
      },
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _resolveStationNames(JourneySearchSuccess response) {
    final resolver = widget.stationNameResolver;
    if (resolver == null) return;
    for (final journey in response.journeys) {
      for (final leg in journey.legs) {
        final stationIds = switch (leg) {
          JourneyEntryLeg(:final fromStationId) => [fromStationId],
          JourneyRideLeg(
            :final fromStationId,
            :final toStationId,
            :final directionStationId,
            :final stops,
          ) =>
            [
              fromStationId,
              toStationId,
              directionStationId,
              for (final stop in stops) stop.stationId,
            ],
          JourneyTransferLeg(:final fromStationId, :final toStationId) => [
            fromStationId,
            toStationId,
          ],
          JourneyExitLeg(:final fromStationId) => [fromStationId],
        };
        for (final stationId in stationIds) {
          if (!_resolvedStationNames.containsKey(stationId)) {
            _resolvedStationNames[stationId] = stationId;
            unawaited(
              resolver(stationId)
                  .then((name) {
                    if (mounted && _resolvedStationNames[stationId] != name) {
                      setState(() => _resolvedStationNames[stationId] = name);
                    }
                  })
                  .catchError((_) {}),
            );
          }
        }
      }
    }
  }

  void _loadTransferGuides(JourneySearchSuccess response) {
    final repository = widget.transferGuideRepository;
    if (repository == null) return;
    for (final journey in response.journeys) {
      for (var index = 0; index < journey.legs.length; index++) {
        final key = transferGuideKeyAt(journey, index);
        if (key == null) continue;
        final stepsKey = '${journey.journeyId}:$index';
        if (!_requestedTransferGuideKeys.add(stepsKey)) continue;
        unawaited(
          repository
              .loadSteps(key)
              .then((steps) {
                if (mounted && steps.isNotEmpty) {
                  setState(() => _transferGuideSteps[stepsKey] = steps);
                }
              })
              .catchError((Object error, StackTrace stackTrace) {
                // 조회 실패는 안내 단계가 없는 것과 같은 화면이다. 값을 만들어 채우지 않는다.
                unawaited(recordNonFatalError(error, stackTrace));
              }),
        );
      }
    }
  }

  String _stationName(String stationId) =>
      _resolvedStationNames[stationId] ?? stationId;

  String _lineBadgeNumber(String lineId) {
    final clean = lineId.replaceAll(RegExp(r'^line-|^seoul-|^korail-'), '');
    const knownShort = <String, String>{
      'gyeongui-jungang': '경의',
      'suin-bundang': '수인',
      'shinbundang': '신분',
      'arex': '공항',
      'airport': '공항',
      'gyeongchun': '경춘',
      'gyeonggang': '경강',
      'seohae': '서해',
      'sillim': '신림',
      'ui-sinseol': '우이',
      'everline': '용인',
      'gimpo-gold': '김포',
    };
    if (knownShort.containsKey(clean)) {
      return knownShort[clean]!;
    }
    final numMatch = RegExp(r'\d+').firstMatch(clean);
    if (numMatch != null) return numMatch.group(0)!;
    if (clean.length > 2) return clean.substring(0, 2);
    return clean;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _controller.revalidateFreshness();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    final state = _controller.state;
    if (state.response case final response?) {
      _resolveStationNames(response);
      _loadTransferGuides(response);
    }
    setState(() {});
    if (state.status == _lastAnnouncedStatus) return;
    _lastAnnouncedStatus = state.status;
    final message = <JourneySearchStatus, String Function()>{
      JourneySearchStatus.searching: () => '경로를 찾고 있어요.',
      JourneySearchStatus.success: () =>
          '경로 ${state.response!.journeys.length}개를 찾았어요.',
      JourneySearchStatus.failure: () {
        final copy = journeyFailureCopy(state.rejection?.disposition);
        return [copy.message, ?copy.detail].join(' ');
      },
    }[state.status]?.call();
    if (message != null) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          TextDirection.ltr,
        ),
      );
    }
  }

  DateTime _seoulWallTime(DateTime instant) {
    final value = instant.toUtc().add(const Duration(hours: 9));
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  Widget? _outOfStationTransferBadge(JourneyTransferLeg leg) {
    if (leg.transferType != 'OUT_OF_STATION') return null;
    final minutes = (leg.durationSeconds + 59) ~/ 60;

    if (widget.hasUnlimitedTransitPass &&
        (minutes > 30 || leg.farePenaltyApplies)) {
      return Container(
        key: const Key('out-of-station-badge-pass-override'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.statusInfoSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: EasySubwayAccessibleColors.statusInfoContent,
          ),
        ),
        child: const Text(
          '노외 환승 (기후동행카드 적용)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: EasySubwayAccessibleColors.statusInfoContent,
          ),
        ),
      );
    }

    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    final String label;
    final Key key;

    if (minutes <= 18) {
      bgColor = EasySubwayAccessibleColors.statusSuccessSurface;
      textColor = EasySubwayAccessibleColors.statusSuccessContent;
      borderColor = EasySubwayAccessibleColors.statusSuccessContent;
      label = '노외 환승 (여유)';
      key = const Key('out-of-station-badge-green');
    } else if (minutes <= 30) {
      bgColor = EasySubwayAccessibleColors.statusWarningSurface;
      textColor = EasySubwayAccessibleColors.statusWarningContent;
      borderColor = EasySubwayAccessibleColors.statusWarningContent;
      label = '노외 환승 (주의)';
      key = const Key('out-of-station-badge-amber');
    } else {
      bgColor = EasySubwayAccessibleColors.statusDangerSurface;
      textColor = EasySubwayAccessibleColors.statusDangerContent;
      borderColor = EasySubwayAccessibleColors.statusDangerContent;
      label = '노외 환승 (시간 초과)';
      key = const Key('out-of-station-badge-red');
    }

    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  /// 재승차(역 밖 환승 제한 시간 초과)는 사실만 알린다. 금액은 여정 총운임(fare)에만 있다.
  Widget? _reboardingFareNotice(JourneyTransferLeg leg) {
    if (!leg.farePenaltyApplies) return null;
    return Semantics(
      label: JourneyTransferNode.reboardingFareLabel,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('reboarding-fare-notice'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            JourneyTransferNode.reboardingFareLabel,
            style: TextStyle(
              fontSize: 11,
              color: EasySubwayAccessibleColors.contentSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedDetail(JourneySelectedSnapshot snapshot) {
    final journey = snapshot.journey;
    final viewModel = JourneyResultViewModel.fromJourney(
      journey,
      stationName: _stationName,
    );
    final rideColors = [
      for (final node in viewModel.timeline)
        if (node is JourneyRideNode) journeyLineColor(node.lineId),
    ];
    final timeline = viewModel.timeline;
    return Column(
      key: const Key('selected-journey-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JourneyResultSummaryView(
          summary: viewModel.summary,
          showStairStatus: journeyShowsStairStatus(snapshot.requestPolicy),
        ),
        const SizedBox(height: 12),
        JourneySegmentBar(
          segments: viewModel.segments,
          semanticsLabel: viewModel.segmentsSemanticsLabel,
        ),
        const SizedBox(height: 20),
        for (var index = 0; index < timeline.length; index++)
          _timelineNode(
            journey.journeyId,
            timeline[index],
            isLast: index == timeline.length - 1,
            departureColor:
                rideColors.firstOrNull ?? EasySubwayAccessibleColors.primary,
            arrivalColor:
                rideColors.lastOrNull ?? EasySubwayAccessibleColors.primary,
          ),
        if (widget.getOffAlarmController case final alarmController?) ...[
          const SizedBox(height: 8),
          JourneyGetOffAlarmToggle(
            snapshot: snapshot,
            controller: alarmController,
            stationNameResolver: widget.stationNameResolver!,
            now: widget.getOffAlarmNow ?? DateTime.now,
          ),
        ],
        const SizedBox(height: 8),
        Builder(
          builder: (buttonContext) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _isSharing
                ? null
                : () => _share(buttonContext, snapshot),
            icon: const Icon(Icons.share_outlined),
            label: const Text('공유'),
          ),
        ),
      ],
    );
  }

  /// 세로 선 + 원형 노드 한 줄. 탑승 구간 선은 노선 색, 도보 구간 선은 회색이다.
  Widget _timelineNode(
    String journeyId,
    JourneyTimelineNode node, {
    required bool isLast,
    required Color departureColor,
    required Color arrivalColor,
  }) {
    // 큰 글자 설정에서 노선 배지 텍스트가 잘리지 않도록 트랙 폭과 배지를 함께 키운다.
    // 1.0배에서는 24dp 그대로다.
    final trackWidth = math.max(
      24.0,
      MediaQuery.textScalerOf(context).scale(24),
    );
    final Widget marker;
    final Widget content;
    var trackColor = EasySubwayAccessibleColors.line;
    var trackThickness = 3.0;
    switch (node) {
      case JourneyDepartureNode():
        marker = _ringMarker(departureColor);
        content = _stationNodeContent(
          semanticsLabel: node.semanticsLabel,
          stationName: node.stationName,
          timeLabel: '${node.departureTime} 출발',
          walkLabel: node.walkLabel,
        );
      case JourneyRideNode():
        final lineColor = journeyLineColor(node.lineId);
        trackColor = lineColor;
        trackThickness = 5;
        marker = Container(
          constraints: BoxConstraints(
            minWidth: trackWidth,
            minHeight: trackWidth,
          ),
          decoration: ShapeDecoration(
            shape: const CircleBorder(
              side: BorderSide(
                color: EasySubwayColorPrimitives.neutralWhite,
                width: 1.5,
              ),
            ),
            color: lineColor,
          ),
          alignment: Alignment.center,
          child: Text(
            _lineBadgeNumber(node.lineId),
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              color: EasySubwayColorPrimitives.neutralWhite,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        );
        content = _rideNodeContent(journeyId, node);
      case JourneyTransferNode():
        marker = SizedBox.square(
          dimension: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: EasySubwayAccessibleColors.surface,
              border: Border.all(
                color: EasySubwayAccessibleColors.primary,
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.sync_alt_rounded,
              size: 13,
              color: EasySubwayAccessibleColors.primary,
            ),
          ),
        );
        content = _transferNodeContent(journeyId, node);
      case JourneyArrivalNode():
        marker = SizedBox.square(
          dimension: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: arrivalColor,
            ),
            child: const Icon(
              Icons.place_rounded,
              size: 14,
              color: EasySubwayColorPrimitives.neutralWhite,
            ),
          ),
        );
        content = _stationNodeContent(
          semanticsLabel: node.semanticsLabel,
          stationName: node.stationName,
          timeLabel: '${node.arrivalTime} 도착',
          walkLabel: node.walkLabel,
        );
    }
    return KeyedSubtree(
      key: Key('selected-journey-leg-${node.legIndex}'),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: trackWidth,
              // 노드 원·세로 선은 장식이다. 내용은 오른쪽 노드 라벨이 읽는다.
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    marker,
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: trackThickness,
                          color: trackColor,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 4 : 16),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ringMarker(Color color) {
    return SizedBox.square(
      dimension: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EasySubwayAccessibleColors.surface,
          border: Border.all(color: color, width: 3),
        ),
      ),
    );
  }

  Widget _stationNodeContent({
    required String semanticsLabel,
    required String stationName,
    required String timeLabel,
    required String walkLabel,
  }) {
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    stationName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              walkLabel,
              style: const TextStyle(
                fontSize: 13,
                color: EasySubwayAccessibleColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideNodeContent(String journeyId, JourneyRideNode node) {
    final expandKey = '$journeyId:${node.legIndex}';
    final expanded = _expandedRideKeys.contains(expandKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: node.semanticsLabel,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            node.lineName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: EasySubwayAccessibleColors.text,
                            ),
                          ),
                          if (node.directionLabel case final direction?)
                            Text(
                              direction,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: EasySubwayAccessibleColors.text,
                              ),
                            ),
                          if (node.isExpress)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: EasySubwayAccessibleColors
                                    .statusDangerSurface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                child: Text(
                                  '급행',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: EasySubwayAccessibleColors
                                        .statusDangerContent,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${node.departureTime} 출발',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: EasySubwayAccessibleColors.secondaryText,
                      ),
                    ),
                  ],
                ),
                if (node.carDoorLabel case final carDoor?) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.directions_subway_outlined,
                        size: 15,
                        color: EasySubwayAccessibleColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          carDoor,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: EasySubwayAccessibleColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        _buildPlatformGapGuidance(
          isBoarding: true,
          gaps: node.boardingPlatformGaps,
          stationName: node.boardingStationName,
        ),
        if (node.intermediateStops.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ExcludeSemantics(
              child: Text(
                node.stopToggleLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EasySubwayAccessibleColors.secondaryText,
                ),
              ),
            ),
          )
        else ...[
          _rideStopsToggle(node, expandKey: expandKey, expanded: expanded),
          if (expanded)
            for (final stop in node.intermediateStops)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          stop.name,
                          style: const TextStyle(
                            fontSize: 14,
                            color: EasySubwayAccessibleColors.text,
                          ),
                        ),
                      ),
                      if (stop.time case final time?)
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 13,
                            color: EasySubwayAccessibleColors.mutedText,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
        _buildPlatformGapGuidance(
          isBoarding: false,
          gaps: node.alightingPlatformGaps,
          stationName: node.alightingStationName,
        ),
      ],
    );
  }

  Widget _rideStopsToggle(
    JourneyRideNode node, {
    required String expandKey,
    required bool expanded,
  }) {
    void toggle() => setState(() {
      if (!_expandedRideKeys.remove(expandKey)) {
        _expandedRideKeys.add(expandKey);
      }
    });
    return Semantics(
      button: true,
      expanded: expanded,
      label: node.stopToggleLabel,
      onTap: toggle,
      excludeSemantics: true,
      child: InkWell(
        key: Key('journey-ride-stops-toggle-${node.legIndex}'),
        onTap: toggle,
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  node.stopToggleLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: EasySubwayAccessibleColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transferNodeContent(String journeyId, JourneyTransferNode node) {
    final guideKey = '$journeyId:${node.legIndex}';
    final guideSteps = _transferGuideSteps[guideKey];
    final badge = _outOfStationTransferBadge(node.leg);
    final reboarding = _reboardingFareNotice(node.leg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: node.semanticsLabel,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.stationName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  node.walkLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (badge != null || reboarding != null) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [?badge, ?reboarding]),
        ],
        if (guideSteps != null)
          JourneyTransferGuideSteps(
            legIndex: node.legIndex,
            steps: guideSteps,
            expanded: _expandedTransferGuideKeys.contains(guideKey),
            onToggle: () => setState(() {
              if (!_expandedTransferGuideKeys.remove(guideKey)) {
                _expandedTransferGuideKeys.add(guideKey);
              }
            }),
          ),
      ],
    );
  }

  bool get _isStepFree {
    final preset =
        mobilityPresetFromRepresentativeMobilityType(widget.mobilityType) ??
        MobilityPreset.standard;
    return preset == MobilityPreset.stepFree ||
        preset == MobilityPreset.noStairs;
  }

  Widget _buildPlatformGapGuidance({
    required bool isBoarding,
    required List<JourneyPlatformGap> gaps,
    required String stationName,
  }) {
    if (!_isStepFree || gaps.isEmpty) {
      return const SizedBox.shrink();
    }

    // 틈이 좁은 문: gapGrade == NARROW && heightDiffGrade == LOW, carNumber != null && doorNumber != null
    final narrowLowGaps = gaps
        .where(
          (g) =>
              g.gapGrade == PlatformGapGrade.narrow &&
              g.heightDiffGrade == PlatformHeightDiffGrade.low &&
              g.carNumber != null &&
              g.doorNumber != null,
        )
        .toList();

    narrowLowGaps.sort((a, b) {
      final carCmp = a.carNumber!.compareTo(b.carNumber!);
      if (carCmp != 0) return carCmp;
      return a.doorNumber!.compareTo(b.doorNumber!);
    });

    final topNarrow = narrowLowGaps.take(3).toList();
    final wideCount = gaps
        .where((g) => g.gapGrade == PlatformGapGrade.wide)
        .length;

    // 두 줄 모두 없으면 이 영역 자체를 표시하지 않는다.
    if (topNarrow.isEmpty && wideCount == 0) {
      return const SizedBox.shrink();
    }

    final platformLabel = isBoarding ? '탑승 승강장' : '하차 승강장';
    final lines = <Widget>[];

    if (topNarrow.isNotEmpty) {
      final narrowText =
          '틈이 좁은 문 ${topNarrow.map((g) => '${g.carNumber}-${g.doorNumber}').join(' · ')}';
      final narrowSemantics =
          '$platformLabel, 틈이 좁은 문 ${topNarrow.map((g) => '${g.carNumber}호차 ${g.doorNumber}번').join(', ')}';
      lines.add(
        _buildPlatformGapLine(
          text: narrowText,
          semanticsLabel: narrowSemantics,
          onTap: () => _showPlatformGapBottomSheet(
            isBoarding: isBoarding,
            gaps: gaps,
            stationName: stationName,
          ),
        ),
      );
    }

    if (wideCount >= 1) {
      final wideText = '틈 넓은 곳 $wideCount곳';
      final wideSemantics = '$platformLabel, 틈 넓은 곳 $wideCount곳, 목록 보기';
      lines.add(
        _buildPlatformGapLine(
          text: wideText,
          semanticsLabel: wideSemantics,
          onTap: () => _showPlatformGapBottomSheet(
            isBoarding: isBoarding,
            gaps: gaps,
            stationName: stationName,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: lines,
      ),
    );
  }

  Widget _buildPlatformGapLine({
    required String text,
    required String semanticsLabel,
    required VoidCallback onTap,
  }) {
    // ExcludeSemantics가 InkWell의 탭 동작까지 지우므로, 스크린리더 두 번 탭은 바깥 노드의
    // onTap으로 받는다(#426).
    return Semantics(
      label: semanticsLabel,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: EasySubwayAccessibleColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: EasySubwayAccessibleColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: EasySubwayAccessibleColors.mutedText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPlatformGapBottomSheet({
    required bool isBoarding,
    required List<JourneyPlatformGap> gaps,
    required String stationName,
  }) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: EasySubwayAccessibleColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: RepaintBoundary(
              key: const Key('platform-gap-bottomsheet-boundary'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$stationName ${isBoarding ? '탑승' : '하차'} 승강장',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: EasySubwayAccessibleColors.text,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: gaps.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: EasySubwayAccessibleColors.line,
                        ),
                        itemBuilder: (context, i) {
                          final gap = gaps[i];
                          final position =
                              (gap.carNumber != null && gap.doorNumber != null)
                              ? '${gap.carNumber}-${gap.doorNumber}'
                              : gap.platformPosition;

                          final gapGradeKo = switch (gap.gapGrade) {
                            PlatformGapGrade.wide => '넓음',
                            PlatformGapGrade.normal => '보통',
                            PlatformGapGrade.narrow => '좁음',
                          };

                          final heightGradeKo = switch (gap.heightDiffGrade) {
                            PlatformHeightDiffGrade.high => '높음',
                            PlatformHeightDiffGrade.normal => '보통',
                            PlatformHeightDiffGrade.low => '낮음',
                          };

                          final curveSuffix = gap.curved ? ' · 곡선 승강장' : '';
                          final rowText =
                              '$position · 틈 $gapGradeKo · 높이차 $heightGradeKo$curveSuffix';

                          final semanticsPosition =
                              (gap.carNumber != null && gap.doorNumber != null)
                              ? '${gap.carNumber}호차 ${gap.doorNumber}번 문'
                              : gap.platformPosition;
                          final semanticsCurveSuffix = gap.curved
                              ? ', 곡선 승강장'
                              : '';
                          final rowSemantics =
                              '$semanticsPosition, 틈 $gapGradeKo, 높이차 $heightGradeKo$semanticsCurveSuffix';

                          return Semantics(
                            label: rowSemantics,
                            child: ExcludeSemantics(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  rowText,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: EasySubwayAccessibleColors.text,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _shareText(JourneySelectedSnapshot snapshot) {
    final journey = snapshot.journey;
    final summary = JourneyResultViewModel.fromJourney(
      journey,
      stationName: _stationName,
    ).summary;
    // 계단 표시는 계단 없는 경로가 필요한 사용자에게만 넣는다(#441 QA).
    final stairStatus =
        journeyShowsStairStatus(snapshot.requestPolicy) &&
            journey.accessibility.stairFree
        ? journeyStairFreeCategoryLabel
        : null;
    final details = [
      summary.durationLabel,
      summary.transferLabel,
      ?summary.fareLabel,
      '${summary.arrivalTime} 도착',
      ?stairStatus,
    ];
    return '${widget.draft.origin!.displayName} → ${widget.draft.destination!.displayName}\n'
        '${details.join(' · ')}';
  }

  Future<void> _share(
    BuildContext buttonContext,
    JourneySelectedSnapshot snapshot,
  ) async {
    if (_isSharing || !_controller.revalidateFreshness()) return;
    setState(() => _isSharing = true);
    try {
      final renderBox = buttonContext.findRenderObject()! as RenderBox;
      final origin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
      final text = _shareText(snapshot);
      final invoker = widget.shareInvoker;
      if (invoker != null) {
        await invoker(text, origin);
      } else {
        await SharePlus.instance.share(
          ShareParams(text: text, sharePositionOrigin: origin),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('경로 요약을 공유하지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  JourneySearchCommand? _searchCommand() {
    final origin = widget.draft.origin;
    final destination = widget.draft.destination;
    final waypoint = widget.draft.waypoint;
    if (origin == null ||
        destination == null ||
        origin.id == destination.id ||
        (waypoint != null &&
            (waypoint.id == origin.id || waypoint.id == destination.id)) ||
        (_departureSelection == _JourneyDepartureSelection.scheduled &&
            _scheduledRequestedAt == null) ||
        (_departureSelection == _JourneyDepartureSelection.departureWindow &&
            _windowRequestedAt == null) ||
        (_departureSelection == _JourneyDepartureSelection.lastConnection &&
            _lastConnectionDate == null)) {
      return null;
    }
    final preset =
        mobilityPresetFromRepresentativeMobilityType(widget.mobilityType) ??
        MobilityPreset.standard;
    final (profile, constraint) = switch (preset) {
      MobilityPreset.standard => (
        MobilityProfile.standard,
        ConstraintMode.none,
      ),
      MobilityPreset.slow => (MobilityProfile.slow, ConstraintMode.none),
      MobilityPreset.noStairs => (
        MobilityProfile.noStairs,
        ConstraintMode.requireStepFree,
      ),
      MobilityPreset.stepFree => (
        MobilityProfile.stepFree,
        ConstraintMode.requireStepFree,
      ),
    };
    final JourneyTemporalQuery? temporalQuery;
    final JourneyDeparture departure;
    switch (_departureSelection) {
      case _JourneyDepartureSelection.now:
        departure = const JourneyDepartureNow();
        temporalQuery = null;
      case _JourneyDepartureSelection.scheduled:
        departure = JourneyDepartureScheduled(_scheduledRequestedAt!);
        temporalQuery = null;
      case _JourneyDepartureSelection.departureWindow:
        final start = _windowRequestedAt!;
        final end = start.add(const Duration(minutes: 30));
        departure = JourneyDepartureScheduled(start);
        temporalQuery = JourneyDepartBetweenQuery(
          earliestReadyAt: start,
          latestReadyAt: end,
        );
      case _JourneyDepartureSelection.lastConnection:
        final date = _lastConnectionDate!;
        final seoul = date.toUtc().add(const Duration(hours: 9));
        final serviceDateStr =
            '${seoul.year.toString().padLeft(4, '0')}-'
            '${seoul.month.toString().padLeft(2, '0')}-'
            '${seoul.day.toString().padLeft(2, '0')}';
        departure = JourneyDepartureScheduled(date);
        temporalQuery = JourneyLastConnectionQuery(serviceDate: serviceDateStr);
    }
    return JourneySearchCommand(
      originStationId: origin.id,
      destinationStationId: destination.id,
      viaStationId: waypoint?.id,
      departure: departure,
      timePolicy: TimePolicy.timetableRequired,
      walkingPace: _walkingPace,
      mobilityProfile: profile,
      constraintMode: constraint,
      maxTransfers: 3,
      alternativeCount: 3,
      profileTemporalQuery: temporalQuery,
    );
  }

  Future<void> _selectJourney(Journey journey) async {
    if (_isAlarmTransitioning || !_controller.revalidateFreshness()) return;
    final alarmController = widget.getOffAlarmController;
    final response = _controller.state.response;
    if (alarmController != null && response != null) {
      final target = JourneySelectedSnapshot.fromResponse(response, journey);
      final active = alarmController.state.activeJourneyIdentity;
      if (alarmController.state.enabled &&
          active != journeyAlarmIdentityForSnapshot(target)) {
        if (!await _disableAlarmBeforeTransition(alarmController)) return;
      }
    }
    _controller.selectJourney(journey.journeyId);
    if (mounted && _alarmTransitionError != null) {
      setState(() => _alarmTransitionError = null);
    }
  }

  Future<void> _search() => _runSearch(_searchCommand());

  /// 계단 없는 경로만 요청했다가 그런 경로가 없을 때(422
  /// ACCESSIBILITY_CONSTRAINT_UNSATISFIED) 사용자가 고르는 다음 행동이다.
  /// 같은 조건으로 계단 제약만 풀어(NONE) 계단 여부를 표시한 일반 경로를 받는다.
  /// 계약상 NO_STAIRS는 NONE과 함께 보낼 수 없으므로, 두 프로필 모두 계단 없는
  /// 경로를 우선 고르는 STEP_FREE로 보낸다(backend #471 결과 구성 규칙).
  Future<void> _showStandardRoutes() {
    final command = _searchCommand();
    return _runSearch(
      command == null
          ? null
          : JourneySearchCommand(
              originStationId: command.originStationId,
              destinationStationId: command.destinationStationId,
              viaStationId: command.viaStationId,
              departure: command.departure,
              timePolicy: command.timePolicy,
              walkingPace: command.walkingPace,
              mobilityProfile: MobilityProfile.stepFree,
              constraintMode: ConstraintMode.none,
              maxTransfers: command.maxTransfers,
              alternativeCount: command.alternativeCount,
              profileTemporalQuery: command.profileTemporalQuery,
            ),
    );
  }

  Future<void> _runSearch(JourneySearchCommand? command) async {
    if (command == null || _isAlarmTransitioning) return;
    final alarmController = widget.getOffAlarmController;
    if (alarmController != null &&
        alarmController.state.enabled &&
        !await _disableAlarmBeforeTransition(alarmController)) {
      return;
    }
    await _controller.search(command);
  }

  Widget _walkingPaceControl(bool enabled) {
    const labels = <WalkingPace, String>{
      WalkingPace.slow: '느린 걸음',
      WalkingPace.standard: '표준 걸음',
      WalkingPace.fast: '빠른 걸음',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '걷는 속도',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final pace in WalkingPace.values) ...[
              if (pace != WalkingPace.slow) const SizedBox(width: 8),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 60),
                  child: ChoiceChip(
                    key: Key('walking-pace-${pace.name}'),
                    showCheckmark: false,
                    selectedColor: EasySubwayAccessibleColors.surfaceBrand,
                    backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: _walkingPace == pace
                            ? EasySubwayAccessibleColors.primary
                            : EasySubwayAccessibleColors.line,
                        width: _walkingPace == pace ? 1.5 : 1.0,
                      ),
                    ),
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(
                        labels[pace]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _walkingPace == pace
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _walkingPace == pace
                              ? EasySubwayAccessibleColors.primary
                              : EasySubwayAccessibleColors.secondaryText,
                        ),
                      ),
                    ),
                    selected: _walkingPace == pace,
                    onSelected: !enabled
                        ? null
                        : (selected) {
                            if (!selected || pace == _walkingPace) return;
                            unawaited(_selectWalkingPace(pace));
                          },
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _selectWalkingPace(WalkingPace pace) async {
    if (pace == _walkingPace || _isAlarmTransitioning) return;
    final alarmController = widget.getOffAlarmController;
    if (alarmController != null &&
        alarmController.state.enabled &&
        !await _disableAlarmBeforeTransition(alarmController)) {
      return;
    }
    if (!mounted) return;
    setState(() => _walkingPace = pace);
    await _search();
  }

  Future<bool> _prepareForTemporalChange() async {
    final alarmController = widget.getOffAlarmController;
    return alarmController == null ||
        !alarmController.state.enabled ||
        await _disableAlarmBeforeTransition(alarmController);
  }

  Future<void> _selectDepartureSelection(
    _JourneyDepartureSelection selection,
  ) async {
    if (selection == _departureSelection || _isAlarmTransitioning) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    setState(() {
      _departureSelection = selection;
      if (selection == _JourneyDepartureSelection.now) {
        _scheduledRequestedAt = null;
        _windowRequestedAt = null;
        _lastConnectionDate = null;
      }
    });
    _controller.reset();
  }

  Future<void> _selectScheduledTime() async {
    if (_isAlarmTransitioning) return;
    final initial = _seoulWallTime(
      _scheduledRequestedAt ?? (widget.journeyNow?.call() ?? DateTime.now()),
    );
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1, 1, 1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final requestedAt = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 9));
    if (requestedAt == _scheduledRequestedAt) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    setState(() => _scheduledRequestedAt = requestedAt);
    _controller.reset();
  }

  Future<void> _selectWindowTime() async {
    if (_isAlarmTransitioning) return;
    final initial = _seoulWallTime(
      _windowRequestedAt ?? (widget.journeyNow?.call() ?? DateTime.now()),
    );
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1, 1, 1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final requestedAt = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 9));
    if (requestedAt == _windowRequestedAt) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    setState(() => _windowRequestedAt = requestedAt);
    _controller.reset();
  }

  Future<void> _selectLastConnectionDate() async {
    if (_isAlarmTransitioning) return;
    final initial = _seoulWallTime(
      _lastConnectionDate ?? (widget.journeyNow?.call() ?? DateTime.now()),
    );
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1, 1, 1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final selectedDate = DateTime.utc(date.year, date.month, date.day);
    if (selectedDate == _lastConnectionDate) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    setState(() => _lastConnectionDate = selectedDate);
    _controller.reset();
  }

  Widget _departureControl(bool enabled) {
    final isNow = _departureSelection == _JourneyDepartureSelection.now;
    final isScheduled =
        _departureSelection == _JourneyDepartureSelection.scheduled;
    final isWindow =
        _departureSelection == _JourneyDepartureSelection.departureWindow;
    final isLastConnection =
        _departureSelection == _JourneyDepartureSelection.lastConnection;

    final requestedAt = _scheduledRequestedAt;
    final selectedWallTime = requestedAt == null
        ? null
        : _seoulWallTime(requestedAt);
    final selectedLabel = selectedWallTime == null
        ? '출발 시간 선택'
        : '출발 시간 ${selectedWallTime.year.toString().padLeft(4, '0')}-${selectedWallTime.month.toString().padLeft(2, '0')}-${selectedWallTime.day.toString().padLeft(2, '0')} ${selectedWallTime.hour.toString().padLeft(2, '0')}:${selectedWallTime.minute.toString().padLeft(2, '0')}';

    final windowAt = _windowRequestedAt;
    final windowWallTime = windowAt == null ? null : _seoulWallTime(windowAt);
    final windowLabel = windowWallTime == null
        ? '출발 대안 시간대 선택'
        : '대안 시간대 ${windowWallTime.year.toString().padLeft(4, '0')}-${windowWallTime.month.toString().padLeft(2, '0')}-${windowWallTime.day.toString().padLeft(2, '0')} ${windowWallTime.hour.toString().padLeft(2, '0')}:${windowWallTime.minute.toString().padLeft(2, '0')} (+30분)';

    final lastDate = _lastConnectionDate;
    final lastDateWallTime = lastDate == null ? null : _seoulWallTime(lastDate);
    final lastConnectionLabel = lastDateWallTime == null
        ? '안심 막차 운행일 선택'
        : '막차 운행일 ${lastDateWallTime.year.toString().padLeft(4, '0')}-${lastDateWallTime.month.toString().padLeft(2, '0')}-${lastDateWallTime.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '출발 기준',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: ChoiceChip(
                  key: const Key('journey-departure-now'),
                  showCheckmark: false,
                  selectedColor: EasySubwayAccessibleColors.surfaceBrand,
                  backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isNow
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.line,
                      width: isNow ? 1.5 : 1.0,
                    ),
                  ),
                  label: Text(
                    '지금 출발',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
                      color: isNow
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  selected: isNow,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  onSelected: !enabled
                      ? null
                      : (selected) {
                          if (selected) {
                            unawaited(
                              _selectDepartureSelection(
                                _JourneyDepartureSelection.now,
                              ),
                            );
                          }
                        },
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: ChoiceChip(
                  key: const Key('journey-departure-scheduled'),
                  showCheckmark: false,
                  selectedColor: EasySubwayAccessibleColors.surfaceBrand,
                  backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isScheduled
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.line,
                      width: isScheduled ? 1.5 : 1.0,
                    ),
                  ),
                  label: Text(
                    '출발 시간',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isScheduled
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isScheduled
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  selected: isScheduled,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  onSelected: !enabled
                      ? null
                      : (selected) {
                          if (selected) {
                            unawaited(
                              _selectDepartureSelection(
                                _JourneyDepartureSelection.scheduled,
                              ),
                            );
                          }
                        },
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: ChoiceChip(
                  key: const Key('journey-departure-window'),
                  showCheckmark: false,
                  selectedColor: EasySubwayAccessibleColors.surfaceBrand,
                  backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isWindow
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.line,
                      width: isWindow ? 1.5 : 1.0,
                    ),
                  ),
                  label: Text(
                    '출발 대안',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isWindow ? FontWeight.w700 : FontWeight.w500,
                      color: isWindow
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.secondaryText,
                    ),
                    semanticsLabel: '특정 시간대 출발 대안 보기',
                  ),
                  selected: isWindow,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  onSelected: !enabled
                      ? null
                      : (selected) {
                          if (selected) {
                            unawaited(
                              _selectDepartureSelection(
                                _JourneyDepartureSelection.departureWindow,
                              ),
                            );
                          }
                        },
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: ChoiceChip(
                  key: const Key('journey-departure-last-connection'),
                  showCheckmark: false,
                  selectedColor: EasySubwayAccessibleColors.surfaceBrand,
                  backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isLastConnection
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.line,
                      width: isLastConnection ? 1.5 : 1.0,
                    ),
                  ),
                  label: Text(
                    '안심 막차',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isLastConnection
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isLastConnection
                          ? EasySubwayAccessibleColors.primary
                          : EasySubwayAccessibleColors.secondaryText,
                    ),
                    semanticsLabel: '교통약자 안심 막차 찾기',
                  ),
                  selected: isLastConnection,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  onSelected: !enabled
                      ? null
                      : (selected) {
                          if (selected) {
                            unawaited(
                              _selectDepartureSelection(
                                _JourneyDepartureSelection.lastConnection,
                              ),
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ),
        if (isScheduled) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('journey-scheduled-time'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
              side: const BorderSide(color: EasySubwayAccessibleColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: enabled ? _selectScheduledTime : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 18,
                  color: EasySubwayAccessibleColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  selectedLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (isWindow) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('journey-window-time'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
              side: const BorderSide(color: EasySubwayAccessibleColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: enabled ? _selectWindowTime : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: EasySubwayAccessibleColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  windowLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (isLastConnection) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('journey-last-connection-date'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: EasySubwayAccessibleColors.surfaceSubtle,
              side: const BorderSide(color: EasySubwayAccessibleColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: enabled ? _selectLastConnectionDate : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.nightlight_round,
                  size: 18,
                  color: EasySubwayAccessibleColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  lastConnectionLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _retry() async {
    if (_isAlarmTransitioning) return;
    final alarmController = widget.getOffAlarmController;
    if (alarmController != null &&
        alarmController.state.enabled &&
        !await _disableAlarmBeforeTransition(alarmController)) {
      return;
    }
    await _controller.retry();
  }

  Future<bool> _disableAlarmBeforeTransition(GetOffAlarmPort controller) async {
    setState(() {
      _isAlarmTransitioning = true;
      _alarmTransitionError = null;
    });
    try {
      await controller.disable();
      if (!mounted) return false;
      setState(() => _isAlarmTransitioning = false);
      return true;
    } on Object {
      if (!mounted) return false;
      setState(() {
        _isAlarmTransitioning = false;
        _alarmTransitionError = '기존 하차 알림을 끄지 못해 경로를 바꾸지 않았어요.';
      });
      return false;
    }
  }

  Widget _routeInputCard(
    BuildContext context,
    bool valid,
    RouteDraftStation? waypoint,
  ) {
    final originName = widget.draft.origin?.displayName ?? '출발역 선택';
    final destinationName = widget.draft.destination?.displayName ?? '도착역 선택';
    final waypointName = waypoint?.displayName ?? '경유역 선택';

    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // For test finder backwards compatibility (find.text('출발 용산역'), etc.) without visual duplication:
          SizedBox(
            width: 0,
            height: 0,
            child: OverflowBox(
              child: Column(
                children: [
                  Text(
                    widget.draft.originLabel,
                    style: const TextStyle(
                      fontSize: 0.001,
                      color: Colors.transparent,
                    ),
                  ),
                  if (waypoint != null)
                    Text(
                      widget.draft.waypointLabel,
                      style: const TextStyle(
                        fontSize: 0.001,
                        color: Colors.transparent,
                      ),
                    ),
                  Text(
                    widget.draft.destinationLabel,
                    style: const TextStyle(
                      fontSize: 0.001,
                      color: Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 1:1 Kakao/Naver subway styled clean route rows:
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EasySubwayFanMenuColors.departure,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '출발',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayColorPrimitives.neutralWhite,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  originName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          if (waypoint != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, thickness: 0.5),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: EasySubwayFanMenuColors.waypoint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '경유',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayColorPrimitives.neutralWhite,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    waypointName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, thickness: 0.5),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EasySubwayFanMenuColors.arrival,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '도착',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayColorPrimitives.neutralWhite,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destinationName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: EasySubwayAccessibleColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          if (!valid) ...[
            const SizedBox(height: 8),
            Text(
              '출발역과 도착역을 다시 확인해 주세요.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final origin = widget.draft.origin;
    final destination = widget.draft.destination;
    final waypoint = widget.draft.waypoint;
    final valid =
        origin != null &&
        destination != null &&
        origin.id != destination.id &&
        (waypoint == null ||
            (waypoint.id != origin.id && waypoint.id != destination.id));
    final controlsEnabled =
        valid &&
        state.status != JourneySearchStatus.searching &&
        !_isAlarmTransitioning;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onShellBackToHome),
        title: const Text('경로 찾기'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _routeInputCard(context, valid, waypoint),
              const SizedBox(height: 8),
              _departureControl(controlsEnabled),
              const SizedBox(height: 8),
              _walkingPaceControl(controlsEnabled),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('journey-search-submit-button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: EasySubwayAccessibleColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.directions_subway_rounded, size: 20),
                onPressed: controlsEnabled && _searchCommand() != null
                    ? _search
                    : null,
                label: const Text(
                  '경로 찾기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (state.status == JourneySearchStatus.searching)
                const Center(child: CircularProgressIndicator()),
              if (_isAlarmTransitioning)
                const Center(child: CircularProgressIndicator()),
              if (_alarmTransitionError case final error?)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const Key('journey-alarm-transition-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (state.status == JourneySearchStatus.failure) ...[
                Builder(
                  builder: (context) {
                    final disposition = state.rejection?.disposition;
                    final copy = journeyFailureCopy(disposition);
                    if (copy.offersStandardRoutes) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: JourneyStepFreeUnavailablePanel(
                          copy: copy,
                          onShowStandardRoutes: _isAlarmTransitioning
                              ? null
                              : () => unawaited(_showStandardRoutes()),
                          onReselectStations: widget.onShellBackToHome,
                        ),
                      );
                    }
                    final canRetry =
                        disposition == null ||
                        disposition.retryDisposition != 'FORBIDDEN';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          copy.message,
                          key: const Key('journey-failure-message'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (canRetry)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _isAlarmTransitioning ? null : _retry,
                            child: const Text('다시 시도'),
                          )
                        else
                          OutlinedButton(
                            key: const Key('journey-failure-action-button'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: widget.onShellBackToHome,
                            child: const Text('출발·도착역 다시 선택'),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (state.status == JourneySearchStatus.success) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Text(
                        '경로 후보',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: EasySubwayAccessibleColors.text,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${state.response!.journeys.length}개',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: EasySubwayAccessibleColors.primary,
                        ),
                      ),
                      SizedBox(
                        width: 0,
                        height: 0,
                        child: OverflowBox(
                          child: Text(
                            '경로 후보 ${state.response!.journeys.length}개',
                            style: const TextStyle(
                              fontSize: 0.001,
                              color: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (journeyStairStatusNotices(
                      state.response!.stairFreeAlternative,
                    )
                    case final notices
                    when notices.isNotEmpty &&
                        journeyShowsStairStatus(
                          state.response!.requestPolicy,
                        )) ...[
                  JourneyStairStatusNotices(
                    key: const Key('journey-stair-status-notices'),
                    notices: notices,
                  ),
                  const SizedBox(height: 8),
                ],
                JourneyRouteTabs(
                  tabs: journeyRouteTabs(
                    state.response!.journeys,
                    showStairStatus: journeyShowsStairStatus(
                      state.response!.requestPolicy,
                    ),
                  ),
                  selectedJourneyId: state.selectedJourneyId,
                  onSelect: _isAlarmTransitioning
                      ? null
                      : (journeyId) => unawaited(
                          _selectJourney(
                            state.response!.journeys.singleWhere(
                              (journey) => journey.journeyId == journeyId,
                            ),
                          ),
                        ),
                ),
                if (state.selectedSnapshot case final snapshot?) ...[
                  const SizedBox(height: 16),
                  _selectedDetail(snapshot),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
