import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../route_draft/domain/route_draft.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_profile_policy.dart';
import '../application/journey_search_controller.dart';
import '../domain/journey_repository.dart';
import '../../../generated/journey_v3/journey_v3_contract.dart';

class JourneySearchScreen extends StatefulWidget {
  const JourneySearchScreen({
    required this.repository,
    required this.attestor,
    required this.draft,
    required this.mobilityType,
    required this.onShellBackToHome,
    super.key,
  });

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final RouteDraft draft;
  final String mobilityType;
  final VoidCallback onShellBackToHome;

  @override
  State<JourneySearchScreen> createState() => _JourneySearchScreenState();
}

class _JourneySearchScreenState extends State<JourneySearchScreen> {
  late final JourneySearchController _controller;
  JourneySearchStatus _lastAnnouncedStatus = JourneySearchStatus.idle;

  @override
  void initState() {
    super.initState();
    _controller = JourneySearchController(
      repository: widget.repository,
      attestor: widget.attestor,
    )..addListener(_changed);
  }

  @override
  void dispose() {
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
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      );
    }
  }

  String _arrivalTime(Journey journey) {
    final value = (journey.realtimeArrivalTime ?? journey.plannedArrivalTime)
        .toUtc()
        .add(const Duration(hours: 9));
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

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
    return Semantics(
      key: Key('journey-candidate-${journey.journeyId}'),
      container: true,
      button: true,
      selected: selected,
      label: summary,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _controller.selectJourney(journey.journeyId),
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

  void _search() {
    final origin = widget.draft.origin;
    final destination = widget.draft.destination;
    if (origin == null ||
        destination == null ||
        widget.draft.waypoint != null) {
      return;
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
    _controller.search(
      JourneySearchCommand(
        originStationId: origin.id,
        destinationStationId: destination.id,
        departure: const JourneyDepartureNow(),
        timePolicy: TimePolicy.timetableRequired,
        mobilityProfile: profile,
        constraintMode: constraint,
        maxTransfers: 3,
        alternativeCount: 3,
      ),
    );
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
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed:
                    valid && state.status != JourneySearchStatus.searching
                    ? _search
                    : null,
                child: const Text('경로 찾기'),
              ),
              if (state.status == JourneySearchStatus.searching)
                const Center(child: CircularProgressIndicator()),
              if (state.status == JourneySearchStatus.failure)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _controller.retry,
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
