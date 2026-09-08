import 'package:flutter/material.dart';

import '../../get_off_alarm/get_off_alarm_port.dart';
import '../../get_off_alarm/get_off_alarm_scheduler.dart';
import '../../get_off_alarm/get_off_alarm_subscription.dart';
import '../application/journey_get_off_alarm_binding.dart';
import '../application/journey_search_controller.dart';

typedef JourneyStationNameResolver = Future<String> Function(String stationId);

JourneyAlarmSubscriptionIdentity journeyAlarmIdentityForSnapshot(
  JourneySelectedSnapshot snapshot,
) {
  final identity = JourneySelectedIdentity.fromSnapshot(snapshot);
  return JourneyAlarmSubscriptionIdentity(
    contractVersion: identity.contractVersion,
    requestId: identity.requestId,
    queryId: identity.queryId,
    journeyId: identity.journeyId,
    calculatedAt: identity.calculatedAt,
    validUntil: identity.validUntil,
    effectiveDepartureTime: identity.effectiveDepartureTime,
    serviceDate: identity.serviceDate,
    serviceTimezone: identity.serviceTimezone,
    sourceIdentity: identity.sourceIdentity,
    requestPolicy: identity.requestPolicy,
  );
}

/// 선택한 Journey V3 후보만 하차 알림으로 결속하는 접근 가능한 토글.
class JourneyGetOffAlarmToggle extends StatefulWidget {
  const JourneyGetOffAlarmToggle({
    required this.snapshot,
    required this.controller,
    required this.stationNameResolver,
    this.now = DateTime.now,
    super.key,
  });

  final JourneySelectedSnapshot snapshot;
  final GetOffAlarmPort controller;
  final JourneyStationNameResolver stationNameResolver;
  final DateTime Function() now;

  @override
  State<JourneyGetOffAlarmToggle> createState() =>
      _JourneyGetOffAlarmToggleState();
}

class _JourneyGetOffAlarmToggleState extends State<JourneyGetOffAlarmToggle> {
  bool _busy = false;
  String? _error;
  int _generation = 0;

  JourneyAlarmSubscriptionIdentity get _identity =>
      journeyAlarmIdentityForSnapshot(widget.snapshot);

  bool get _enabled =>
      widget.controller.state.enabled &&
      widget.controller.state.activeJourneyIdentity == _identity;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(covariant JourneyGetOffAlarmToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    if (controllerChanged) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    if (controllerChanged ||
        journeyAlarmIdentityForSnapshot(oldWidget.snapshot) != _identity) {
      _generation++;
      _busy = false;
      _error = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    final snapshot = widget.snapshot;
    final controller = widget.controller;
    final stationNameResolver = widget.stationNameResolver;
    final currentTime = widget.now();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!enabled) {
      try {
        await controller.disable();
        _finish(generation);
      } on Object {
        _finish(generation, error: '알림을 끄지 못했어요. 다시 시도해 주세요.');
      }
      return;
    }

    final JourneyGetOffAlarmBinding binding;
    try {
      binding = JourneyGetOffAlarmBinding.fromSnapshot(
        snapshot,
        now: currentTime,
      );
    } on JourneyAlarmBindingException {
      _finish(generation, error: '이 경로로 하차 알림을 켤 수 없어요.');
      return;
    }

    final stops = <GetOffAlarmStop>[];
    try {
      for (final input in binding.stops) {
        final stationName = (await stationNameResolver(input.stationId)).trim();
        if (!_isCurrent(generation)) return;
        if (stationName.isEmpty || stationName == input.stationId) {
          _finish(generation, error: '역 이름을 확인하지 못해 알림을 켜지 않았어요.');
          return;
        }
        stops.add(
          GetOffAlarmStop(
            stationId: input.stationId,
            stationName: stationName,
            arrivalAt: input.arrivalAt,
            kind: switch (input.kind) {
              JourneyAlarmStopKind.transfer => GetOffAlarmKind.transfer,
              JourneyAlarmStopKind.destination => GetOffAlarmKind.destination,
            },
          ),
        );
      }
    } on Object {
      _finish(generation, error: '역 이름을 확인하지 못해 알림을 켜지 않았어요.');
      return;
    }
    if (!_isCurrent(generation)) return;

    try {
      final identity = journeyAlarmIdentityForSnapshot(snapshot);
      final activeIdentity = controller.state.activeJourneyIdentity;
      if (activeIdentity != null && activeIdentity != identity) {
        await controller.disable();
        if (!_isCurrent(generation)) return;
      }
      await controller.enableJourney(
        identity: identity,
        stops: stops,
        transferAlarmEnabled: true,
      );
      if (!_isCurrent(generation)) {
        await controller.disableJourneyIfActive(identity);
        return;
      }
      _finish(generation);
    } on Object {
      _finish(generation, error: '하차 알림을 켜지 못했어요. 다시 시도해 주세요.');
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  void _finish(int generation, {String? error}) {
    if (!_isCurrent(generation)) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final state = widget.controller.state;
    final notice = enabled ? state.inexactNotice : state.permissionNotice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          selected: enabled,
          child: SwitchListTile(
            key: const Key('journey-get-off-alarm-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('하차 알림'),
            subtitle: Text(
              _busy
                  ? '알림을 준비하고 있어요.'
                  : enabled
                  ? '선택한 경로의 환승·도착 전에 알려드려요.'
                  : '환승·도착 전에 알림을 받아요.',
            ),
            value: enabled,
            onChanged: _busy ? null : _toggle,
          ),
        ),
        if (_error case final error?)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              key: const Key('journey-get-off-alarm-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (notice case final notice?)
          Semantics(
            key: const Key('journey-get-off-alarm-notice'),
            container: true,
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(notice),
            ),
          ),
      ],
    );
  }
}
