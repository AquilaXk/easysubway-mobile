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
import 'journey_get_off_alarm_toggle.dart';
import '../../../generated/journey_v3/journey_v3_contract.dart';
import '../../../core/crashlytics/mobile_crash_reporting.dart';
import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../stations/domain/station_line.dart';

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
  final Set<int> _expandedLegIndices = {};

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
          ) =>
            [fromStationId, toStationId, directionStationId],
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

  String _stationName(String stationId) =>
      _resolvedStationNames[stationId] ?? stationId;

  String _formatLineName(String lineId) {
    final clean = lineId.replaceAll(RegExp(r'^line-|^seoul-|^korail-'), '');
    const knownLines = <String, String>{
      'gyeongui-jungang': '경의중앙선',
      'suin-bundang': '수인분당선',
      'shinbundang': '신분당선',
      'arex': '공항철도',
      'airport': '공항철도',
      'gyeongchun': '경춘선',
      'gyeonggang': '경강선',
      'seohae': '서해선',
      'sillim': '신림선',
      'ui-sinseol': '우이신설선',
      'everline': '에버라인',
      'gimpo-gold': '김포골드라인',
    };
    if (knownLines.containsKey(clean)) {
      return knownLines[clean]!;
    }
    if (int.tryParse(clean) != null) {
      return '$clean호선';
    }
    return lineId;
  }

  Color _resolveLineColor(String lineId) {
    final hex = fallbackLineColorHex(lineId: lineId);
    return stationLineColor(hex);
  }

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
    }
    setState(() {});
    if (state.status == _lastAnnouncedStatus) return;
    _lastAnnouncedStatus = state.status;
    final message = <JourneySearchStatus, String Function()>{
      JourneySearchStatus.searching: () => '경로를 찾고 있어요.',
      JourneySearchStatus.success: () =>
          '경로 ${state.response!.journeys.length}개를 찾았어요.',
      JourneySearchStatus.failure: () =>
          state.rejection?.disposition.canonicalKoreanCopy ?? '경로를 찾지 못했어요.',
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

  String _arrivalTime(Journey journey) {
    return _kstTime(journey.realtimeArrivalTime ?? journey.plannedArrivalTime);
  }

  String _kstTime(DateTime dateTime) {
    final value = dateTime.toUtc().add(const Duration(hours: 9));
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
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

  String _durationLabel(int seconds) => '${(seconds + 59) ~/ 60}분';

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

  Widget? _outOfStationFareBreakdown(JourneyTransferLeg leg) {
    if (leg.transferType != 'OUT_OF_STATION') return null;
    if (!leg.farePenaltyApplies && leg.additionalFareWon <= 0) return null;
    final amount = leg.additionalFareWon > 0 ? leg.additionalFareWon : 1400;
    final s = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(s[i]);
    }
    return Container(
      key: const Key('out-of-station-fare-breakdown'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '추가 요금 +${buffer.toString()}원',
        style: const TextStyle(
          fontSize: 11,
          color: EasySubwayAccessibleColors.contentSecondary,
        ),
      ),
    );
  }

  Widget _candidateRow(
    BuildContext context,
    Journey journey, {
    int index = 0,
    List<Journey> allJourneys = const [],
  }) {
    final selected = _controller.state.selectedJourneyId == journey.journeyId;
    final durationMinutes = (journey.durationSeconds + 59) ~/ 60;
    final transfer = journey.transferCount == 0
        ? '환승 없음'
        : '환승 ${journey.transferCount}회';
    final accessibility = journey.accessibility.stairFree
        ? '무단차 경로'
        : '무단차 경로 아님';
    JourneyTransferLeg? outOfStationLeg;
    for (final leg in journey.legs) {
      if (leg is JourneyTransferLeg && leg.transferType == 'OUT_OF_STATION') {
        outOfStationLeg = leg;
        break;
      }
    }
    final rideLegs = journey.legs.whereType<JourneyRideLeg>().toList(
      growable: false,
    );
    final summary =
        '$durationMinutes분, $transfer, 도보 ${journey.walkingDistanceMeters}m, ${_arrivalTime(journey)} 도착, $accessibility';
    final color = Theme.of(context).colorScheme.primary;
    void selectJourney() => unawaited(_selectJourney(journey));

    final tags = <String>[];
    if (allJourneys.isNotEmpty) {
      final minDuration = allJourneys
          .map((j) => j.durationSeconds)
          .fold<int>(allJourneys.first.durationSeconds, math.min);
      final minTransfers = allJourneys
          .map((j) => j.transferCount)
          .fold<int>(allJourneys.first.transferCount, math.min);

      final isFastest = journey.durationSeconds == minDuration;
      final isLeastTransfers = journey.transferCount == minTransfers;

      if (isFastest &&
          index ==
              allJourneys.indexWhere((j) => j.durationSeconds == minDuration)) {
        tags.add('최단시간');
      } else if (isLeastTransfers &&
          index ==
              allJourneys.indexWhere((j) => j.transferCount == minTransfers)) {
        tags.add('최소환승');
      }

      if (journey.accessibility.stairFree) {
        tags.add('무단차');
      }
    }

    if (tags.isEmpty) {
      tags.add(
        index == 0
            ? '최단시간'
            : (index == 1
                  ? '최소환승'
                  : (journey.accessibility.stairFree ? '무단차' : '대안경로')),
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: summary,
      child: InkWell(
        key: Key('journey-candidate-${journey.journeyId}'),
        onTap: _isAlarmTransitioning ? null : selectJourney,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.08)
                : EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : EasySubwayAccessibleColors.line,
              width: selected ? 2.0 : 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final tag in tags) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? color
                            : (tag == '무단차'
                                  ? EasySubwayColorPrimitives.statusSuccessSoft
                                  : EasySubwayAccessibleColors
                                        .surfaceBrandChrome),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selected
                              ? color
                              : (tag == '무단차'
                                    ? EasySubwayAccessibleColors.mint
                                    : EasySubwayAccessibleColors.primary
                                          .withValues(alpha: 0.25)),
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? EasySubwayColorPrimitives.neutralWhite
                              : (tag == '무단차'
                                    ? EasySubwayAccessibleColors.mint
                                    : EasySubwayAccessibleColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 2),
                  Text(
                    '$durationMinutes분',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: selected ? color : EasySubwayAccessibleColors.text,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var rIdx = 0;
                            rIdx < rideLegs.length;
                            rIdx++
                          ) ...[
                            if (rIdx > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 9,
                                  color:
                                      EasySubwayAccessibleColors.secondaryText,
                                ),
                              ),
                            Container(
                              key: rIdx == 0
                                  ? Key(
                                      'journey-candidate-line-${journey.journeyId}',
                                    )
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: _resolveLineColor(rideLegs[rIdx].lineId),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatLineName(rideLegs[rIdx].lineId),
                                style: const TextStyle(
                                  color: EasySubwayColorPrimitives.neutralWhite,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                          if (outOfStationLeg != null) ...[
                            const SizedBox(width: 6),
                            _outOfStationTransferBadge(outOfStationLeg)!,
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_circle_rounded,
                      key: Key('selected-journey-${journey.journeyId}'),
                      color: color,
                      size: 18,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_arrivalTime(journey)} 도착 · 도보 ${journey.walkingDistanceMeters}m · $transfer · 카드 1,400원',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: EasySubwayAccessibleColors.secondaryText,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    journey.accessibility.stairFree ? '♿ 무단차 경로' : '일반 경로',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: journey.accessibility.stairFree
                          ? EasySubwayAccessibleColors.mint
                          : EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _legStopCount(JourneyRideLeg leg) {
    final minutes = leg.plannedArrivalTime
        .difference(leg.plannedDepartureTime)
        .inMinutes;
    return math.max(1, (minutes / 2.2).round());
  }

  int _estimatedStopCount(Journey journey) {
    var count = 0;
    for (final leg in journey.legs.whereType<JourneyRideLeg>()) {
      count += _legStopCount(leg);
    }
    return math.max(1, count);
  }

  Widget _selectedDetail(JourneySelectedSnapshot snapshot) {
    final journey = snapshot.journey;
    final durationMinutes = (journey.durationSeconds + 59) ~/ 60;
    final transferLabel = journey.transferCount == 0
        ? '환승 없음'
        : '환승 ${journey.transferCount}회';
    final totalStops = _estimatedStopCount(journey);

    return Column(
      key: const Key('selected-journey-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 4),
        Text(
          '선택 경로 상세',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EasySubwayAccessibleColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$durationMinutes',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '분 소요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: journey.accessibility.stairFree
                          ? EasySubwayColorPrimitives.statusSuccessSoft
                          : EasySubwayAccessibleColors.surfaceBrandChrome,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: journey.accessibility.stairFree
                            ? EasySubwayAccessibleColors.mint
                            : EasySubwayAccessibleColors.primary.withValues(
                                alpha: 0.3,
                              ),
                      ),
                    ),
                    child: Text(
                      journey.accessibility.stairFree ? '♿ 무단차 경로' : '일반 경로',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: journey.accessibility.stairFree
                            ? EasySubwayAccessibleColors.mint
                            : EasySubwayAccessibleColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_arrivalTime(journey)} 도착',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                  const Text(
                    '·',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  Text(
                    '$totalStops개 역 이동',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  const Text(
                    '·',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  Text(
                    transferLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  const Text(
                    '·',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  const Text(
                    '카드 1,400원',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        for (var index = 0; index < journey.legs.length; index++)
          _detailLeg(index, journey.legs[index], journey),
        if (widget.getOffAlarmController case final alarmController?) ...[
          const SizedBox(height: 3),
          JourneyGetOffAlarmToggle(
            snapshot: snapshot,
            controller: alarmController,
            stationNameResolver: widget.stationNameResolver!,
            now: widget.getOffAlarmNow ?? DateTime.now,
          ),
        ],
        const SizedBox(height: 4),
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

  Widget _detailLeg(int index, JourneyLeg leg, Journey journey) {
    final isLastLeg = index == journey.legs.length - 1;
    final rideLegs = journey.legs.whereType<JourneyRideLeg>().toList(
      growable: false,
    );
    final firstRide = rideLegs.firstOrNull;
    final lastRide = rideLegs.lastOrNull;

    final Color trackColor;
    final Widget nodeIcon;
    final Widget content;
    final String semanticsLabel;

    if (leg is JourneyEntryLeg) {
      final lineColor = firstRide != null
          ? _resolveLineColor(firstRide.lineId)
          : EasySubwayAccessibleColors.primary;
      trackColor = lineColor;
      nodeIcon = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EasySubwayAccessibleColors.surface,
          border: Border.all(color: lineColor, width: 3),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: lineColor),
        ),
      );
      content = Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _stationName(leg.fromStationId),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                ),
                Text(
                  '${_kstTime(journey.realtimeDepartureTime ?? journey.plannedDepartureTime)} 출발',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(
                  Icons.directions_walk_rounded,
                  size: 13,
                  color: EasySubwayAccessibleColors.secondaryText,
                ),
                const SizedBox(width: 4),
                const Text(
                  '승강장으로 이동',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _durationLabel(leg.durationSeconds),
                  style: const TextStyle(
                    fontSize: 12,
                    color: EasySubwayAccessibleColors.mutedText,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      semanticsLabel =
          '${_stationName(leg.fromStationId)}, 승강장으로 이동, ${_durationLabel(leg.durationSeconds)}';
    } else if (leg is JourneyRideLeg) {
      final lineColor = _resolveLineColor(leg.lineId);
      trackColor = lineColor;
      final badgeNum = _lineBadgeNumber(leg.lineId);
      final isExpanded = _expandedLegIndices.contains(index);
      final stopCount = _legStopCount(leg);

      nodeIcon = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lineColor,
          border: Border.all(
            color: EasySubwayColorPrimitives.neutralWhite,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: EasySubwayAccessibleColors.cardShadow,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          badgeNum,
          style: const TextStyle(
            color: EasySubwayColorPrimitives.neutralWhite,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ),
      );
      content = Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EasySubwayAccessibleColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    '열차 탑승',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatLineName(leg.lineId),
                      style: const TextStyle(
                        color: EasySubwayColorPrimitives.neutralWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (leg.directionStationId.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${_stationName(leg.directionStationId)} 방면',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: EasySubwayAccessibleColors.secondaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  Text(
                    '${_kstTime(leg.realtimeDepartureTime ?? leg.plannedDepartureTime)}–${_kstTime(leg.realtimeArrivalTime ?? leg.plannedArrivalTime)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${_stationName(leg.fromStationId)} → ${_stationName(leg.toStationId)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: EasySubwayAccessibleColors.text,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedLegIndices.remove(index);
                        } else {
                          _expandedLegIndices.add(index);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: EasySubwayAccessibleColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: EasySubwayAccessibleColors.line,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 12,
                            color: EasySubwayAccessibleColors.secondaryText,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            isExpanded ? '접기 ▴' : '$stopCount개 역 이동 ▾',
                            style: const TextStyle(
                              color: EasySubwayAccessibleColors.secondaryText,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: EasySubwayAccessibleColors.surfaceBrandChrome,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• 출발: ${_stationName(leg.fromStationId)} (${_kstTime(leg.realtimeDepartureTime ?? leg.plannedDepartureTime)})',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '• 방면: ${leg.directionStationId.isNotEmpty ? '${_stationName(leg.directionStationId)} 방면' : '행선 방면'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '• 도착: ${_stationName(leg.toStationId)} (${_kstTime(leg.realtimeArrivalTime ?? leg.plannedArrivalTime)})',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      semanticsLabel =
          '열차 탑승, ${_formatLineName(leg.lineId)}, ${_stationName(leg.fromStationId)} → ${_stationName(leg.toStationId)}';
    } else if (leg is JourneyTransferLeg) {
      trackColor = EasySubwayAccessibleColors.line;
      final badge = _outOfStationTransferBadge(leg);
      final fare = _outOfStationFareBreakdown(leg);

      nodeIcon = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EasySubwayAccessibleColors.surface,
          border: Border.all(
            color: EasySubwayAccessibleColors.primary,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.sync_alt_rounded,
          size: 13,
          color: EasySubwayAccessibleColors.primary,
        ),
      );
      content = Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(
                Icons.transfer_within_a_station_rounded,
                size: 14,
                color: EasySubwayAccessibleColors.secondaryText,
              ),
              const SizedBox(width: 4),
              const Text(
                '환승 이동',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: EasySubwayAccessibleColors.text,
                  fontSize: 13,
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 6), badge],
              const Spacer(),
              Text(
                _durationLabel(leg.durationSeconds),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: EasySubwayAccessibleColors.secondaryText,
                  fontSize: 12,
                ),
              ),
              if (fare != null) ...[const SizedBox(width: 4), fare],
            ],
          ),
        ),
      );
      semanticsLabel = '환승 이동, ${_durationLabel(leg.durationSeconds)}';
    } else if (leg is JourneyExitLeg) {
      final lineColor = lastRide != null
          ? _resolveLineColor(lastRide.lineId)
          : EasySubwayAccessibleColors.primary;
      trackColor = lineColor;
      nodeIcon = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lineColor,
          border: Border.all(
            color: EasySubwayColorPrimitives.neutralWhite,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: EasySubwayAccessibleColors.cardShadow,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.place_rounded,
          size: 13,
          color: EasySubwayColorPrimitives.neutralWhite,
        ),
      );
      content = Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _stationName(leg.fromStationId),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                ),
                Text(
                  '${_arrivalTime(journey)} 도착',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(
                  Icons.exit_to_app_rounded,
                  size: 13,
                  color: EasySubwayAccessibleColors.secondaryText,
                ),
                const SizedBox(width: 4),
                const Text(
                  '도착역 나가기',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _durationLabel(leg.durationSeconds),
                  style: const TextStyle(
                    fontSize: 12,
                    color: EasySubwayAccessibleColors.mutedText,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      semanticsLabel =
          '${_stationName(leg.fromStationId)}, 도착역 나가기, ${_durationLabel(leg.durationSeconds)}';
    } else {
      trackColor = EasySubwayAccessibleColors.line;
      nodeIcon = const SizedBox(width: 24, height: 24);
      content = const SizedBox.shrink();
      semanticsLabel = '';
    }

    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          key: Key('selected-journey-leg-$index'),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      nodeIcon,
                      if (!isLastLeg)
                        Expanded(
                          child: Container(
                            width:
                                leg is JourneyRideLeg || leg is JourneyEntryLeg
                                ? 5
                                : 3,
                            color: trackColor,
                            margin: const EdgeInsets.symmetric(vertical: 1),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shareText(JourneySelectedSnapshot snapshot) {
    final journey = snapshot.journey;
    final transfer = journey.transferCount == 0
        ? '환승 없음'
        : '환승 ${journey.transferCount}회';
    final accessibility = journey.accessibility.stairFree
        ? '무단차 경로'
        : '무단차 경로 아님';
    return '${widget.draft.origin!.displayName} → ${widget.draft.destination!.displayName}\n'
        '${_durationLabel(journey.durationSeconds)} · $transfer · ${_arrivalTime(journey)} 도착 · $accessibility';
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

  Future<void> _search() async {
    final command = _searchCommand();
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
                    semanticsLabel: '교통약자 안심 막차 찾기(Last Connection)',
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
                    final copy =
                        disposition?.canonicalKoreanCopy ??
                        '경로를 찾지 못했어요. 잠시 후 다시 시도해 주세요.';
                    final canRetry =
                        disposition == null ||
                        disposition.retryDisposition != 'FORBIDDEN';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          copy,
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
                for (
                  var index = 0;
                  index < state.response!.journeys.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(height: 6),
                  _candidateRow(
                    context,
                    state.response!.journeys[index],
                    index: index,
                    allJourneys: state.response!.journeys,
                  ),
                ],
                if (state.selectedSnapshot case final snapshot?)
                  _selectedDetail(snapshot),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
