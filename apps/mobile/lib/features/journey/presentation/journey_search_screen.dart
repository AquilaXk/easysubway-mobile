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
    super.key,
  });

  final JourneyRepository repository;
  final JourneyV3IntegrityAttestor attestor;
  final RouteDraft draft;
  final String mobilityType;

  @override
  State<JourneySearchScreen> createState() => _JourneySearchScreenState();
}

class _JourneySearchScreenState extends State<JourneySearchScreen> {
  late final JourneySearchController _controller;

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
      appBar: AppBar(title: const Text('경로 찾기')),
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
              if (state.status == JourneySearchStatus.success)
                Text('경로 ${state.response!.journeys.length}개'),
            ],
          ),
        ),
      ),
    );
  }
}
