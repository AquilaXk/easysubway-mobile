import 'dart:async';

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

typedef JourneyShareInvoker = Future<void> Function(String text, Rect origin);

class JourneySearchScreen extends StatefulWidget {
  const JourneySearchScreen({
    required this.repository,
    required this.attestor,
    required this.draft,
    required this.mobilityType,
    required this.onShellBackToHome,
    this.shareInvoker,
    this.getOffAlarmController,
    this.stationNameResolver,
    this.getOffAlarmNow,
    this.journeyNow,
    super.key,
  }) : assert((getOffAlarmController == null) == (stationNameResolver == null));

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final RouteDraft draft;
  final String mobilityType;
  final VoidCallback onShellBackToHome;
  final JourneyShareInvoker? shareInvoker;
  final GetOffAlarmPort? getOffAlarmController;
  final JourneyStationNameResolver? stationNameResolver;
  final DateTime Function()? getOffAlarmNow;
  final DateTime Function()? journeyNow;

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

  @override
  void initState() {
    super.initState();
    _controller = JourneySearchController(
      repository: widget.repository,
      attestor: widget.attestor,
      now: widget.journeyNow,
      reportNonFatalError: (error, stackTrace) {
        return recordNonFatalError(error, stackTrace);
      },
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
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
    setState(() {});
    final state = _controller.state;
    if (state.status == _lastAnnouncedStatus) return;
    _lastAnnouncedStatus = state.status;
    final message = <JourneySearchStatus, String Function()>{
      JourneySearchStatus.searching: () => '경로를 찾고 있어요.',
      JourneySearchStatus.success: () =>
          '경로 ${state.response!.journeys.length}개를 찾았어요.',
      JourneySearchStatus.failure: () => '경로를 찾지 못했어요.',
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

  String _durationLabel(int seconds) => '${(seconds + 59) ~/ 60}분';

  Widget _candidateRow(BuildContext context, Journey journey) {
    final selected = _controller.state.selectedJourneyId == journey.journeyId;
    final durationMinutes = (journey.durationSeconds + 59) ~/ 60;
    final transfer = journey.transferCount == 0
        ? '환승 없이 이동'
        : '환승 ${journey.transferCount}회';
    final accessibility = journey.accessibility.stairFree
        ? '무단차 경로'
        : '무단차 경로 아님';
    final summary =
        '$durationMinutes분, $transfer, 도보 ${journey.walkingDistanceMeters}m, ${_arrivalTime(journey)} 도착, $accessibility';
    final color = Theme.of(context).colorScheme.primary;
    void selectJourney() => unawaited(_selectJourney(journey));

    return Semantics(
      key: Key('journey-candidate-${journey.journeyId}'),
      container: true,
      button: true,
      selected: selected,
      label: summary,
      onTap: _isAlarmTransitioning ? null : selectJourney,
      excludeSemantics: true,
      child: InkWell(
        onTap: _isAlarmTransitioning ? null : selectJourney,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: selected
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: color, width: 2)),
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$durationMinutes분',
                      style: selected
                          ? Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )
                          : Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$transfer · 도보 ${journey.walkingDistanceMeters}m · ${_arrivalTime(journey)} 도착',
                    ),
                    Text(accessibility),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  key: Key('selected-journey-${journey.journeyId}'),
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }

  (String, String) _legLabel(JourneyLeg leg) => switch (leg) {
    JourneyEntryLeg(:final durationSeconds) => (
      '승강장으로 이동',
      _durationLabel(durationSeconds),
    ),
    JourneyRideLeg(
      :final plannedDepartureTime,
      :final plannedArrivalTime,
      :final realtimeDepartureTime,
      :final realtimeArrivalTime,
    ) =>
      (
        '열차 탑승',
        '${_kstTime(realtimeDepartureTime ?? plannedDepartureTime)}–${_kstTime(realtimeArrivalTime ?? plannedArrivalTime)}',
      ),
    JourneyTransferLeg(:final durationSeconds) => (
      '환승 이동',
      _durationLabel(durationSeconds),
    ),
    JourneyExitLeg(:final durationSeconds) => (
      '도착역 나가기',
      _durationLabel(durationSeconds),
    ),
  };

  Widget _selectedDetail(JourneySelectedSnapshot snapshot) {
    final journey = snapshot.journey;
    return Column(
      key: const Key('selected-journey-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Text('선택 경로 상세', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (var index = 0; index < journey.legs.length; index++)
          _detailLeg(index, journey.legs[index]),
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

  Widget _detailLeg(int index, JourneyLeg leg) {
    final (title, detail) = _legLabel(leg);
    return Semantics(
      label: '$title, $detail',
      child: ExcludeSemantics(
        child: Container(
          key: Key('selected-journey-leg-$index'),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(title)),
              Text(detail),
            ],
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
    if (origin == null ||
        destination == null ||
        widget.draft.waypoint != null) {
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
    return JourneySearchCommand(
      originStationId: origin.id,
      destinationStationId: destination.id,
      departure: const JourneyDepartureNow(),
      timePolicy: TimePolicy.timetableRequired,
      walkingPace: _walkingPace,
      mobilityProfile: profile,
      constraintMode: constraint,
      maxTransfers: 3,
      alternativeCount: 3,
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
        const Text('걷는 속도'),
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
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(labels[pace]!, textAlign: TextAlign.center),
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

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final valid =
        widget.draft.origin != null &&
        widget.draft.destination != null &&
        widget.draft.waypoint == null;
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
              Text(widget.draft.originLabel),
              Text(widget.draft.destinationLabel),
              if (!valid) const Text('출발역과 도착역을 다시 확인해 주세요.'),
              const SizedBox(height: 12),
              _walkingPaceControl(
                valid &&
                    state.status != JourneySearchStatus.searching &&
                    !_isAlarmTransitioning,
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed:
                    valid &&
                        state.status != JourneySearchStatus.searching &&
                        !_isAlarmTransitioning
                    ? _search
                    : null,
                child: const Text('경로 찾기'),
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
              if (state.status == JourneySearchStatus.failure)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _isAlarmTransitioning ? null : _retry,
                  child: const Text('다시 시도'),
                ),
              if (state.status == JourneySearchStatus.success) ...[
                Text('경로 후보 ${state.response!.journeys.length}개'),
                const SizedBox(height: 8),
                for (
                  var index = 0;
                  index < state.response!.journeys.length;
                  index++
                ) ...[
                  if (index > 0) const Divider(height: 1),
                  _candidateRow(context, state.response!.journeys[index]),
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
