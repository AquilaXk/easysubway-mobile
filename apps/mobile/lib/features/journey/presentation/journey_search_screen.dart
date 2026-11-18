import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:share_plus/share_plus.dart';

import '../../get_off_alarm/get_off_alarm_port.dart';
import '../../route_draft/domain/route_draft.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_profile_policy.dart';
import '../../../core/ui/route_role_dot.dart';
import '../application/journey_search_controller.dart';
import '../domain/journey_repository.dart';
import '../domain/transfer_guide.dart';
import '../domain/transfer_guide_key.dart';
import 'journey_departure_choice.dart';
import 'journey_departure_sheet.dart';
import 'journey_get_off_alarm_toggle.dart';
import 'result/journey_result_view_model.dart';
import 'result/journey_result_widgets.dart';
import 'result/journey_timeline.dart';
import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../../../core/crashlytics/mobile_crash_reporting.dart';
import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

typedef JourneyShareInvoker = Future<void> Function(String text, Rect origin);

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
    this.onSwapOriginDestination,
    this.onClearWaypoint,
    this.onOpenStation,
    this.onOpenStationTimetable,
    super.key,
  }) : assert(getOffAlarmController == null || stationNameResolver != null);

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final JourneySessionProvider? sessionProvider;
  final RouteDraft draft;
  final String mobilityType;
  final WalkingPace? initialWalkingPace;
  final VoidCallback onShellBackToHome;
  final VoidCallback? onSwapOriginDestination;
  final VoidCallback? onClearWaypoint;

  /// 경로 상세의 역 이름 `>`와 `실시간` 칩이 여는 기존 역 상세 화면.
  final ValueChanged<String>? onOpenStation;

  /// 경로 상세의 `시간표` 칩이 여는 기존 역 시간표 화면.
  final ValueChanged<String>? onOpenStationTimetable;
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
  late RouteDraft _draft;
  JourneySearchStatus _lastAnnouncedStatus = JourneySearchStatus.idle;
  bool _isSharing = false;
  bool _isAlarmTransitioning = false;
  String? _alarmTransitionError;
  WalkingPace _walkingPace = WalkingPace.standard;
  JourneyDepartureChoice _departure = const JourneyDepartNow();
  JourneyCriterion? _criterion;

  final Map<String, String> _resolvedStationNames = {};
  final Set<String> _expandedRideKeys = {};
  final Set<TransferGuideKey> _expandedTransferGuideKeys = {};

  /// 조회 키(`TransferGuideKey`)별 환승 이동 안내 단계. 조회했는데 행이 없으면 키가 없다.
  /// 여정 ID나 leg 위치가 아니라 조회 키로만 묶어, 다른 환승에 다른 문장이 붙지 않게 한다.
  final Map<TransferGuideKey, List<String>> _transferGuideSteps = {};
  final Set<TransferGuideKey> _requestedTransferGuideKeys = {};

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
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

  @override
  void didUpdateWidget(covariant JourneySearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      _draft = widget.draft;
    }
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
        if (!_requestedTransferGuideKeys.add(key)) continue;
        unawaited(
          repository
              .loadSteps(key)
              .then((steps) {
                if (mounted && steps.isNotEmpty) {
                  setState(() => _transferGuideSteps[key] = steps);
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
            fontWeight: EasySubwayFontWeight.emphasis,
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
          fontWeight: EasySubwayFontWeight.emphasis,
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
      // 막차는 프로필 검색이라 서버 기준 시각이 없다(응답 변환이 첫 여정 출발로 채운다).
      basis: _departure is JourneyLastTrain
          ? null
          : snapshot.effectiveDepartureTime,
    );
    return Column(
      key: const Key('selected-journey-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JourneyResultSummaryView(
          key: Key('selected-journey-${journey.journeyId}'),
          summary: viewModel.summary,
          showStairStatus: journeyShowsStairStatus(snapshot.requestPolicy),
        ),
        const SizedBox(height: EasySubwaySpacing.lg),
        JourneySegmentBar(
          segments: viewModel.segments,
          semanticsLabel: viewModel.segmentsSemanticsLabel,
        ),
        const SizedBox(height: EasySubwaySpacing.lg),
        if (viewModel.basisLabel case final basis?)
          JourneyBasisRow(label: basis),
        JourneyTimeline(
          nodes: viewModel.timeline,
          isRideExpanded: (legIndex) =>
              _expandedRideKeys.contains('${journey.journeyId}:$legIndex'),
          onToggleRide: (legIndex) => setState(() {
            final key = '${journey.journeyId}:$legIndex';
            if (!_expandedRideKeys.remove(key)) _expandedRideKeys.add(key);
          }),
          boardingExtras: (node) => _buildPlatformGapGuidance(
            isBoarding: true,
            gaps: node.boardingPlatformGaps,
            stationName: node.boardingStationName,
          ),
          alightingExtras: (node) => _buildPlatformGapGuidance(
            isBoarding: false,
            gaps: node.alightingPlatformGaps,
            stationName: node.alightingStationName,
          ),
          transferExtras: (node) =>
              _transferExtras(node, transferGuideKeyAt(journey, node.legIndex)),
          onOpenStation: widget.onOpenStation,
          onOpenStationTimetable: widget.onOpenStationTimetable,
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

  /// 환승 줄 아래의 역 밖 환승 배지, 재승차 안내, 환승 이동 안내 단계.
  Widget _transferExtras(JourneyTransferNode node, TransferGuideKey? guideKey) {
    final guideSteps = guideKey == null ? null : _transferGuideSteps[guideKey];
    final badge = _outOfStationTransferBadge(node.leg);
    final reboarding = _reboardingFareNotice(node.leg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badge != null || reboarding != null) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [?badge, ?reboarding]),
        ],
        if (guideKey != null && guideSteps != null)
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
                        fontWeight: EasySubwayFontWeight.regular,
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
                            fontWeight: EasySubwayFontWeight.emphasis,
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
    return '${_draft.origin!.displayName} → ${_draft.destination!.displayName}\n'
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
    final origin = _draft.origin;
    final destination = _draft.destination;
    final waypoint = _draft.waypoint;
    if (origin == null ||
        destination == null ||
        origin.id == destination.id ||
        (waypoint != null &&
            (waypoint.id == origin.id || waypoint.id == destination.id))) {
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
    // 막차는 운행일 하나만 보내는 LAST_CONNECTION 프로필 질의다.
    final (
      JourneyDeparture departure,
      JourneyTemporalQuery? temporalQuery,
    ) = switch (_departure) {
      JourneyDepartNow() => (const JourneyDepartureNow(), null),
      JourneyDepartAt(:final requestedAt) => (
        JourneyDepartureScheduled(requestedAt),
        null,
      ),
      final JourneyLastTrain lastTrain => (
        JourneyDepartureScheduled(lastTrain.serviceDay),
        JourneyLastConnectionQuery(serviceDate: lastTrain.serviceDate),
      ),
    };
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
            fontWeight: EasySubwayFontWeight.emphasis,
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
                              ? EasySubwayFontWeight.emphasis
                              : EasySubwayFontWeight.regular,
                          color: _walkingPace == pace
                              ? EasySubwayAccessibleColors.interactionOnBrand
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

  DateTime _now() => (widget.journeyNow ?? DateTime.now)();

  /// 출발 기준을 바꾼다. 결과가 떠 있으면 상용 지하철 서비스처럼 바로 다시
  /// 찾고, 아니면 이전 결과를 지운다.
  Future<void> _applyDeparture(
    JourneyDepartureChoice choice, {
    bool search = false,
  }) async {
    if (_isAlarmTransitioning) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    final wasSuccess = _controller.state.status == JourneySearchStatus.success;
    setState(() => _departure = choice);
    if (search || wasSuccess) {
      await _search();
    } else {
      _controller.reset();
    }
  }

  Future<void> _openDepartureSheet() async {
    final choice = await showJourneyDepartureSheet(
      context,
      initial: _departure,
      now: _now(),
    );
    if (choice == null || !mounted) return;
    await _applyDeparture(choice);
  }

  /// `다음열차`: 고른 경로 첫 열차 출발 1분 뒤로 다시 찾는다.
  Future<void> _nextTrain(JourneySelectedSnapshot snapshot) {
    final firstBoarding = JourneyResultViewModel.fromJourney(
      snapshot.journey,
      stationName: _stationName,
    ).firstBoardingTime;
    return _applyDeparture(
      JourneyDepartAt(firstBoarding.add(const Duration(minutes: 1))),
      search: true,
    );
  }

  /// 탭 줄의 `막차`: 지금 운행일의 막차를 찾는다.
  Future<void> _lastTrainNow() => _applyDeparture(
    JourneyLastTrain(journeyCurrentServiceDay(_now())),
    search: true,
  );

  /// `오늘 00:36 출발 ▾ | 다음열차` 줄. 이전열차는 서버 요청 모드가 없어 두지 않는다.
  Widget _departureBar({
    required bool enabled,
    required JourneySelectedSnapshot? snapshot,
  }) {
    final canNext = enabled && _departure is! JourneyLastTrain;
    final label = journeyDepartureBarLabel(_departure, _now());
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border.all(color: EasySubwayAccessibleColors.line),
        borderRadius: BorderRadius.circular(EasySubwayRadius.control),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Semantics(
                button: true,
                label: '출발 시각 설정, $label',
                excludeSemantics: true,
                onTap: enabled ? _openDepartureSheet : null,
                child: TextButton(
                  key: const Key('journey-departure-bar-time'),
                  onPressed: enabled ? _openDepartureSheet : null,
                  style: _barButtonStyle,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: EasySubwayFontWeight.emphasis,
                            color: EasySubwayAccessibleColors.primary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        color: EasySubwayAccessibleColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(
              width: 1,
              color: EasySubwayAccessibleColors.line,
            ),
            Expanded(
              child: TextButton(
                key: const Key('journey-departure-bar-next'),
                onPressed: switch (snapshot) {
                  final selected? when canNext => () => unawaited(
                    _nextTrain(selected),
                  ),
                  _ => null,
                },
                style: _barButtonStyle,
                child: const Text(
                  '다음열차',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final _barButtonStyle = TextButton.styleFrom(
    minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
    foregroundColor: EasySubwayAccessibleColors.text,
    disabledForegroundColor: EasySubwayAccessibleColors.mutedText,
    shape: const RoundedRectangleBorder(),
  );

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

  Future<void> _swapOriginAndDestination() async {
    final origin = _draft.origin;
    final destination = _draft.destination;
    if (origin == null || destination == null || _isAlarmTransitioning) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    final wasSuccess = _controller.state.status == JourneySearchStatus.success;
    setState(() {
      _draft = RouteDraft(
        origin: destination,
        waypoint: _draft.waypoint,
        destination: origin,
        lastModifiedAt: (widget.journeyNow ?? DateTime.now)(),
      );
    });
    widget.onSwapOriginDestination?.call();
    if (wasSuccess) {
      await _search();
    } else {
      _controller.reset();
    }
  }

  Future<void> _clearWaypoint() async {
    if (_draft.waypoint == null || _isAlarmTransitioning) return;
    if (!await _prepareForTemporalChange() || !mounted) return;
    final wasSuccess = _controller.state.status == JourneySearchStatus.success;
    setState(() {
      _draft = RouteDraft(
        origin: _draft.origin,
        destination: _draft.destination,
        lastModifiedAt: (widget.journeyNow ?? DateTime.now)(),
      );
    });
    widget.onClearWaypoint?.call();
    if (wasSuccess) {
      await _search();
    } else {
      _controller.reset();
    }
  }

  Widget _routeInputCard(
    BuildContext context,
    bool valid,
    RouteDraftStation? waypoint, {
    required bool controlsEnabled,
  }) {
    final originName = _draft.origin?.displayName ?? '출발역 선택';
    final destinationName = _draft.destination?.displayName ?? '도착역 선택';
    final waypointName = waypoint?.displayName ?? '경유역 선택';
    final canSwap =
        controlsEnabled && _draft.origin != null && _draft.destination != null;

    return Container(
      key: const Key('journey-route-input-card'),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(EasySubwayRadius.card),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('journeyRouteSwapButton'),
                tooltip: '출발·도착역 바꾸기',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                padding: EdgeInsets.zero,
                onPressed: canSwap
                    ? () => unawaited(_swapOriginAndDestination())
                    : null,
                icon: const Icon(
                  Icons.swap_vert_rounded,
                  size: 22,
                  color: EasySubwayAccessibleColors.secondaryText,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const RouteRoleDot(
                          key: Key('journey-route-dot-origin'),
                          color: EasySubwayRouteDotColors.origin,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            originName,
                            semanticsLabel: _draft.originLabel,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: EasySubwayFontWeight.regular,
                              color: EasySubwayAccessibleColors.text,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (waypoint != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, thickness: 0.5),
                      ),
                      Row(
                        children: [
                          const RouteRoleDot(
                            key: Key('journey-route-dot-waypoint'),
                            color: EasySubwayRouteDotColors.waypoint,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              waypointName,
                              semanticsLabel: _draft.waypointLabel,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: EasySubwayFontWeight.regular,
                                color: EasySubwayAccessibleColors.text,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('journeyWaypointClearButton'),
                            tooltip: '경유역 지우기',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: controlsEnabled
                                ? () => unawaited(_clearWaypoint())
                                : null,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: EasySubwayAccessibleColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Divider(height: 1, thickness: 0.5),
                    ),
                    Row(
                      children: [
                        const RouteRoleDot(
                          key: Key('journey-route-dot-destination'),
                          color: EasySubwayRouteDotColors.destination,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            destinationName,
                            semanticsLabel: _draft.destinationLabel,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: EasySubwayFontWeight.regular,
                              color: EasySubwayAccessibleColors.text,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                fontWeight: EasySubwayFontWeight.regular,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _criterionTabs(JourneySearchState state) {
    final response = state.response!;
    final tabs = journeyCriterionTabs(
      response.journeys,
      showStairStatus: journeyShowsStairStatus(response.requestPolicy),
    );
    final selectedId = state.selectedJourneyId;
    final selected =
        tabs
            .where(
              (tab) =>
                  tab.criterion == _criterion && tab.journeyId == selectedId,
            )
            .firstOrNull ??
        tabs.where((tab) => tab.journeyId == selectedId).firstOrNull;
    return JourneyCriterionTabBar(
      tabs: tabs,
      selected: selected?.criterion,
      onSelect: _isAlarmTransitioning
          ? null
          : (tab) {
              setState(() => _criterion = tab.criterion);
              unawaited(
                _selectJourney(
                  response.journeys.singleWhere(
                    (journey) => journey.journeyId == tab.journeyId,
                  ),
                ),
              );
            },
      lastTrainSelected: _departure is JourneyLastTrain,
      onLastTrain: _isAlarmTransitioning
          ? null
          : () => unawaited(_lastTrainNow()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final origin = _draft.origin;
    final destination = _draft.destination;
    final waypoint = _draft.waypoint;
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
              _routeInputCard(
                context,
                valid,
                waypoint,
                controlsEnabled: controlsEnabled,
              ),
              const SizedBox(height: 8),
              _departureBar(
                enabled: controlsEnabled,
                snapshot: state.status == JourneySearchStatus.success
                    ? state.selectedSnapshot
                    : null,
              ),
              const SizedBox(height: 8),
              _walkingPaceControl(controlsEnabled),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('journey-search-submit-button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: EasySubwayFontWeight.emphasis,
                  ),
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
                            fontWeight: EasySubwayFontWeight.emphasis,
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
                _criterionTabs(state),
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
